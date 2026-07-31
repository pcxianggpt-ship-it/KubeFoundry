package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/** Immutable, credential-free configuration captured when an installation job is accepted. */
public record InstallationSnapshotPayload(
        long clusterId,
        String clusterName,
        String kubernetesVersion,
        String kubernetesWorkDir,
        String imageRegistryType,
        List<NodeTarget> nodes) {

    public InstallationSnapshotPayload {
        clusterName = nonBlank(clusterName, "集群名称");
        kubernetesVersion = valueOrEmpty(kubernetesVersion);
        kubernetesWorkDir = nonBlank(kubernetesWorkDir, "Kubernetes 工作目录");
        imageRegistryType = nonBlank(imageRegistryType, "镜像仓库类型");
        nodes = nodes == null ? List.of() : List.copyOf(nodes);
    }

    public static InstallationSnapshotPayload capture(Cluster cluster, List<Node> configuredNodes) {
        if (cluster == null || cluster.getId() == null) {
            throw new IllegalArgumentException("安装快照缺少集群");
        }
        List<NodeTarget> targets = InstallationNodes.normalize(configuredNodes).stream()
                .map(NodeTarget::from)
                .toList();
        if (targets.isEmpty()) throw new IllegalArgumentException("安装快照缺少节点");
        return new InstallationSnapshotPayload(
                cluster.getId(),
                cluster.getName(),
                cluster.getKubernetesVersion(),
                cluster.getKubernetesWorkDir(),
                cluster.getImageRegistryType(),
                targets);
    }

    public record NodeTarget(
            long id,
            String hostname,
            String ip,
            String sshUser,
            int sshPort,
            Set<String> roles) {

        public NodeTarget {
            hostname = nonBlank(hostname, "节点主机名");
            ip = nonBlank(ip, "节点 IP");
            sshUser = nonBlank(sshUser, "节点 SSH 用户");
            if (sshPort < 1 || sshPort > 65535) {
                throw new IllegalArgumentException("节点 SSH 端口不合法");
            }
            roles = roles == null ? Set.of() : Set.copyOf(roles);
            if (roles.isEmpty()) throw new IllegalArgumentException("节点角色不能为空");
        }

        static NodeTarget from(Node node) {
            if (node == null || node.getId() == null) {
                throw new IllegalArgumentException("安装快照包含未保存节点");
            }
            Set<String> roles = new LinkedHashSet<>(node.getRoles());
            if (roles.isEmpty() && node.getRole() != null && !node.getRole().isBlank()) {
                roles.add(node.getRole());
            }
            return new NodeTarget(
                    node.getId(), node.getHostname(), node.getIp(), node.getSshUser(),
                    node.getSshPort(), roles);
        }
    }

    private static String nonBlank(String value, String field) {
        if (value == null || value.isBlank()) throw new IllegalArgumentException(field + "不能为空");
        return value.trim();
    }

    private static String valueOrEmpty(String value) {
        return value == null ? "" : value.trim();
    }
}
