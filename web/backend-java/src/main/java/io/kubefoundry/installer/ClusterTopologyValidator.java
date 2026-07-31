package io.kubefoundry.installer;

import io.kubefoundry.cluster.Node;
import java.util.List;

/** Validates the node topology before a remote job is allowed to start. */
final class ClusterTopologyValidator {
    private ClusterTopologyValidator() { }

    static void requireValid(List<Node> nodes, String registryType) {
        int controls = 0;
        int workers = 0;
        int registries = 0;
        for (Node node : nodes) {
            boolean control = hasRole(node, "control_plane");
            boolean worker = hasRole(node, "worker");
            if (control && worker) {
                throw new IllegalArgumentException("同一台服务器不能同时配置控制节点和工作节点角色: " + node.getHostname());
            }
            if (control) controls++;
            if (worker) workers++;
            if (hasRole(node, "registry")) registries++;
        }
        if (controls == 0) throw new IllegalArgumentException("至少需要配置一个控制节点");
        if (workers == 0) throw new IllegalArgumentException("至少需要配置一个工作节点");
        if (registries > 1) throw new IllegalArgumentException("镜像仓库角色只能配置在一台服务器上");
        if ("REGISTRY".equals(registryType) && registries != 1) {
            throw new IllegalArgumentException("当前版本仅支持安装 Registry，必须配置一个镜像仓库角色");
        }
        if (!"REGISTRY".equals(registryType)) {
            throw new IllegalArgumentException("当前版本仅支持安装 Registry，Harbor 将在后续版本开放");
        }
    }

    private static boolean hasRole(Node node, String role) {
        return node.hasRole(role) || role.equals(node.getRole());
    }
}
