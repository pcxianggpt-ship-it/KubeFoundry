package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;

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
}
