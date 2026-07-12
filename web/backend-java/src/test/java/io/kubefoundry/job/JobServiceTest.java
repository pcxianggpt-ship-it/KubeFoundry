package io.kubefoundry.job;

import io.kubefoundry.cluster.Cluster;
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

    private Node node(Cluster cluster, String hostname, String ip) {
        Node node = new Node(cluster);
        node.update(hostname, ip, "", "worker", "root", 22);
        return nodes.save(node);
    }
}
