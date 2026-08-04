package io.kubefoundry.job;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponentState;
import io.kubefoundry.cluster.ClusterComponentStateRepository;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:job-service;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate"
})
class JobServiceTest {

    @Autowired
    ClusterRepository clusters;

    @Autowired
    JobRepository jobs;

    @Autowired
    JobService service;

    @Autowired
    NodeRepository nodes;

    @Autowired
    JobStepRepository steps;

    @Autowired
    JobStepNodeRepository stepNodes;

    @Autowired
    JobEventRepository events;

    @Autowired
    ClusterComponentStateRepository componentStates;

    @Autowired
    JobExecutor executor;

    @AfterEach
    void cleanUp() {
        clusters.deleteAll();
    }

    @Test
    void marksOnlyRunningJobsInterruptedAtStartupRecovery() {
        Cluster cluster = clusters.save(new Cluster("recovery-test"));
        Job pending = jobs.save(new Job(cluster, "install"));
        Job running = new Job(cluster, "precheck");
        running.markRunning();
        running = jobs.save(running);
        Job finished = new Job(cluster, "install");
        finished.markSuccess();
        finished = jobs.save(finished);

        assertThat(service.recoverInterruptedJobs()).isEqualTo(1);

        assertThat(jobs.findById(pending.getId()).orElseThrow().getStatus()).isEqualTo("pending");
        assertThat(jobs.findById(running.getId()).orElseThrow().getStatus()).isEqualTo("interrupted");
        assertThat(jobs.findById(finished.getId()).orElseThrow().getStatus()).isEqualTo("success");
    }

    @Test
    void submitPersistsPartialFailureAndOrderedEvents() throws Exception {
        Cluster cluster = clusters.save(new Cluster("execution-test"));
        Node first = node(cluster, "node-1", "10.0.0.1");
        Node second = node(cluster, "node-2", "10.0.0.2");
        List<JobService.NodeOperation> operations = List.of(
                new JobService.NodeOperation(first.getId(), () -> { }),
                new JobService.NodeOperation(second.getId(), () -> {
                    throw new IllegalStateException("连接失败");
                }));
        JobService.JobDefinition definition = new JobService.JobDefinition(
                cluster.getId(), "node_test", List.of(
                        new JobService.StepDefinition("测试节点", 1, operations)));
        long jobId = service.submit(definition);

        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(jobs.findById(jobId).orElseThrow().getStatus()).isEqualTo("failed");
        JobStep step = steps.findByJobIdOrderByOrder(jobId).get(0);
        assertThat(step.getStatus()).isEqualTo("failed");
        assertThat(stepNodes.findByStepIdOrderById(step.getId()))
                .extracting(JobStepNode::getStatus)
                .containsExactly("success", "failed");
        assertThat(events.findTop100ByJobIdAndIdGreaterThanOrderById(jobId, 0))
                .extracting(JobEvent::getType)
                .startsWith("job.status", "step.status")
                .endsWith("step.status", "job.status");
    }

    @Test
    void invalidNodeDoesNotLeaveOrphanJob() {
        Cluster cluster = clusters.save(new Cluster("invalid-node-test"));

        org.assertj.core.api.Assertions.assertThatThrownBy(() -> service.submit(
                        new JobService.JobDefinition(cluster.getId(), "node_test", List.of(
                                new JobService.StepDefinition("测试节点", 1, List.of(
                                        new JobService.NodeOperation(999999, () -> { })))))))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("节点不存在");
        assertThat(jobs.count()).isZero();
    }

    @Test
    void persistsNodeExitCodeLogPathAndFailureMessage() throws Exception {
        Cluster cluster = clusters.save(new Cluster("node-outcome-test"));
        Node node = node(cluster, "node-1", "10.0.0.1");
        JobService.NodeOperation operation = JobService.NodeOperation.withOutcome(node.getId(), jobId ->
                new JobService.NodeOutcome(false, 23, "远程执行失败", "logs/node-1.log"));

        long jobId = service.submit(new JobService.JobDefinition(
                cluster.getId(), "install", List.of(
                        new JobService.StepDefinition("执行安装步骤", 1, 1, true, List.of(operation)))));
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        JobStep step = steps.findByJobIdOrderByOrder(jobId).get(0);
        JobStepNode item = stepNodes.findByStepIdOrderById(step.getId()).get(0);
        assertThat(item.getStatus()).isEqualTo("failed");
        assertThat(item.getExitCode()).isEqualTo(23);
        assertThat(item.getMessage()).isEqualTo("远程执行失败");
        assertThat(item.getLogPath()).isEqualTo("logs/node-1.log");
    }

