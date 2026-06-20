import unittest
from unittest.mock import patch

from kubefoundry.installer.health import (
    check_cluster_health,
    evaluate_cluster_health,
)


class ClusterHealthTestCase(unittest.TestCase):
    def setUp(self):
        self.master = {
            "id": 1,
            "hostname": "master-1",
            "ip": "10.0.0.10",
            "role": "control_plane",
        }
        self.worker = {
            "id": 2,
            "hostname": "worker-1",
            "ip": "10.0.0.11",
            "role": "worker",
        }
        self.context = {
            "control_plane": [self.master],
            "workers": [self.worker],
            "ssh": {},
        }

    def test_healthy_cluster_passes(self):
        result = evaluate_cluster_health(
            expected_nodes=["master-1", "worker-1"],
            ready_nodes=["master-1", "worker-1"],
            not_ready_nodes=[],
            failed_pods=[],
            flannel_ready=2,
        )

        self.assertTrue(result["ok"])
        self.assertEqual("cluster health check passed", result["message"])

    def test_not_ready_node_and_failed_pod_fail(self):
        result = evaluate_cluster_health(
            expected_nodes=["master-1", "worker-1"],
            ready_nodes=["master-1"],
            not_ready_nodes=["worker-1"],
            failed_pods=["kube-system/coredns-1:CrashLoopBackOff"],
            flannel_ready=1,
        )

        self.assertFalse(result["ok"])
        self.assertIn("worker-1", result["message"])
        self.assertIn("coredns-1", result["message"])
        self.assertIn("flannel ready 1/2", result["message"])

    def test_remote_health_check_parses_nodes_pods_and_flannel(self):
        node_output = (
            "master-1 Ready control-plane 10m v1.30.14\n"
            "worker-1 Ready <none> 8m v1.30.14\n"
        )
        pod_output = (
            "kube-system coredns-1 1/1 Running 0 8m\n"
            "kube-flannel kube-flannel-ds-a 1/1 Running 0 8m\n"
            "kube-flannel kube-flannel-ds-b 1/1 Running 0 8m\n"
        )
        with patch(
            "kubefoundry.installer.health.run_ssh",
            side_effect=[
                (0, node_output, ""),
                (0, pod_output, ""),
            ],
        ):
            code, out, err = check_cluster_health(
                self.master, self.context
            )

        self.assertEqual(0, code)
        self.assertEqual("", err)
        self.assertIn("cluster health check passed", out)
        self.assertIn(node_output.strip(), out)
        self.assertIn(pod_output.strip(), out)

    def test_remote_health_check_reports_kubectl_failure(self):
        with patch(
            "kubefoundry.installer.health.run_ssh",
            return_value=(1, "", "connection refused"),
        ):
            code, out, err = check_cluster_health(
                self.master, self.context
            )

        self.assertEqual(1, code)
        self.assertEqual("", out)
        self.assertIn("connection refused", err)


if __name__ == "__main__":
    unittest.main()
