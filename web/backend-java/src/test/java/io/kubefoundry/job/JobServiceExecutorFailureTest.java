package io.kubefoundry.job;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:job-service-executor-failure;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate",
        "kubefoundry.jobs.workers=1",
        "kubefoundry.jobs.queue-capacity=1"
})
class JobServiceExecutorFailureTest {

    @Autowired
    ClusterRepository clusters;

    @Autowired
    NodeRepository nodes;

    @Autowired
    JobRepository jobs;

    @Autowired
    JobStepRepository steps;

    @Autowired
    JobStepNodeRepository stepNodes;

    @Autowired
    JobEventRepository events;

    @Autowired
    JobService service;

    @Autowired
    JobExecutor executor;

    @AfterEach
    void cleanUp() {
        clusters.deleteAll();
    }

    @Test
    void nodeExecutorRejectionTerminatesCurrentStepAndNodes() throws Exception {
        Cluster cluster = clusters.save(new Cluster("executor-rejection"));
        List<Node> savedNodes = List.of(
                node(cluster, "node-1", "10.0.0.1"),
                node(cluster, "node-2", "10.0.0.2"),
                node(cluster, "node-3", "10.0.0.3"),
                node(cluster, "node-4", "10.0.0.4"));
        CountDownLatch release = new CountDownLatch(1);
        List<JobService.NodeOperation> operations = savedNodes.stream()
                .map(node -> new JobService.NodeOperation(node.getId(), () -> {
                    try {
                        release.await(5, TimeUnit.SECONDS);
                    } catch (InterruptedException exception) {
                        Thread.currentThread().interrupt();
                        throw exception;
                    }
                })).toList();

        long jobId = service.submit(new JobService.JobDefinition(
                cluster.getId(), "install", List.of(
                        new JobService.StepDefinition("拥塞步骤", 1, 4, false, operations))));
        release.countDown();
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(jobs.findById(jobId).orElseThrow().getStatus()).isEqualTo("failed");
        JobStep step = steps.findByJobIdOrderByOrder(jobId).get(0);
        assertThat(step.getStatus()).isEqualTo("failed");
        assertThat(stepNodes.findByStepIdOrderById(step.getId()))
                .extracting(JobStepNode::getStatus)
                .doesNotContain("running");
        assertThat(events.findTop100ByJobIdAndIdGreaterThanOrderById(jobId, 0))
                .extracting(JobEvent::getType)
                .endsWith("job.status");
    }

    private Node node(Cluster cluster, String hostname, String ip) {
        Node node = new Node(cluster);
        node.update(hostname, ip, "", "worker", "root", 22);
        return nodes.save(node);
    }
}
