package io.kubefoundry.installer;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ResetPlanFactoryTest {

    @Test
    void acceptsOnlyNonSensitiveAbsoluteWorkDirectories() {
        assertThat(ResetPlanFactory.requireSafeWorkDir("/data/kubernetes"))
                .isEqualTo("/data/kubernetes");
    }

    @Test
    void rejectsDangerousOrRelativeWorkDirectories() {
        for (String unsafe : new String[] {"", "/", "/etc/kubernetes", "/var/lib/kubernetes",
                "/root/kubernetes", "relative/path", "/data/../etc/kubernetes", "/data/ok\nvalue"}) {
            assertThatThrownBy(() -> ResetPlanFactory.requireSafeWorkDir(unsafe))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessage("Kubernetes 工作目录不安全，拒绝执行远程重置");
        }
    }

    @Test
    void resetScriptsKeepRegistryCleanupAndVerificationBehindExplicitGuards() throws Exception {
        Path root = InstallPlanFactory.discoverProjectRoot(Path.of(""));
        String cleanup = Files.readString(root.resolve("scripts/steps/reset/reset-kubernetes-node.sh"));
        String verification = Files.readString(
                root.resolve("scripts/verify/reset/verify-reset-kubernetes-node.sh"));

        assertThat(cleanup)
                .contains("cleanup_registry", "remove_system_directory", "has_role registry",
                        "unmount_managed_mounts", "findmnt -rn -o TARGET", "umount -l",
                        "systemctl stop containerd || fail", "cleanup_managed_nfs",
                        "remove_managed_block", "# >>>KubeFoundry NFS fstab>>>",
                        "# >>>KubeFoundry NFS exports>>>")
                .doesNotContain("rm -rf --one-file-system -- /etc/kubernetes");
        assertThat(Files.readString(root.resolve("scripts/steps/reset/reset-kubemate-components.sh")))
                .contains("helm get metadata", "KF_RESET_HELM_RELEASE_CHECKSUMS",
                        "app.kubernetes.io/managed-by", "kubefoundry.io/media-sha256");
        assertThat(cleanup.lastIndexOf("cleanup_registry"))
                .isLessThan(cleanup.indexOf("systemctl stop containerd || fail"));
        assertThat(cleanup.indexOf("systemctl stop containerd || fail"))
                .isLessThan(cleanup.indexOf("remove_managed_directory \"${KF_CONTAINERD_ROOT:-}\""));
        assertThat(verification)
                .contains("verify_registry", "assert_absent /etc/kubernetes", "kubelet 服务仍在运行");
    }

    @Test
    void buildsCleanupGroupsFromSnapshotAndNonTerminalComponentStates() {
        InstallationSnapshotPayload payload = new InstallationSnapshotPayload(1L, "cluster", "v1", "/data/k8s",
                "local", List.of(), true, 1L, List.of(
                        new InstallationSnapshotPayload.ComponentGroup("nfs", true, java.util.Map.of()),
                        new InstallationSnapshotPayload.ComponentGroup("traefik", false, java.util.Map.of())),
                "v0.3.0", java.util.Map.of());
        io.kubefoundry.cluster.Cluster cluster = new io.kubefoundry.cluster.Cluster("cluster");
        io.kubefoundry.cluster.ClusterComponentState state =
                new io.kubefoundry.cluster.ClusterComponentState(cluster, "traefik");
        state.markFailed("INSTALL_FAILED", 1L);

        assertThat(ResetPlanFactory.componentGroups(payload, List.of(state)))
                .containsExactlyInAnyOrder("nfs", "traefik");
    }

    @Test
    void exposesOnlySnapshotCheckedHelmMediaForReset() {
        InstallationSnapshotPayload payload = new InstallationSnapshotPayload(1L, "cluster", "v1", "/data/k8s",
                "local", List.of(), true, 1L, List.of(), "v0.3.0", java.util.Map.of(
                        "kube-media/03.setup_file/v1/helmapp/alloy", "a".repeat(64),
                        "kube-media/03.setup_file/v1/helmapp/loki", "b".repeat(64)));

        RuntimeSettings settings = new ResetPlanFactory(".").runtimeSettings(payload,
                java.util.Set.of("storage_observability"));

        assertThat(settings.envValue("reset_helm_release_checksums"))
                .isEqualTo("alloy=" + "a".repeat(64) + ",loki=" + "b".repeat(64));
    }
}
