package io.kubefoundry.installer;

import io.kubefoundry.cluster.ClusterComponentState;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
class ResetPlanFactory {

    private final Path script;
    private final Path verifyScript;
    private final Path componentCleanupScript;

    ResetPlanFactory(@Value("${kubefoundry.app-dir:${user.dir}}") String appDirectory) {
        Path root = InstallPlanFactory.discoverProjectRoot(Path.of(appDirectory));
        script = root.resolve("scripts/steps/reset/reset-kubernetes-node.sh").normalize();
        verifyScript = root.resolve("scripts/verify/reset/verify-reset-kubernetes-node.sh").normalize();
        componentCleanupScript = root.resolve("scripts/steps/reset/reset-kubemate-components.sh").normalize();
        if (!Files.isRegularFile(script)) {
            throw new IllegalStateException("远程重置脚本不存在: " + script);
        }
        if (!Files.isRegularFile(verifyScript)) {
            throw new IllegalStateException("远程重置验证脚本不存在: " + verifyScript);
        }
        if (!Files.isRegularFile(componentCleanupScript)) {
            throw new IllegalStateException("组件重置清理脚本不存在: " + componentCleanupScript);
        }
    }

    InstallStep componentCleanupStep() {
        return InstallStep.script("reset-kubemate-components", "清理 Kubemate 受管组件", "reset",
                "primary_control_plane", componentCleanupScript, "serial", 1, true,
                List.of(), List.of(), List.of(), "");
    }

    InstallStep nodeCleanupStep() {
        return InstallStep.script("reset-kubernetes-node", "清理 Kubernetes 节点", "reset",
                "snapshot_node", script, "parallel", 3, true,
                java.util.List.of(), java.util.List.of(), java.util.List.of(), "");
    }

    InstallStep nodeVerificationStep() {
        return InstallStep.script("verify-reset-kubernetes-node", "验证 Kubernetes 节点清理", "reset",
                "snapshot_node", verifyScript, "parallel", 3, true,
                java.util.List.of(), java.util.List.of(), java.util.List.of(), "");
    }

    RuntimeSettings runtimeSettings(InstallationSnapshotPayload payload, Set<String> componentGroups) {
        String workDir = requireSafeWorkDir(payload.kubernetesWorkDir());
        String groups = String.join(",", componentGroups == null ? Set.of() : componentGroups);
        String releaseChecksums = releaseChecksums(payload, componentGroups);
        return new RuntimeSettings(
                Map.of("k8s_home", workDir),
                Map.of(
                        "kubelet_root", workDir + "/kubelet_root",
                        "containerd_root", workDir + "/containerd_root",
                        "etcd_data_dir", workDir + "/etcd_root",
                        "reset_component_groups", groups,
                        "reset_helm_release_checksums", releaseChecksums),
                Map.of());
    }

    private static String releaseChecksums(InstallationSnapshotPayload payload, Set<String> componentGroups) {
        Map<String, String> paths = new java.util.LinkedHashMap<>();
        paths.put("alloy", "helmapp/alloy");
        paths.put("loki", "helmapp/loki");
        paths.put("openebs", "helmapp/openebs");
        paths.put("nfs-subdir-external-provisioner", "helmapp/nfs/nfs-subdir-external-provisioner");
        Set<String> enabled = componentGroups == null ? Set.of() : componentGroups;
        List<String> entries = new java.util.ArrayList<>();
        for (Map.Entry<String, String> entry : paths.entrySet()) {
            String group = "nfs-subdir-external-provisioner".equals(entry.getKey()) ? "nfs"
                    : "storage_observability";
            if (!enabled.contains(group)) continue;
            payload.mediaChecksums().entrySet().stream()
                    .filter(value -> value.getKey().endsWith(entry.getValue()))
                    .map(Map.Entry::getValue)
                    .findFirst().ifPresent(checksum -> entries.add(entry.getKey() + "=" + checksum));
        }
        return String.join(",", entries);
    }

    static Set<String> componentGroups(
            InstallationSnapshotPayload payload, List<ClusterComponentState> states) {
        if (payload == null) throw new IllegalArgumentException("重置缺少安装快照");
        Set<String> result = new LinkedHashSet<>();
        payload.componentGroups().stream().filter(InstallationSnapshotPayload.ComponentGroup::enabled)
                .map(InstallationSnapshotPayload.ComponentGroup::key)
                .filter(ResetPlanFactory::isCleanupGroup).forEach(result::add);
        for (ClusterComponentState state : states == null ? List.<ClusterComponentState>of() : states) {
            if (state != null && isCleanupGroup(state.getComponentKey())
                    && !ClusterComponentState.NOT_INSTALLED.equals(state.getStatus())) {
                result.add(state.getComponentKey());
            }
        }
        return Set.copyOf(result);
    }

    private static boolean isCleanupGroup(String group) {
        return Set.of("nfs", "kubemate", "traefik", "storage_observability", "prometheus")
                .contains(group);
    }

    static String requireSafeWorkDir(String value) {
        if (value == null || value.isBlank() || value.indexOf('\u0000') >= 0
                || value.chars().anyMatch(Character::isISOControl)) {
            throw new IllegalArgumentException("Kubernetes 工作目录不安全，拒绝执行远程重置");
        }
        String candidate = value.trim();
        if (!candidate.matches("/[A-Za-z0-9._/-]+")) {
            throw new IllegalArgumentException("Kubernetes 工作目录不安全，拒绝执行远程重置");
        }
        java.util.List<String> segments = java.util.Arrays.stream(candidate.split("/"))
                .filter(segment -> !segment.isBlank()).toList();
        if (segments.size() < 2 || segments.stream()
                .anyMatch(segment -> ".".equals(segment) || "..".equals(segment))) {
            throw new IllegalArgumentException("Kubernetes 工作目录不安全，拒绝执行远程重置");
        }
        String normalized = "/" + String.join("/", segments);
        if (isReservedPath(normalized)) {
            throw new IllegalArgumentException("Kubernetes 工作目录不安全，拒绝执行远程重置");
        }
        return normalized;
    }

    private static boolean isReservedPath(String path) {
        return java.util.List.of("/etc", "/usr", "/var", "/root").stream()
                .anyMatch(root -> path.equals(root) || path.startsWith(root + "/"));
    }
}
