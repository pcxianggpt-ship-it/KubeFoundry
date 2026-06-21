import json
import os
import shutil
import tempfile
import unittest

from kubefoundry.api.routes import create_app
from kubefoundry.installer.context import build_cluster_context, context_to_yaml_data
from kubefoundry.installer.plan import (
    STEP_PLAN,
    resolve_targets,
    validate_selected_plan,
    validate_step_resources,
)
from kubefoundry.installer.runtime import render_runtime_env
from kubefoundry.installer.validator import validate_cluster_context
from kubefoundry.store.db import init_db
from kubefoundry.store.repository import Repository


class ApiTestCase(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix="kubefoundry-test-")
        self.old_db_path = os.environ.get("KF_DB_PATH")
        self.old_data_dir = os.environ.get("KF_DATA_DIR")
        self.old_frontend_dist = os.environ.get("KF_FRONTEND_DIST")
        os.environ["KF_DATA_DIR"] = self.temp_dir
        os.environ["KF_DB_PATH"] = os.path.join(self.temp_dir, "kubefoundry.db")
        self.frontend_dist = os.path.join(self.temp_dir, "frontend-dist")
        os.makedirs(os.path.join(self.frontend_dist, "assets"))
        with open(
            os.path.join(self.frontend_dist, "index.html"),
            "w",
            encoding="utf-8",
            newline="\n",
        ) as fh:
            fh.write("<html>KubeFoundry production</html>\n")
        with open(
            os.path.join(self.frontend_dist, "assets", "app.js"),
            "w",
            encoding="utf-8",
            newline="\n",
        ) as fh:
            fh.write("console.log('production asset');\n")
        os.environ["KF_FRONTEND_DIST"] = self.frontend_dist
        init_db()
        self.app = create_app()
        self.app.config["TESTING"] = True
        self.client = self.app.test_client()

    def tearDown(self):
        if self.old_db_path is None:
            os.environ.pop("KF_DB_PATH", None)
        else:
            os.environ["KF_DB_PATH"] = self.old_db_path
        if self.old_data_dir is None:
            os.environ.pop("KF_DATA_DIR", None)
        else:
            os.environ["KF_DATA_DIR"] = self.old_data_dir
        if self.old_frontend_dist is None:
            os.environ.pop("KF_FRONTEND_DIST", None)
        else:
            os.environ["KF_FRONTEND_DIST"] = self.old_frontend_dist
        shutil.rmtree(self.temp_dir)

    def test_frontend_static_files_and_spa_fallback(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertIn("KubeFoundry production", response.get_data(as_text=True))
        response.close()

        response = self.client.get("/assets/app.js")
        self.assertEqual(response.status_code, 200)
        self.assertIn("production asset", response.get_data(as_text=True))
        response.close()

        response = self.client.get("/clusters/1/install")
        self.assertEqual(response.status_code, 200)
        self.assertIn("KubeFoundry production", response.get_data(as_text=True))
        response.close()

        response = self.client.get("/api/not-found")
        self.assertEqual(response.status_code, 404)
        response.close()

    def test_cluster_node_settings_context_and_runtime_env(self):
        response = self.client.post(
            "/api/clusters",
            json={"name": "demo", "k8s_version": "1.30.14", "registry_ip": "10.0.0.10"},
        )
        self.assertEqual(response.status_code, 201)
        cluster_id = response.get_json()["id"]

        response = self.client.post(
            "/api/clusters/%s/nodes" % cluster_id,
            json={
                "hostname": "master-1",
                "ip": "10.0.0.10",
                "role": "control_plane",
                "ssh_port": 2222,
            },
        )
        self.assertEqual(response.status_code, 201)
        node = response.get_json()

        response = self.client.put(
            "/api/clusters/%s/settings" % cluster_id,
            json={
                "paths": {"k8s_home": "/opt/k8s", "install_media": "/opt/media"},
                "ecosystem": {"traefik": True},
            },
        )
        self.assertEqual(response.status_code, 200)

        context = build_cluster_context(cluster_id)
        self.assertEqual(context["paths"]["k8s_home"], "/opt/k8s")
        self.assertTrue(context["ecosystem"]["traefik"])

        yaml_data = context_to_yaml_data(context)
        self.assertEqual(yaml_data["ssh"]["port"], 2222)

        runtime_env = render_runtime_env(context, node)
        self.assertIn("export KF_CLUSTER_NAME=demo", runtime_env)
        self.assertIn("export KF_NODE_IP=10.0.0.10", runtime_env)
        self.assertIn('export K8S_HOME="${KF_K8S_HOME}"', runtime_env)
        self.assertIn("log_info()", runtime_env)
        self.assertIn("export -f log_info", runtime_env)

    def test_jobs_require_nodes(self):
        cluster = self.client.post("/api/clusters", json={"name": "empty"}).get_json()
        response = self.client.post("/api/clusters/%s/precheck" % cluster["id"])
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"], "cluster has no nodes")

        response = self.client.post("/api/clusters/%s/install" % cluster["id"])
        self.assertEqual(response.status_code, 400)

    def test_cluster_validation_and_step_validation(self):
        repo = Repository()
        cluster = repo.create_cluster(
            {
                "name": "invalid",
                "pod_subnet": "10.96.0.0/16",
                "service_subnet": "10.96.0.0/24",
            }
        )
        repo.create_node(
            cluster["id"],
            {"hostname": "master-1", "ip": "10.0.0.10", "role": "control_plane"},
        )
        context = build_cluster_context(cluster["id"])
        repo.close()
        with self.assertRaisesRegex(ValueError, "must not overlap"):
            validate_cluster_context(context)
        with self.assertRaisesRegex(ValueError, "unknown installation steps"):
            validate_selected_plan(["does-not-exist"])
        with self.assertRaisesRegex(ValueError, "requires output"):
            validate_selected_plan(["20-add-control-nodes"])

    def test_containerd_resource_validation(self):
        repo = Repository()
        cluster = repo.create_cluster({"name": "resources", "registry_ip": "10.0.0.10"})
        master = repo.create_node(
            cluster["id"],
            {"hostname": "master-1", "ip": "10.0.0.10", "role": "control_plane"},
        )
        worker = repo.create_node(
            cluster["id"],
            {"hostname": "worker-1", "ip": "10.0.0.11", "role": "worker"},
        )
        media_dir = os.path.join(self.temp_dir, "media")
        container_dir = os.path.join(media_dir, "02.container_runtime")
        os.makedirs(container_dir)
        repo.upsert_cluster_settings(
            cluster["id"],
            {"paths": {"install_media": media_dir, "container_runtime": container_dir}},
        )
        context = build_cluster_context(cluster["id"])
        plan = validate_selected_plan(["16-install-containerd"])
        self.assertTrue(validate_step_resources(plan, context))
        targets = resolve_targets(plan[0], context)
        self.assertEqual([master["id"], worker["id"]], [item["id"] for item in targets])

    def test_full_phase2_plan_and_resources(self):
        repo = Repository()
        cluster = repo.create_cluster({"name": "full-plan", "registry_ip": "10.0.0.10"})
        repo.create_node(
            cluster["id"],
            {"hostname": "master-1", "ip": "10.0.0.10", "role": "control_plane"},
        )
        repo.create_node(
            cluster["id"],
            {"hostname": "worker-1", "ip": "10.0.0.11", "role": "worker"},
        )
        media_dir = os.path.join(self.temp_dir, "media")
        rpm_dir = os.path.join(media_dir, "01.rpm_package")
        runtime_dir = os.path.join(media_dir, "02.container_runtime")
        setup_dir = os.path.join(media_dir, "03.setup_file")
        registry_dir = os.path.join(media_dir, "04.registry")
        for path in [rpm_dir, runtime_dir, setup_dir, registry_dir]:
            os.makedirs(path)
        repo_source = os.path.join(rpm_dir, "repo.tar.gz")
        kubeadm_file = os.path.join(rpm_dir, "kubeadm")
        flannel_file = os.path.join(setup_dir, "kube-flannel.yml")
        for path in [repo_source, kubeadm_file, flannel_file]:
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write("test\n")
        repo.upsert_cluster_settings(
            cluster["id"],
            {
                "paths": {
                    "install_media": media_dir,
                    "repo_source": repo_source,
                    "kubeadm_100y": kubeadm_file,
                    "container_runtime": runtime_dir,
                    "registry_install": registry_dir,
                    "flannel_config": flannel_file,
                }
            },
        )
        context = build_cluster_context(cluster["id"])
        plan = validate_selected_plan()
        self.assertEqual("10-setup-yum-source", plan[0]["key"])
        self.assertEqual("web-verify-cluster-health", plan[-1]["key"])
        self.assertEqual(14, len(STEP_PLAN))
        self.assertTrue(validate_step_resources(plan, context))

    def test_install_plan_and_yaml_round_trip(self):
        response = self.client.get("/api/install-plan")
        self.assertEqual(response.status_code, 200)
        plan = response.get_json()["items"]
        self.assertEqual(14, len(plan))
        self.assertEqual("10-setup-yum-source", plan[0]["key"])
        self.assertEqual("web-verify-cluster-health", plan[-1]["key"])

        cluster = self.client.post(
            "/api/clusters",
            json={"name": "yaml-demo", "registry_ip": "10.0.0.10"},
        ).get_json()
        cluster_id = cluster["id"]
        self.client.post(
            "/api/clusters/%s/nodes" % cluster_id,
            json={"hostname": "master-1", "ip": "10.0.0.10", "role": "control_plane"},
        )
        self.client.put(
            "/api/clusters/%s/settings" % cluster_id,
            json={"ecosystem": {"traefik": True}, "advanced": {"enable_ipv6_dual_stack": False}},
        )

        response = self.client.get("/api/clusters/%s/config-yaml" % cluster_id)
        self.assertEqual(response.status_code, 200)
        yaml_text = response.get_data(as_text=True)
        self.assertIn("name: yaml-demo", yaml_text)
        self.assertIn("traefik: true", yaml_text)

        updated_yaml = yaml_text.replace("name: yaml-demo", "name: yaml-imported")
        response = self.client.post(
            "/api/clusters/%s/import-yaml" % cluster_id,
            json={"content": updated_yaml},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual("yaml-imported", response.get_json()["cluster"]["name"])

    def test_ssh_credentials_are_key_only_and_sanitized(self):
        cluster = self.client.post("/api/clusters", json={"name": "ssh"}).get_json()
        cluster_id = cluster["id"]
        response = self.client.put(
            "/api/clusters/%s/ssh-credentials" % cluster_id,
            json={"auth_type": "password", "username": "root", "password_encrypted": "secret"},
        )
        self.assertEqual(response.status_code, 400)

        response = self.client.put(
            "/api/clusters/%s/ssh-credentials" % cluster_id,
            json={"auth_type": "key", "username": "admin", "private_key_path": "/keys/id_rsa"},
        )
        self.assertEqual(response.status_code, 200)
        credentials = response.get_json()
        self.assertEqual(credentials["auth_type"], "key")
        self.assertNotIn("password_encrypted", credentials)
        self.assertNotIn("sudo_password_encrypted", credentials)

    def test_terminal_job_event_stream(self):
        repo = Repository()
        cluster = repo.create_cluster({"name": "events"})
        job = repo.create_job(cluster["id"], "precheck", {}, "", self.temp_dir)
        repo.add_event(job["id"], "job.status", {"status": "success"})
        repo.update_job(job["id"], status="success")

        response = self.client.get("/api/jobs/%s/events" % job["id"], buffered=True)
        self.assertEqual(response.status_code, 200)
        body = response.get_data(as_text=True)
        self.assertIn("event: job.status", body)
        self.assertIn('"status": "success"', body)

    def test_invalid_event_cursor(self):
        repo = Repository()
        cluster = repo.create_cluster({"name": "events"})
        job = repo.create_job(cluster["id"], "precheck", {}, "", self.temp_dir)
        response = self.client.get("/api/jobs/%s/events?last_id=bad" % job["id"])
        self.assertEqual(response.status_code, 400)

    def test_job_step_node_log_endpoint(self):
        repo = Repository()
        cluster = repo.create_cluster({"name": "logs"})
        node = repo.create_node(
            cluster["id"],
            {"hostname": "worker-1", "ip": "10.0.0.11", "role": "worker"},
        )
        job = repo.create_job(cluster["id"], "install", {}, "", self.temp_dir)
        step = repo.create_job_step(
            job["id"],
            {
                "key": "test-step",
                "name": "Test Step",
                "phase": "test",
                "target_scope": "workers",
            },
        )
        log_path = os.path.join(self.temp_dir, "worker-1.log")
        with open(log_path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("hello node log\n")
        item = repo.create_job_step_node(step["id"], node["id"], log_path)
        repo.close()

        response = self.client.get("/api/job-step-nodes/%s/log" % item["id"])
        self.assertEqual(response.status_code, 200)
        self.assertIn("hello node log", response.get_json()["content"])


if __name__ == "__main__":
    unittest.main()
