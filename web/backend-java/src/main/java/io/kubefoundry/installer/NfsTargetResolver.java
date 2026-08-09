package io.kubefoundry.installer;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponentRepository;
import io.kubefoundry.cluster.Node;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/** Resolves the managed NFS server node and renders its non-sensitive runtime values. */
@Component
public class NfsTargetResolver {
    private final ClusterComponentRepository components;
    private final ObjectMapper mapper;

    public NfsTargetResolver(ClusterComponentRepository components, ObjectMapper mapper) {
        this.components = components;
        this.mapper = mapper;
    }

    public List<Node> resolve(InstallStep step, Cluster cluster, List<Node> nodes) {
        if (step == null || !"nfs_server".equals(step.targetScope()) || cluster == null) return null;
        Map<String, String> config = configuration(cluster.getId());
        if ("external".equals(config.get("exports_mode"))) {
            Node primary = PrimaryControlPlaneSelector.select(InstallationNodes.normalize(nodes));
            return primary == null ? List.of() : List.of(primary);
        }
        String address = config.getOrDefault("server_address", "");
        return InstallationNodes.normalize(nodes).stream()
                .filter(node -> "success".equalsIgnoreCase(node.getNodeTestStatus()))
                .filter(node -> address.equals(node.getIp()) || address.equals(node.getHostname()))
                .toList();
    }

    public Map<String, String> runtimeValues(Cluster cluster) {
        if (cluster == null) return Map.of();
        Map<String, String> config = configuration(cluster.getId());
        if (config.isEmpty()) return Map.of();
        Map<String, String> values = new LinkedHashMap<>();
        values.put("KF_NFS_SERVER", config.getOrDefault("server_address", ""));
        values.put("KF_NFS_SHARE_PATH", config.getOrDefault("share_path", ""));
        values.put("KF_NFS_WORKER_MOUNT_PATH", config.getOrDefault("worker_mount_path", ""));
        values.put("KF_NFS_STORAGE_CLASS", config.getOrDefault("storage_class", ""));
        values.put("KF_NFS_EXPORTS_MODE", config.getOrDefault("exports_mode", ""));
        return Map.copyOf(values);
    }

    public String missingTargetMessage(Cluster cluster, List<Node> nodes) {
        Map<String, String> config = cluster == null ? Map.of() : configuration(cluster.getId());
        String address = config.getOrDefault("server_address", "");
        String candidates = InstallationNodes.normalize(nodes).stream()
                .filter(node -> "success".equalsIgnoreCase(node.getNodeTestStatus()))
                .map(node -> node.getHostname() + "（" + node.getIp() + "）")
                .sorted()
                .collect(java.util.stream.Collectors.joining("、"));
        if (candidates.isBlank()) candidates = "无";
        return "NFS 服务端地址“" + address + "”未匹配任何通过节点测试的集群节点。"
                + "请将 NFS 服务端地址改为以下节点 IP 之一：" + candidates
                + "；如果使用集群外部 NFS，请将导出模式改为“外部”。";
    }

    private Map<String, String> configuration(long clusterId) {
        return components.findByClusterIdAndComponentKey(clusterId, "nfs")
                .map(component -> parse(component.getConfigJson()))
                .orElse(Map.of());
    }

    private Map<String, String> parse(String json) {
        if (json == null || json.isBlank()) return Map.of();
        try {
            Map<?, ?> raw = mapper.readValue(json, Map.class);
            Map<String, String> values = new LinkedHashMap<>();
            raw.forEach((key, value) -> {
                if (key != null && value != null) values.put(key.toString(), value.toString());
            });
            return values;
        } catch (JsonProcessingException exception) {
            return Map.of();
        }
    }
}
