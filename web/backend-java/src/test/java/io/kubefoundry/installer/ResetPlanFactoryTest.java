package io.kubefoundry.installer;

import java.nio.file.Files;
import java.nio.file.Path;
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
                        "systemctl stop containerd || fail")
                .doesNotContain("rm -rf --one-file-system -- /etc/kubernetes");
        assertThat(cleanup.lastIndexOf("cleanup_registry"))
                .isLessThan(cleanup.indexOf("systemctl stop containerd || fail"));
        assertThat(cleanup.indexOf("systemctl stop containerd || fail"))
                .isLessThan(cleanup.indexOf("remove_managed_directory \"${KF_CONTAINERD_ROOT:-}\""));
        assertThat(verification)
                .contains("verify_registry", "assert_absent /etc/kubernetes", "kubelet 服务仍在运行");
    }
}
