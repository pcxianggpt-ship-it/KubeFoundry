package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponentState;
import io.kubefoundry.cluster.ClusterComponentStateRepository;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobService;
import io.kubefoundry.job.JobStep;
import io.kubefoundry.job.JobStepRepository;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.LongSupplier;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
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
                mock(ClusterComponentStateRepository.class), mock(JobStepRepository.class));

        assertThatThrownBy(() -> service.start(1L, false, "RESET production"))
                .isInstanceOf(ResetConfirmationMismatchException.class);
        assertThatThrownBy(() -> service.start(1L, true, "RESET"))
                .isInstanceOf(ResetConfirmationMismatchException.class);
        assertThatThrownBy(() -> service.start(1L, true, "RESET another-cluster"))
                .isInstanceOf(ResetConfirmationMismatchException.class);
    }

    @Test
    void allowsFailedInstallResetWithoutAddingHelmCleanupWhenHelmNeverCompleted() {
        Fixture fixture = fixture("failed");
        JobStep environment = completedStep(fixture.cluster(), "15-environment-config", null, 1);
        when(fixture.jobSteps().findByJobIdOrderByOrder(70L)).thenReturn(List.of(environment));

        long jobId = fixture.service().start(1L, true, "RESET production");

        assertThat(jobId).isEqualTo(91L);
        JobService.JobDefinition definition = capturedDefinition(fixture.jobs());
        assertThat(definition.steps()).extracting(JobService.StepDefinition::name)
                .containsExactly("重置主控制节点", "验证重置结果")
                .doesNotContain("清理 Kubemate 受管组件");
    }

    @Test
    void ignoresAbortedHelmSkipAndFailedComponentStateWhenBuildingResetPlan() {
        Fixture fixture = fixture("failed");
        JobStep helm = completedStep(fixture.cluster(), "29-install-helm", null, 16);
        helm.markSkipped("JOB_ABORTED");
        ClusterComponentState kubemate = new ClusterComponentState(fixture.cluster(), "kubemate");
        kubemate.markFailed("INSTALL_FAILED", 70L);
        when(fixture.componentStates().findByClusterIdOrderByComponentKey(1L))
                .thenReturn(List.of(kubemate));
        when(fixture.jobSteps().findByJobIdOrderByOrder(70L)).thenReturn(List.of(helm));

        fixture.service().start(1L, true, "RESET production");

        JobService.JobDefinition definition = capturedDefinition(fixture.jobs());
        assertThat(definition.steps()).extracting(JobService.StepDefinition::name)
                .containsExactly("重置主控制节点", "验证重置结果")
                .doesNotContain("清理 Kubemate 受管组件");
    }

    @Test
    void addsComponentCleanupOnlyWhenHelmAndManagedComponentHaveExecutionEvidence() {
        Fixture fixture = fixture("success");
        JobStep helm = completedStep(fixture.cluster(), "29-install-helm", null, 1);
        JobStep kubemate = completedStep(fixture.cluster(), "40-install-kubemate", "kubemate", 2);
        when(fixture.jobSteps().findByJobIdOrderByOrder(70L)).thenReturn(List.of(helm, kubemate));

        fixture.service().start(1L, true, "RESET production");

        JobService.JobDefinition definition = capturedDefinition(fixture.jobs());
        assertThat(definition.steps()).extracting(JobService.StepDefinition::name)
                .containsExactly("清理 Kubemate 受管组件", "重置主控制节点", "验证重置结果");
    }

    @Test
    void rejectsResetWhileLatestInstallIsStillActive() {
        Fixture fixture = fixture("running");

        assertThatThrownBy(() -> fixture.service().start(1L, true, "RESET production"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("未处于可重置终态");
    }

    @Test
    void retainsFailedSharedOpenEbsEvidenceBeforeAnyConsumerHasRun() {
        Fixture fixture = fixture("failed");
        JobStep helm = completedStep(fixture.cluster(), "29-install-helm", null, 1);
        JobStep openEbs = completedStep(fixture.cluster(), "47-install-openebs", null, 2);
        openEbs.markFailed();
        when(fixture.jobSteps().findByJobIdOrderByOrder(70L)).thenReturn(List.of(helm, openEbs));

        fixture.service().start(1L, true, "RESET production");

        assertThat(capturedDefinition(fixture.jobs()).steps()).extracting(JobService.StepDefinition::name)
                .containsExactly("清理 Kubemate 受管组件", "重置主控制节点", "验证重置结果");
    }

    private static Fixture fixture(String installStatus) {
        ClusterRepository clusters = mock(ClusterRepository.class);
        NodeRepository nodes = mock(NodeRepository.class);
        JobService jobs = mock(JobService.class);
        RemoteStepRunner runner = mock(RemoteStepRunner.class);
        InstallerAdmission admission = mock(InstallerAdmission.class);
        InstallationSnapshotService snapshots = mock(InstallationSnapshotService.class);
        ResetPlanFactory plans = mock(ResetPlanFactory.class);
        ClusterComponentStateRepository componentStates = mock(ClusterComponentStateRepository.class);
        JobStepRepository jobSteps = mock(JobStepRepository.class);
        Cluster cluster = new Cluster("production");
        ReflectionTestUtils.setField(cluster, "id", 1L);
        Node control = new Node(cluster);
        ReflectionTestUtils.setField(control, "id", 10L);
        control.update("cp-1", "10.0.0.10", "", "control_plane", "root", 22);
        control.replaceRoles(Set.of("control_plane"));
        InstallationSnapshotPayload payload = new InstallationSnapshotPayload(
                1L, "production", "v1.30.14", "/data/k8s_install", "registry",
                List.of(new InstallationSnapshotPayload.NodeTarget(
                        10L, "cp-1", "10.0.0.10", "root", 22,
                        Set.of("control_plane"), "amd64", "", "")),
                1L, List.of(), InstallationSnapshotPayload.COMPONENT_PLAN_VERSION, Map.of());
        when(clusters.findById(1L)).thenReturn(Optional.of(cluster));
        when(nodes.findByClusterIdOrderById(1L)).thenReturn(List.of(control));
        when(snapshots.latestInstallContext(1L)).thenReturn(
                new InstallationSnapshotService.LatestInstallContext(payload, 70L, installStatus));
        when(componentStates.findByClusterIdOrderByComponentKey(1L)).thenReturn(List.of());
        when(plans.runtimeSettings(eq(payload), any())).thenReturn(
                new RuntimeSettings(Map.of(), Map.of(), Map.of()));
        when(plans.componentCleanupStep()).thenReturn(step("component-cleanup"));
        when(plans.nodeCleanupStep()).thenReturn(step("node-cleanup"));
        when(plans.nodeVerificationStep()).thenReturn(step("node-verification"));
        when(admission.submit(eq(1L), any(LongSupplier.class))).thenAnswer(invocation ->
                invocation.getArgument(1, LongSupplier.class).getAsLong());
        when(jobs.submit(any(JobService.JobDefinition.class))).thenReturn(91L);
        return new Fixture(new ClusterResetService(
                clusters, nodes, jobs, runner, admission, snapshots, plans, componentStates, jobSteps),
                cluster, jobs, componentStates, jobSteps);
    }

    private static InstallStep step(String key) {
        return InstallStep.builtin(key, key, "reset", "snapshot_node", "cluster_health",
                "serial", 1, true, "");
    }

    private static JobStep completedStep(Cluster cluster, String stepKey, String group, int order) {
        JobStep step = new JobStep(new Job(cluster, "install"), stepKey, order, group,
                stepKey, "test", "测试", 1, order);
        step.markSuccess();
        return step;
    }

    private static JobService.JobDefinition capturedDefinition(JobService jobs) {
        ArgumentCaptor<JobService.JobDefinition> captor = ArgumentCaptor.forClass(JobService.JobDefinition.class);
        verify(jobs).submit(captor.capture());
        return captor.getValue();
    }

    private record Fixture(
            ClusterResetService service,
            Cluster cluster,
            JobService jobs,
            ClusterComponentStateRepository componentStates,
            JobStepRepository jobSteps) { }
}
