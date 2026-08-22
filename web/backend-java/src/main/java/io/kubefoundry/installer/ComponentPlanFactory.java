package io.kubefoundry.installer;

import io.kubefoundry.cluster.KubemateComponentCatalog;
import java.nio.file.Path;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/** Builds the deterministic component graph exclusively from an immutable snapshot. */
@Component
public class ComponentPlanFactory {
    private final Path scripts;
    private final Path verifyScripts;
    private final ComponentMediaService media;

    public ComponentPlanFactory(Path projectRoot) {
        this(new ComponentMediaService(projectRoot));
    }

    @Autowired
    public ComponentPlanFactory(ComponentMediaService media) {
        this.media = media;
        this.scripts = media.projectRoot().resolve("scripts/steps/phase3_ecosystem");
        this.verifyScripts = media.projectRoot().resolve("scripts/verify/phase3_ecosystem");
    }

    public InstallPlan create(InstallationSnapshotPayload snapshot) {
        return create(snapshot, null);
    }

    public InstallPlan create(InstallationSnapshotPayload snapshot, Set<String> candidateGroups) {
        if (snapshot == null) throw new IllegalArgumentException("组件计划缺少安装快照");
        Set<String> requested = candidateGroups == null ? null : Set.copyOf(candidateGroups);
        List<String> enabled = KubemateComponentCatalog.GROUPS.stream()
                .filter(KubemateComponentCatalog.Group::available)
                .map(KubemateComponentCatalog.Group::key)
                .filter(key -> isEnabled(snapshot, key))
                .filter(key -> requested == null || requested.contains(key))
                .toList();
        if (requested != null) validateRequested(snapshot, requested, enabled);
        if (enabled.isEmpty()) return new InstallPlan(List.of());

        java.util.ArrayList<InstallStep> steps = new java.util.ArrayList<>();
        steps.add(script(snapshot, "29-install-helm", "安装 Helm", "primary_control_plane", null,
                "serial", 1, true));
        steps.add(script(snapshot, "30-create-namespace", "创建 Kubemate 命名空间",
                "primary_control_plane", null, "serial", 1, true));
        for (String key : enabled) steps.addAll(groupSteps(snapshot, key));
        return new InstallPlan(steps);
    }

    private List<InstallStep> groupSteps(InstallationSnapshotPayload snapshot, String groupKey) {
        return switch (groupKey) {
            case "nfs" -> List.of(
                    script(snapshot, "32-configure-nfs-exports", "配置 NFS exports", "nfs_server", groupKey,
                            "serial", 1, true),
                    script(snapshot, "32-install-nfs", "安装 NFS Provisioner", "primary_control_plane", groupKey,
                            "serial", 1, true),
                    script(snapshot, "32-mount-nfs-workers", "挂载 NFS 工作节点", "workers", groupKey,
                            "parallel", 5, false));
            case "kubemate" -> List.of(script(snapshot, "31-install-kubemate-ui", "安装 Kubemate 管理组件",
                    "primary_control_plane", groupKey, "serial", 1, true));
            case "traefik" -> List.of(script(snapshot, "36-install-traefik", "安装 Traefik 网关",
                    "primary_control_plane", groupKey, "serial", 1, true));
            case "storage_observability" -> List.of(
                    script(snapshot, "46-prepare-storage-workers", "准备存储 Worker 目录", "workers", groupKey,
                            "parallel", 5, true),
                    script(snapshot, "47-install-openebs", "安装 OpenEBS", "primary_control_plane", groupKey,
                            "serial", 1, true),
                    script(snapshot, "49-install-minio", "安装 MinIO", "primary_control_plane", groupKey,
                            "serial", 1, true),
                    script(snapshot, "35-install-loki", "安装 Loki", "primary_control_plane", groupKey,
                            "serial", 1, true),
                    script(snapshot, "48-install-alloy", "安装 Alloy", "primary_control_plane", groupKey,
                            "serial", 1, true));
            case "prometheus" -> List.of(
                    script(snapshot, "37-prepare-prometheus-workers", "准备 Prometheus Worker 目录", "workers",
                            groupKey, "parallel", 5, true),
                    script(snapshot, "38-install-prometheus", "安装 Prometheus", "primary_control_plane", groupKey,
                            "serial", 1, true));
            default -> throw new IllegalArgumentException("组件组不可安装: " + groupKey);
        };
    }

    private InstallStep script(InstallationSnapshotPayload snapshot, String key, String name, String scope,
            String groupKey, String mode, int maxWorkers, boolean failFast) {
        List<InstallStep.Resource> resources = "29-install-helm".equals(key)
                ? List.of(media.helmResource(snapshot))
                : requiresComponentMedia(key)
                        ? List.of(media.componentResource(snapshot, groupKey, key)) : List.of();
        return new InstallStep(key, name, "kubemate_component", scope, scripts.resolve(key + ".sh"), null,
                mode, maxWorkers, failFast, resources, List.of(), List.of(), "", groupKey)
                .withVerification(verifyScripts.resolve("verify-" + key + ".sh"));
    }

    private static boolean requiresComponentMedia(String key) {
        return List.of("31-install-kubemate-ui", "32-install-nfs", "36-install-traefik",
                "47-install-openebs", "49-install-minio", "35-install-loki", "48-install-alloy",
                "38-install-prometheus").contains(key);
    }

    private static boolean isEnabled(InstallationSnapshotPayload snapshot, String groupKey) {
        return snapshot.componentGroups().stream()
                .anyMatch(group -> group.key().equals(groupKey) && group.enabled());
    }

    private static void validateRequested(
            InstallationSnapshotPayload snapshot, Set<String> requested, List<String> enabled) {
        Set<String> valid = new LinkedHashSet<>(enabled);
        Set<String> invalid = new java.util.TreeSet<>(requested);
        invalid.removeAll(valid);
        if (!invalid.isEmpty()) {
            throw new IllegalArgumentException("组件组未启用、不可用或已安装: " + String.join(", ", invalid));
        }
    }
}
