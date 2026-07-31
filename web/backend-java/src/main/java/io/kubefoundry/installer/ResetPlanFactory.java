package io.kubefoundry.installer;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
class ResetPlanFactory {

    private final Path script;

    ResetPlanFactory(@Value("${kubefoundry.app-dir:${user.dir}}") String appDirectory) {
        Path root = InstallPlanFactory.discoverProjectRoot(Path.of(appDirectory));
        script = root.resolve("scripts/steps/reset/reset-kubernetes-node.sh").normalize();
        if (!Files.isRegularFile(script)) {
            throw new IllegalStateException("远程重置脚本不存在: " + script);
        }
    }

    InstallStep nodeCleanupStep() {
        return InstallStep.script("reset-kubernetes-node", "清理 Kubernetes 节点", "reset",
                "snapshot_node", script, "parallel", 3, true,
                java.util.List.of(), java.util.List.of(), java.util.List.of(), "");
    }

    RuntimeSettings runtimeSettings(InstallationSnapshotPayload payload) {
        String workDir = requireSafeWorkDir(payload.kubernetesWorkDir());
        return new RuntimeSettings(
                Map.of("k8s_home", workDir),
                Map.of(
                        "kubelet_root", workDir + "/kubelet_root",
                        "containerd_root", workDir + "/containerd_root",
                        "etcd_data_dir", workDir + "/etcd_root"),
                Map.of());
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
