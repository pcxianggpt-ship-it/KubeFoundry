package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.util.Map;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class InstallationSnapshotPayloadTest {

    @Test
    void capturesOnlyStableCredentialFreeConfiguration() {
        Cluster cluster = new Cluster("snapshot-cluster");
        ReflectionTestUtils.setField(cluster, "id", 7L);
        cluster.updateInstallationConfiguration("/data/kubernetes", "REGISTRY");
        Node node = new Node(cluster);
        ReflectionTestUtils.setField(node, "id", 9L);
        node.update("cp-1", "10.0.0.10", "", "control_plane", "root", 22);
        node.replaceRoles(List.of("control_plane", "registry"));

        InstallationSnapshotPayload payload = InstallationSnapshotPayload.capture(cluster, List.of(node));

        assertThat(payload.clusterId()).isEqualTo(7L);
        assertThat(payload.kubernetesWorkDir()).isEqualTo("/data/kubernetes");
        assertThat(payload.nodes()).singleElement().satisfies(target -> {
            assertThat(target.id()).isEqualTo(9L);
            assertThat(target.roles()).containsExactlyInAnyOrder("control_plane", "registry");
            assertThat(target.sshUser()).isEqualTo("root");
        });
    }

    @Test
    void capturesNormalizedComponentConfigurationAndMediaChecksums() {
        Cluster cluster = new Cluster("component-snapshot");
        ReflectionTestUtils.setField(cluster, "id", 8L);
        cluster.updateInstallationConfiguration("/data/kubernetes", "REGISTRY");
        cluster.markComponentConfigurationChanged();
        Node node = new Node(cluster);
        ReflectionTestUtils.setField(node, "id", 10L);
        node.update("cp-1", "10.0.0.10", "", "control_plane", "root", 22);

        InstallationSnapshotPayload payload = InstallationSnapshotPayload.capture(cluster, List.of(node), List.of(
                new InstallationSnapshotPayload.ComponentGroup("nfs", true, Map.of(
                        "storage_class", "nfs-storage", "server_address", "10.0.0.20"))),
                Map.of("kubemate/helm", "A".repeat(64)));

        assertThat(payload.componentConfigurationVersion()).isEqualTo(1);
        assertThat(payload.componentGroups()).singleElement().satisfies(group -> {
            assertThat(group.key()).isEqualTo("nfs");
            assertThat(group.config()).containsEntry("server_address", "10.0.0.20");
        });
        assertThat(payload.mediaChecksums()).containsEntry("kubemate/helm", "a".repeat(64));
    }

    @Test
    void rejectsSensitiveComponentConfigurationBeforeSnapshotSerialization() {
        assertThatThrownBy(() -> new InstallationSnapshotPayload.ComponentGroup(
                "kubemate", true, Map.of("api_token", "must-not-persist")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("敏感配置");
    }
}
