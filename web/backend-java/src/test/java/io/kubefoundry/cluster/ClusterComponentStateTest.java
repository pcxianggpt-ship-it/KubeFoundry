package io.kubefoundry.cluster;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ClusterComponentStateTest {

    @Test
    void transitionsFromNotInstalledToInstalledAndBackToNotInstalled() {
        ClusterComponentState state = new ClusterComponentState(new Cluster("state-cluster"), "nfs");

        assertThat(state.getStatus()).isEqualTo(ClusterComponentState.NOT_INSTALLED);

        state.markInstalling(11L);
        assertThat(state.getStatus()).isEqualTo(ClusterComponentState.INSTALLING);
        assertThat(state.getLastJobId()).isEqualTo(11L);

        state.markInstalled("1", 11L);
        assertThat(state.getStatus()).isEqualTo(ClusterComponentState.INSTALLED);
        assertThat(state.getInstalledVersion()).isEqualTo("1");
        assertThat(state.getLastErrorCode()).isNull();

        state.reset();
        assertThat(state.getStatus()).isEqualTo(ClusterComponentState.NOT_INSTALLED);
        assertThat(state.getInstalledVersion()).isNull();
        assertThat(state.getLastJobId()).isNull();
    }

    @Test
    void rejectsBlankClusterAndComponentKeys() {
        assertThatThrownBy(() -> new ClusterComponentState(null, "nfs"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("集群不能为空");
        assertThatThrownBy(() -> new ClusterComponentState(new Cluster("state-cluster"), " "))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("组件组标识不能为空");
    }
}
