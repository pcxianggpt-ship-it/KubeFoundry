package io.kubefoundry.installer;

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
}
