package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponentState;
import io.kubefoundry.cluster.ClusterComponentStateRepository;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobStep;
import io.kubefoundry.job.JobStepRepository;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ComponentInstallationStateServiceTest {

    @Test
    void preverifiedStepsKeepTheComponentInstalledWhenAResumeCompletes() {
        Fixture fixture = fixture("PREVERIFY_SATISFIED");

        fixture.service().complete(fixture.job(), true);

        assertThat(fixture.state().getStatus()).isEqualTo(ClusterComponentState.INSTALLED);
        assertThat(fixture.state().getLastErrorCode()).isNull();
    }

    @Test
    void anUnrelatedSkippedStepDoesNotMarkTheComponentInstalled() {
        Fixture fixture = fixture("COMPONENT_GROUP_PREVIOUS_STEP_FAILED");

        fixture.service().complete(fixture.job(), true);

        assertThat(fixture.state().getStatus()).isEqualTo(ClusterComponentState.FAILED);
        assertThat(fixture.state().getLastErrorCode()).isEqualTo("COMPONENT_STATE_INCOMPLETE");
    }

    private Fixture fixture(String skipReason) {
        Cluster cluster = mock(Cluster.class);
        when(cluster.getId()).thenReturn(1L);
        Job job = mock(Job.class);
        when(job.getId()).thenReturn(7L);
        when(job.getType()).thenReturn("install");
        when(job.getCluster()).thenReturn(cluster);

        ClusterComponentState state = new ClusterComponentState(cluster, "nfs");
        state.markInstalling(job.getId());
        JobStep step = new JobStep(job, "部署 NFS 组件", 1, "nfs");
        step.markSkipped(skipReason);

        ClusterComponentStateRepository states = mock(ClusterComponentStateRepository.class);
        when(states.findByClusterIdAndComponentKey(1L, "nfs")).thenReturn(Optional.of(state));
        JobStepRepository steps = mock(JobStepRepository.class);
        when(steps.findByJobIdOrderByOrder(7L)).thenReturn(List.of(step));
        return new Fixture(new ComponentInstallationStateService(states, steps), job, state);
    }

    private record Fixture(
            ComponentInstallationStateService service,
            Job job,
            ClusterComponentState state) {
    }
}
