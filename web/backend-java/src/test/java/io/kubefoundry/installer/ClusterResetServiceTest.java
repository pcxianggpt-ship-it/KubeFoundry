package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponentStateRepository;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.JobService;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ClusterResetServiceTest {

    @Test
    void rejectsRequestsWithoutExactServerSideConfirmationPhrase() {
        ClusterRepository clusters = mock(ClusterRepository.class);
        Cluster cluster = new Cluster("production");
        ReflectionTestUtils.setField(cluster, "id", 1L);
        when(clusters.findById(1L)).thenReturn(Optional.of(cluster));
        ClusterResetService service = new ClusterResetService(
                clusters, mock(NodeRepository.class), mock(JobService.class),
                mock(RemoteStepRunner.class), mock(InstallerAdmission.class),
                mock(InstallationSnapshotService.class), mock(ResetPlanFactory.class),
                mock(ClusterComponentStateRepository.class));

        assertThatThrownBy(() -> service.start(1L, false, "RESET production"))
                .isInstanceOf(ResetConfirmationMismatchException.class);
        assertThatThrownBy(() -> service.start(1L, true, "RESET"))
                .isInstanceOf(ResetConfirmationMismatchException.class);
        assertThatThrownBy(() -> service.start(1L, true, "RESET another-cluster"))
                .isInstanceOf(ResetConfirmationMismatchException.class);
    }
}
