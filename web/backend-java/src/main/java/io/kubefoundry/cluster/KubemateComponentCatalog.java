package io.kubefoundry.cluster;

import java.util.List;
import java.util.Map;

/** 固定的 Kubemate 组件组目录，配置和安装计划共用此顺序与元数据。 */
public final class KubemateComponentCatalog {
    public static final List<Group> GROUPS = List.of(
            new Group("nfs", "NFS 存储", List.of("nfs_exports", "nfs_provisioner", "worker_mount"), true),
            new Group("kubemate", "Kubemate 管理组件", List.of("kubemate_ui"), true),
            new Group("traefik", "Traefik 网关", List.of("traefik"), true),
            new Group("storage_observability", "存储与日志套件", List.of("openebs", "minio", "loki", "alloy"), true),
            new Group("prometheus", "Prometheus 监控", List.of("prometheus", "metrics_server"), true),
            new Group("redis_sentinel", "Redis 哨兵模式", List.of("redis_sentinel"), false));

    private static final Map<String, Group> BY_KEY = GROUPS.stream().collect(
            java.util.stream.Collectors.toUnmodifiableMap(Group::key, group -> group));

    private KubemateComponentCatalog() { }

    public static Group find(String key) { return BY_KEY.get(key); }

    public record Group(String key, String name, List<String> components, boolean available) { }
}
