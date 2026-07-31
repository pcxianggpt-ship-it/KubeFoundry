package io.kubefoundry.cluster;

import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ClusterComponentService {
    private static final Set<String> SUPPORTED = Set.of("loki", "traefik", "nfs");
    private final ClusterRepository clusters;
    private final ClusterComponentRepository components;

    public ClusterComponentService(ClusterRepository clusters, ClusterComponentRepository components) {
        this.clusters = clusters;
        this.components = components;
    }

    @Transactional(readOnly = true)
    public List<ComponentResponse> list(long clusterId) {
        requireCluster(clusterId);
        Map<String, Boolean> configured = components.findByClusterIdOrderByComponentKey(clusterId).stream()
                .collect(java.util.stream.Collectors.toMap(ClusterComponent::getComponentKey,
                        ClusterComponent::isEnabled));
        return SUPPORTED.stream().sorted().map(key -> new ComponentResponse(key,
                configured.getOrDefault(key, false))).toList();
    }

    @Transactional
    public List<ComponentResponse> replace(long clusterId, List<ComponentRequest> requests) {
        Cluster cluster = requireCluster(clusterId);
        if (cluster.isInstallationLocked()) {
            throw new ClusterService.ClusterConfigurationLockedException("集群安装成功后必须先完成重置，才能修改 Kubemate 组件配置");
        }
        Map<String, Boolean> values = (requests == null ? List.<ComponentRequest>of() : requests).stream()
                .peek(request -> {
                    if (request.key() == null || !SUPPORTED.contains(request.key())) {
                        throw new IllegalArgumentException("不支持的 Kubemate 组件");
                    }
                }).collect(java.util.stream.Collectors.toMap(ComponentRequest::key,
                        request -> request.enabled(), (left, right) -> right));
        components.deleteByClusterId(clusterId);
        values.forEach((key, enabled) -> components.save(new ClusterComponent(cluster, key, enabled)));
        return list(clusterId);
    }

    private Cluster requireCluster(long id) {
        return clusters.findById(id).orElseThrow(() -> ClusterService.ResourceNotFoundException.cluster(id));
    }

    public record ComponentRequest(String key, boolean enabled) { }
    public record ComponentResponse(String key, boolean enabled) { }
}
