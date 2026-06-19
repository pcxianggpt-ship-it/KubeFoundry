import json
import os
import shutil
import tempfile
import unittest

from kubefoundry.api.routes import create_app
from kubefoundry.installer.context import build_cluster_context, context_to_yaml_data
from kubefoundry.installer.runtime import render_runtime_env
from kubefoundry.store.db import init_db
from kubefoundry.store.repository import Repository


class ApiTestCase(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix="kubefoundry-test-")
        self.old_db_path = os.environ.get("KF_DB_PATH")
        self.old_data_dir = os.environ.get("KF_DATA_DIR")
        os.environ["KF_DATA_DIR"] = self.temp_dir
        os.environ["KF_DB_PATH"] = os.path.join(self.temp_dir, "kubefoundry.db")
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
        shutil.rmtree(self.temp_dir)

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

    def test_jobs_require_nodes(self):
        cluster = self.client.post("/api/clusters", json={"name": "empty"}).get_json()
        response = self.client.post("/api/clusters/%s/precheck" % cluster["id"])
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"], "cluster has no nodes")

        response = self.client.post("/api/clusters/%s/install" % cluster["id"])
        self.assertEqual(response.status_code, 400)

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


if __name__ == "__main__":
    unittest.main()
