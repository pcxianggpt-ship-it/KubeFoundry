package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.KubemateComponentCatalog;
import io.kubefoundry.cluster.Node;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

/** Immutable, credential-free configuration captured when an installation job is accepted. */
public record InstallationSnapshotPayload(
        long clusterId,
        String clusterName,
        String kubernetesVersion,
        String kubernetesWorkDir,
        String imageRegistryType,
        List<NodeTarget> nodes,
        long componentConfigurationVersion,
        List<ComponentGroup> componentGroups,
        String componentPlanVersion,
        Map<String, String> mediaChecksums) {

    public static final String COMPONENT_PLAN_VERSION = "v0.3.1";

    public InstallationSnapshotPayload {
        clusterName = nonBlank(clusterName, "集群名称");
        kubernetesVersion = valueOrEmpty(kubernetesVersion);
        kubernetesWorkDir = nonBlank(kubernetesWorkDir, "Kubernetes 工作目录");
        imageRegistryType = nonBlank(imageRegistryType, "镜像仓库类型");
        nodes = nodes == null ? List.of() : List.copyOf(nodes);
        componentGroups = componentGroups == null ? List.of() : List.copyOf(componentGroups);
        componentPlanVersion = nonBlank(valueOrDefault(componentPlanVersion, COMPONENT_PLAN_VERSION), "组件计划版本");
        mediaChecksums = normalizeChecksums(mediaChecksums);
    }

    public static InstallationSnapshotPayload capture(Cluster cluster, List<Node> configuredNodes) {
        return capture(cluster, configuredNodes, List.of(), Map.of());
    }

    public static InstallationSnapshotPayload capture(
            Cluster cluster,
            List<Node> configuredNodes,
            List<ComponentGroup> componentGroups,
            Map<String, String> mediaChecksums) {
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
                targets,
                cluster.getComponentConfigVersion(),
                componentGroups,
                COMPONENT_PLAN_VERSION,
                mediaChecksums);
    }

    public record ComponentGroup(String key, boolean enabled, Map<String, Object> config) {
        public ComponentGroup {
            if (key == null || KubemateComponentCatalog.find(key) == null) {
                throw new IllegalArgumentException("安装快照包含未知组件组");
            }
            key = key.trim();
            config = normalizeConfig(config, key);
        }
    }

    public record NodeTarget(
            long id,
            String hostname,
            String ip,
            String sshUser,
            int sshPort,
            Set<String> roles,
            String architecture) {

        public NodeTarget {
            hostname = nonBlank(hostname, "节点主机名");
            ip = nonBlank(ip, "节点 IP");
            sshUser = nonBlank(sshUser, "节点 SSH 用户");
            if (sshPort < 1 || sshPort > 65535) {
                throw new IllegalArgumentException("节点 SSH 端口不合法");
            }
            roles = roles == null ? Set.of() : Set.copyOf(roles);
            architecture = architecture == null || architecture.isBlank() ? "amd64" : architecture.trim();
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
                    node.getSshPort(), roles, node.getArchitecture());
        }
    }

    private static Map<String, Object> normalizeConfig(Map<String, Object> value, String path) {
        Map<String, Object> normalized = new TreeMap<>();
        for (Map.Entry<String, Object> entry : (value == null ? Map.<String, Object>of() : value).entrySet()) {
            String key = nonBlank(entry.getKey(), "组件配置字段");
            String nestedPath = path + "." + key;
            if (key.toLowerCase(java.util.Locale.ROOT)
                    .matches(".*(password|token|secret|credential|private[_-]?key).*$")) {
                throw new IllegalArgumentException("安装快照不得包含敏感配置: " + nestedPath);
            }
            normalized.put(key, normalizeConfigValue(entry.getValue(), nestedPath));
        }
        return Map.copyOf(normalized);
    }

    private static Object normalizeConfigValue(Object value, String path) {
        if (value == null) {
            throw new IllegalArgumentException("安装快照配置值不能为空: " + path);
        }
        if (value instanceof String || value instanceof Boolean || value instanceof Number) {
            return value;
        }
        if (value instanceof Map<?, ?> nested) {
            Map<String, Object> converted = new LinkedHashMap<>();
            for (Map.Entry<?, ?> entry : nested.entrySet()) {
                if (!(entry.getKey() instanceof String key)) {
                    throw new IllegalArgumentException("安装快照配置字段必须为字符串: " + path);
                }
                converted.put(key, entry.getValue());
            }
            return normalizeConfig(converted, path);
        }
        if (value instanceof List<?> items) {
            List<Object> normalized = new ArrayList<>();
            for (Object item : items) normalized.add(normalizeConfigValue(item, path));
            return List.copyOf(normalized);
        }
        throw new IllegalArgumentException("安装快照配置值类型不受支持: " + path);
    }

    private static Map<String, String> normalizeChecksums(Map<String, String> values) {
        Map<String, String> normalized = new TreeMap<>();
        for (Map.Entry<String, String> entry : (values == null ? Map.<String, String>of() : values).entrySet()) {
            String path = nonBlank(entry.getKey(), "介质路径");
            String checksum = nonBlank(entry.getValue(), "介质校验和").toLowerCase(java.util.Locale.ROOT);
            if (!checksum.matches("[0-9a-f]{64}")) {
                throw new IllegalArgumentException("介质校验和必须为 SHA-256: " + path);
            }
            normalized.put(path, checksum);
        }
        return Map.copyOf(normalized);
    }

    private static String nonBlank(String value, String field) {
        if (value == null || value.isBlank()) throw new IllegalArgumentException(field + "不能为空");
        return value.trim();
    }

    private static String valueOrEmpty(String value) {
        return value == null ? "" : value.trim();
    }

    private static String valueOrDefault(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }
}
