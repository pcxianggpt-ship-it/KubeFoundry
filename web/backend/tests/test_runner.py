import os
import shutil
import tempfile
import unittest
from unittest.mock import patch

from kubefoundry.installer import runner
from kubefoundry.store.db import init_db
from kubefoundry.store.repository import Repository


class RunnerTestCase(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix="kf-runner-")
        self.old_db_path = os.environ.get("KF_DB_PATH")
        self.old_data_dir = os.environ.get("KF_DATA_DIR")
        os.environ["KF_DATA_DIR"] = self.temp_dir
        os.environ["KF_DB_PATH"] = os.path.join(self.temp_dir, "kubefoundry.db")
        init_db()
        with Repository() as repo:
            self.cluster = repo.create_cluster(
                {"name": "runner", "registry_ip": "10.0.0.10"}
            )
            self.master = repo.create_node(
                self.cluster["id"],
                {
                    "hostname": "master-1",
                    "ip": "10.0.0.10",
                    "role": "control_plane",
                },
            )
            self.worker = repo.create_node(
                self.cluster["id"],
                {
                    "hostname": "worker-1",
                    "ip": "10.0.0.11",
                    "role": "worker",
                },
            )
            self.job = repo.create_job(
                self.cluster["id"], "install", {}, "", self.temp_dir
            )
        self.context = {
            "cluster": self.cluster,
            "nodes": [self.master, self.worker],
            "control_plane": [self.master],
            "workers": [self.worker],
            "registry_nodes": [],
            "registry": {
                "hostname": "registry",
                "ip": "10.0.0.10",
                "port": 5000,
            },
            "ssh": {
                "username": "root",
                "private_key_path": "/tmp/id_rsa",
            },
            "network": {},
            "paths": {},
            "env": {
                "kubelet_root": "/data/kubelet",
                "containerd_root": "/data/containerd",
                "etcd_data_dir": "/data/etcd",
            },
            "storage": {},
            "advanced": {},
            "ecosystem": {},
        }
        self.log_dir = os.path.join(
            self.temp_dir, "jobs", str(self.job["id"]), "logs"
        )

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

    def step(self, key, mode="serial", target_scope="all_nodes"):
        return {
            "key": key,
            "name": key,
            "phase": "test",
            "target_scope": target_scope,
            "builtin": "setup_hostname",
            "mode": mode,
            "max_workers": 2,
            "fail_fast": True,
            "resources": [],
        }

    def test_failed_step_stops_following_steps(self):
        plan = [self.step("first"), self.step("second")]

        with patch(
            "kubefoundry.installer.runner._run_step", return_value=False
        ) as run_step:
            runner._run_install_job(self.job["id"], self.context, plan)

        self.assertEqual(1, run_step.call_count)
        with Repository() as repo:
            self.assertEqual("failed", repo.get_job(self.job["id"])["status"])

    def test_parallel_step_runs_once_per_target(self):
        result = {
            "ok": True,
            "exit_code": 0,
            "message": "执行成功",
            "stdout": "",
            "stderr": "",
        }
        with patch(
            "kubefoundry.installer.runner._run_step_on_node",
            return_value=result,
        ) as run_node:
            ok = runner._run_step(
                self.job["id"],
                self.context,
                self.step("parallel", mode="parallel"),
                self.log_dir,
                {},
            )

        self.assertTrue(ok)
        self.assertEqual(2, run_node.call_count)

    def test_join_artifact_is_collected_and_reused(self):
        artifacts = {}
        output_step = {
            "outputs": [
                {
                    "key": "worker_join",
                    "remote_path": "/tmp/k8s/kube_join_nodes",
                }
            ]
        }
        with patch(
            "kubefoundry.installer.runner.run_ssh",
            return_value=(0, "kubeadm join 10.0.0.10:6443\n", ""),
        ):
            runner._collect_step_outputs(
                self.job["id"],
                self.context,
                output_step,
                [self.master],
                artifacts,
            )
        consumer_step = {
            "resources": [
                {
                    "artifact_key": "worker_join",
                    "remote_path": "/tmp/k8s/kube_join_nodes",
                }
            ]
        }
        with patch(
            "kubefoundry.installer.runner.copy_path_to_node",
            return_value=(0, "", ""),
        ) as copy_path:
            result = runner._copy_step_resources(
                consumer_step, self.context, self.worker, artifacts
            )

        self.assertEqual((0, "", ""), result)
        self.assertTrue(os.path.isfile(artifacts["worker_join"]))
        copy_path.assert_called_once_with(
            artifacts["worker_join"],
            "/tmp/k8s/kube_join_nodes",
            self.worker,
            self.context,
        )

    def test_ssh_exception_marks_node_failed_and_returns_result(self):
        step = self.step("exception", target_scope="workers")
        with Repository() as repo:
            step_row = repo.create_job_step(self.job["id"], step)

        with patch(
            "kubefoundry.installer.runner.run_ssh",
            side_effect=RuntimeError("ssh exploded"),
        ):
            result = runner._run_step_on_node(
                self.job["id"],
                self.context,
                step,
                step_row["id"],
                self.worker,
                self.log_dir,
                {},
            )

        self.assertEqual(
            {
                "ok": False,
                "exit_code": 1,
                "message": "执行失败，退出码: 1",
                "stdout": "",
                "stderr": "ssh exploded",
            },
            result,
        )
        with Repository() as repo:
            node_result = repo.list_job_steps(self.job["id"])[0]["nodes"][0]
        self.assertEqual("failed", node_result["status"])
        self.assertEqual(1, node_result["exit_code"])
        with open(node_result["log_path"], "r", encoding="utf-8") as fh:
            self.assertIn("ssh exploded", fh.read())


if __name__ == "__main__":
    unittest.main()
