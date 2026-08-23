package io.kubefoundry.installer;

/** 安装计划中固定的部署单元定义。 */
public record InstallStage(String key, String name, int order) {

    public static final InstallStage HOST_PREPARATION =
            new InstallStage("host_preparation", "主机与软件源准备", 1);
    public static final InstallStage CONTAINER_RUNTIME =
            new InstallStage("container_runtime", "部署容器运行时", 2);
    public static final InstallStage REGISTRY =
            new InstallStage("registry", "部署镜像仓库", 3);
    public static final InstallStage KUBERNETES =
            new InstallStage("kubernetes", "部署 Kubernetes 集群", 4);
    public static final InstallStage COMPONENT_PREREQUISITE =
            new InstallStage("component_prerequisite", "Kubemate 公共准备", 5);
    public static final InstallStage NFS =
            new InstallStage("nfs", "部署 NFS 组件", 6);
    public static final InstallStage KUBEMATE =
            new InstallStage("kubemate", "部署 Kubemate 管理组件", 7);
    public static final InstallStage TRAEFIK =
            new InstallStage("traefik", "部署 Traefik 网关", 8);
    public static final InstallStage STORAGE_OBSERVABILITY =
            new InstallStage("storage_observability", "部署存储与日志套件", 9);
    public static final InstallStage PROMETHEUS =
            new InstallStage("prometheus", "部署 Prometheus 监控", 10);
    public static final InstallStage REDIS_SENTINEL =
            new InstallStage("redis_sentinel", "部署 Redis Sentinel", 11);
    public static final InstallStage ETCD_BACKUP =
            new InstallStage("etcd_backup", "配置并验证 etcd 备份", 12);
    public static final InstallStage RESET =
            new InstallStage("reset", "重置集群", 1);

    public InstallStage {
        if (key == null || key.isBlank()) throw new IllegalArgumentException("部署单元键不能为空");
        if (name == null || name.isBlank()) throw new IllegalArgumentException("部署单元名称不能为空");
        if (order < 1) throw new IllegalArgumentException("部署单元顺序必须为正整数");
    }
}
