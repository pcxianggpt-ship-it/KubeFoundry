package io.kubefoundry.installer;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponent;
import io.kubefoundry.cluster.ClusterComponentRepository;
import io.kubefoundry.cluster.Node;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class NfsTargetResolverTest {
    @Test
    void managedModeSelectsOnlyTheSuccessfulNodeMatchingServerAddress() {
        ClusterComponentRepository repository = mock(ClusterComponentRepository.class);
        Cluster cluster = cluster(1L);
        ClusterComponent component = new ClusterComponent(cluster, "nfs", true,
                "{\"server_address\":\"10.0.0.10\",\"share_path\":\"/srv/share\","
                        + "\"worker_mount_path\":\"/data/nfs\",\"storage_class\":\"nfs\","
                        + "\"exports_mode\":\"managed\"}");
        when(repository.findByClusterIdAndComponentKey(1L, "nfs")).thenReturn(Optional.of(component));
        NfsTargetResolver resolver = new NfsTargetResolver(repository, new ObjectMapper());
        Node selected = node(cluster, 1L, "nfs", "10.0.0.10", "control_plane", true);
        Node stale = node(cluster, 2L, "other", "10.0.0.10", "worker", false);

        assertThat(resolver.resolve(step(), cluster, List.of(stale, selected)))
                .containsExactly(selected);
    }

    @Test
    void externalModeRunsExportsValidationOnPrimaryControlPlane() {
        ClusterComponentRepository repository = mock(ClusterComponentRepository.class);
        Cluster cluster = cluster(2L);
        ClusterComponent component = new ClusterComponent(cluster, "nfs", true,
                "{\"server_address\":\"10.0.0.99\",\"share_path\":\"/srv/share\","
                        + "\"worker_mount_path\":\"/data/nfs\",\"storage_class\":\"nfs\","
                        + "\"exports_mode\":\"external\"}");
        when(repository.findByClusterIdAndComponentKey(2L, "nfs")).thenReturn(Optional.of(component));
        NfsTargetResolver resolver = new NfsTargetResolver(repository, new ObjectMapper());
        Node primary = node(cluster, 10L, "cp", "10.0.0.1", "control_plane", false);
        Node later = node(cluster, 20L, "cp2", "10.0.0.2", "control_plane", false);

        assertThat(resolver.resolve(step(), cluster, List.of(later, primary))).containsExactly(primary);
        assertThat(resolver.runtimeValues(cluster))
                .containsEntry("KF_NFS_EXPORTS_MODE", "external")
                .containsEntry("KF_NFS_SERVER", "10.0.0.99");
    }

    private static InstallStep step() {
        return InstallStep.componentScript("32-configure-nfs-exports", "NFS", "nfs_server",
                null, "nfs", "serial", 1, true, "");
    }

    private static Cluster cluster(long id) {
        Cluster cluster = new Cluster("nfs-" + id);
        ReflectionTestUtils.setField(cluster, "id", id);
        return cluster;
    }

    private static Node node(Cluster cluster, long id, String hostname, String ip, String role, boolean success) {
        Node node = new Node(cluster);
        ReflectionTestUtils.setField(node, "id", id);
        node.update(hostname, ip, "", role, "root", 22);
        if (success) node.completeNodeTest("linux", "1", "amd64");
        return node;
    }
}
