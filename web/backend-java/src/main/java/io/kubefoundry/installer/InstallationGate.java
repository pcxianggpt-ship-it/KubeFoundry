package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.util.List;

final class InstallationGate {

    private InstallationGate() {
    }

    static void requireSuccessfulNodeTests(Cluster cluster, List<Node> nodes) {
        if (nodes == null || nodes.isEmpty()) {
            throw new IllegalArgumentException("集群没有可用节点");
        }
        if (!"success".equals(cluster.getNodeTestStatus())) {
            throw new IllegalArgumentException(
                    "节点测试状态必须为 success，当前集群状态: " + cluster.getNodeTestStatus());
        }
        for (Node node : nodes) {
            if (node.isDraft() || !"success".equals(node.getNodeTestStatus())) {
                throw new IllegalArgumentException("节点 " + node.getHostname()
                        + " 的测试状态必须为 success，当前状态: " + node.getNodeTestStatus());
            }
        }
    }
}