    @Test
    void publishesNodeRunningAndTerminalStatusForOutcomeOperations() throws Exception {
        Cluster cluster = clusters.save(new Cluster("node-running-event-test"));
        Node node = node(cluster, "node-1", "10.0.0.1");

        long jobId = service.submit(new JobService.JobDefinition(
                cluster.getId(), "install", List.of(
                        new JobService.StepDefinition("执行安装步骤", 1, 1, true, List.of(
                                JobService.NodeOperation.withOutcome(node.getId(), ignored ->
                                        new JobService.NodeOutcome(true, 0, "执行成功", "logs/node-1.log")))))));
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(events.findTop100ByJobIdAndIdGreaterThanOrderById(jobId, 0).stream()
                .filter(event -> "node.status".equals(event.getType()))
                .map(event -> (String) event.getPayload().get("status")))
                .containsExactly("running", "success");
    }

    @Test
    void recordsEachComponentGroupAsSoonAsItsStepsFinish() throws Exception {
        Cluster cluster = clusters.save(new Cluster("component-group-status"));
        Node node = node(cluster, "node-1", "10.0.0.1");
        ClusterComponentState traefik = componentStates.save(new ClusterComponentState(cluster, "traefik"));
        ClusterComponentState prometheus = componentStates.save(new ClusterComponentState(cluster, "prometheus"));
        ClusterComponentState kubemate = componentStates.save(new ClusterComponentState(cluster, "kubemate"));

        long jobId = service.submit(new JobService.JobDefinition(cluster.getId(), "component_install", List.of(
                new JobService.StepDefinition("安装 Traefik", 1, 1, true, List.of(
                        new JobService.NodeOperation(node.getId(), () -> { })), "traefik"),
                new JobService.StepDefinition("安装 Prometheus", 2, 1, true, List.of(
                        new JobService.NodeOperation(node.getId(), () -> {
                            throw new IllegalStateException("Prometheus 安装失败");
                        })), "prometheus"),
                new JobService.StepDefinition("安装 Kubemate", 3, 1, true, List.of(
                        new JobService.NodeOperation(node.getId(), () -> { })), "kubemate"))));
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(componentStates.findById(traefik.getId()).orElseThrow().getStatus())
                .isEqualTo(ClusterComponentState.INSTALLED);
        assertThat(componentStates.findById(prometheus.getId()).orElseThrow())
                .satisfies(state -> {
                    assertThat(state.getStatus()).isEqualTo(ClusterComponentState.FAILED);
                    assertThat(state.getLastJobId()).isEqualTo(jobId);
                    assertThat(state.getLastErrorCode()).isEqualTo("COMPONENT_INSTALL_FAILED");
                });
        assertThat(componentStates.findById(kubemate.getId()).orElseThrow().getStatus())
                .isEqualTo(ClusterComponentState.NOT_INSTALLED);
    }

    @Test
    void recoversUnstartedComponentGroupsWithoutMarkingThemFailed() {
        Cluster cluster = clusters.save(new Cluster("component-recovery"));
        Node node = node(cluster, "node-1", "10.0.0.1");
        ClusterComponentState state = componentStates.save(new ClusterComponentState(cluster, "traefik"));
        Job job = jobs.save(new Job(cluster, "component_install"));
        state.markInstalling(job.getId());
        componentStates.save(state);
        steps.save(new JobStep(job, "安装 Traefik", 1, "traefik"));

        assertThat(service.recoverInterruptedJobs()).isEqualTo(1);

        assertThat(jobs.findById(job.getId()).orElseThrow().getStatus()).isEqualTo("interrupted");
        assertThat(componentStates.findById(state.getId()).orElseThrow().getStatus())
                .isEqualTo(ClusterComponentState.NOT_INSTALLED);
    }

    private Node node(Cluster cluster, String hostname, String ip) {
        Node node = new Node(cluster);
        node.update(hostname, ip, "", "worker", "root", 22);
        return nodes.save(node);
    }
}
