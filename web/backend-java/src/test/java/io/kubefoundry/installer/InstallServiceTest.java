package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import java.util.function.LongSupplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class InstallServiceTest {

    ClusterRepository clusters;
    NodeRepository nodes;
    JobRepository jobs;
    JobService jobService;
    RemoteStepRunner runner;
    InstallPlanFactory plans;
    InstallerAdmission admission;
    InstallationSnapshotService snapshots;
    Cluster cluster;
    List<Node> configuredNodes;

    @BeforeEach
    void setUp() {
        clusters = mock(ClusterRepository.class);
        nodes = mock(NodeRepository.class);
        jobs = mock(JobRepository.class);
        jobService = mock(JobService.class);
        runner = mock(RemoteStepRunner.class);
        plans = new InstallPlanFactory(Path.of("D:/repo"));
        admission = mock(InstallerAdmission.class);
        snapshots = mock(InstallationSnapshotService.class);
        cluster = new Cluster("service-test");
        cluster.markNodeTestStatus("success");
        Node control = node("cp-a", "10.0.0.1", "control_plane");
        Node worker = node("worker-a", "10.0.0.2", "worker");
        Node registry = node("registry", "10.0.0.3", "registry");
        configuredNodes = List.of(worker, control, registry);
        when(clusters.findById(1L)).thenReturn(Optional.of(cluster));
        when(nodes.findByClusterIdOrderById(1L)).thenReturn(configuredNodes);
        when(jobs.findFirstByClusterIdAndTypeAndStatusInOrderByIdDesc(
                org.mockito.ArgumentMatchers.anyLong(), any(), any()))
                .thenReturn(Optional.empty());
        when(jobService.submit(any())).thenReturn(99L);
        when(admission.submit(org.mockito.ArgumentMatchers.anyLong(), any(LongSupplier.class)))
                .thenAnswer(invocation -> invocation.<LongSupplier>getArgument(1).getAsLong());
    }

    @Test
    void rejectsStaleClusterAndNonSuccessfulNodeTests() {
        cluster.markNodeTestStatus("stale");
        assertThatThrownBy(() -> installService().start(1L, List.of()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("stale");
        assertThatThrownBy(() -> precheckService().start(1L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("stale");

        cluster.markNodeTestStatus("success");
        configuredNodes.get(0).markTestStale(false);
        assertThatThrownBy(() -> installService().start(1L, List.of()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("worker-a");
        assertThatThrownBy(() -> precheckService().start(1L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("worker-a");
    }

    @Test
    void mapsPlanToExistingJobServiceWithPerStepConcurrency() {
        long jobId = installService().start(1L, List.of());

        assertThat(jobId).isEqualTo(99L);
        ArgumentCaptor<JobService.JobDefinition> captor =
                ArgumentCaptor.forClass(JobService.JobDefinition.class);
        verify(jobService).submit(captor.capture());
        JobService.JobDefinition definition = captor.getValue();
        assertThat(definition.type()).isEqualTo("install");
        assertThat(definition.steps()).hasSize(14);
        assertThat(definition.steps().get(3).name()).isEqualTo("安装 Kubernetes 依赖");
        assertThat(definition.steps().get(3).maxWorkers()).isEqualTo(5);
        assertThat(definition.steps().get(8).name()).isEqualTo("初始化 Kubernetes 集群");
        assertThat(definition.steps().get(8).maxWorkers()).isEqualTo(1);
        assertThat(definition.steps().get(10).name()).isEqualTo("加入其他控制节点");
        assertThat(definition.steps().get(10).maxWorkers()).isEqualTo(1);
        assertThat(definition.steps().get(13).name()).isEqualTo("验证 Kubernetes 集群健康");
        assertThat(definition.steps().get(13).maxWorkers()).isEqualTo(1);
        verify(snapshots).capture(eq(99L), eq(cluster), argThat(captured -> captured.stream()
                .map(Node::getId).toList().equals(List.of(1L, 2L, 3L))));
    }

    @Test
    void precheckIsCallableThroughJobServiceWithoutCreatingAnotherExecutor() {
        long jobId = precheckService().start(1L);

        assertThat(jobId).isEqualTo(99L);
        ArgumentCaptor<JobService.JobDefinition> captor =
                ArgumentCaptor.forClass(JobService.JobDefinition.class);
        verify(jobService).submit(captor.capture());
        JobService.JobDefinition definition = captor.getValue();
        assertThat(definition.type()).isEqualTo("precheck");
        assertThat(definition.steps()).singleElement().satisfies(step -> {
            assertThat(step.name()).isEqualTo("节点环境预检查");
            assertThat(step.maxWorkers()).isEqualTo(5);
            assertThat(step.nodes()).hasSize(3);
        });
    }

    private InstallService installService() {
        return new InstallService(clusters, nodes, jobService, plans, runner, null, admission, snapshots);
    }

    private PrecheckService precheckService() {
        return new PrecheckService(clusters, nodes, jobs, jobService, runner, null, null, admission);
    }

    private Node node(String hostname, String ip, String role) {
        Node node = new Node(cluster);
        long id = "cp-a".equals(hostname) ? 1L : "worker-a".equals(hostname) ? 2L : 3L;
        ReflectionTestUtils.setField(node, "id", id);
        node.update(hostname, ip, "", role, "root", 22);
        node.completeNodeTest("kylin", "V10", "amd64");
        return node;
    }
}
