package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobExecutor;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.stubbing.Answer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.when;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:install-job-concurrency;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate",
        "kubefoundry.jobs.workers=6",
        "kubefoundry.jobs.queue-capacity=50"
})
class InstallJobConcurrencyIntegrationTest {

    @Autowired
    ClusterRepository clusters;

    @Autowired
    NodeRepository nodes;

    @Autowired
    JobRepository jobs;

    @Autowired
    InstallService installs;

    @Autowired
    JobExecutor executor;

    @MockBean
    RemoteStepRunner runner;

    Cluster cluster;

    @BeforeEach
    void setUp() {
        cluster = new Cluster("install-concurrency-" + System.nanoTime());
        cluster.update(null, null, "1.30.2", "10.244.0.0/16", "10.96.0.0/12",
                "registry", "10.0.0.20", 5000, null);
        cluster.markNodeTestStatus("success");
        cluster = clusters.saveAndFlush(cluster);
        saveNode("cp-1", "10.0.0.1", "control_plane");
        saveNode("cp-2", "10.0.0.2", "control_plane");
        saveNode("worker-1", "10.0.0.3", "worker");
        saveNode("worker-2", "10.0.0.4", "worker");
        saveNode("worker-3", "10.0.0.5", "worker");
        saveNode("worker-4", "10.0.0.6", "worker");
        saveNode("registry", "10.0.0.20", "registry");
    }

    @AfterEach
    void cleanUp() {
        clusters.deleteAll();
    }

    @Test
    void realJobServiceHonorsStep13And16ConcurrencyLimits() throws Exception {
        Map<String, AtomicInteger> active = new ConcurrentHashMap<>();
        Map<String, AtomicInteger> maximum = new ConcurrentHashMap<>();
        CountDownLatch first13BatchEntered = new CountDownLatch(5);
        CountDownLatch first16BatchEntered = new CountDownLatch(5);
        CountDownLatch release13 = new CountDownLatch(1);
        CountDownLatch release16 = new CountDownLatch(1);
        when(runner.run(anyLong(), any(), any(), any(), any(), any(RuntimeSettings.class)))
                .thenAnswer(countingAnswer(active, maximum, Map.of(
                        "13-install-k8s-deps", new Gate(first13BatchEntered, release13),
                        "16-install-containerd", new Gate(first16BatchEntered, release16))));

        long jobId = installs.start(cluster.getId(),
                List.of("13-install-k8s-deps", "16-install-containerd"));
        assertThat(first13BatchEntered.await(5, TimeUnit.SECONDS)).isTrue();
        release13.countDown();
        assertThat(first16BatchEntered.await(5, TimeUnit.SECONDS)).isTrue();
        release16.countDown();
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(jobs.findById(jobId).orElseThrow().getStatus()).isEqualTo("success");
        assertThat(maximum.get("13-install-k8s-deps")).hasValue(5);
        assertThat(maximum.get("16-install-containerd")).hasValue(5);
    }

    @Test
    void realJobServiceRunsStep20SeriallyAndStopsAfterFailFastStep18Failure() throws Exception {
        Map<String, AtomicInteger> active = new ConcurrentHashMap<>();
        Map<String, AtomicInteger> maximum = new ConcurrentHashMap<>();
        when(runner.run(anyLong(), any(), any(), any(), any(), any(RuntimeSettings.class)))
                .thenAnswer(countingAnswer(active, maximum, Map.of()));

        long successJobId = installs.start(cluster.getId(),
                List.of("18-init-k8s-cluster", "20-add-control-nodes"));
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();
        assertThat(jobs.findById(successJobId).orElseThrow().getStatus()).isEqualTo("success");
        assertThat(maximum.get("18-init-k8s-cluster")).hasValue(1);
        assertThat(maximum.get("20-add-control-nodes")).hasValue(1);

        when(runner.run(anyLong(), any(), any(), any(), any(), any(RuntimeSettings.class)))
                .thenAnswer(invocation -> {
                    InstallStep step = invocation.getArgument(4);
                    if ("18-init-k8s-cluster".equals(step.key())) {
                        return new JobService.NodeOutcome(false, 9, "初始化失败", "logs/cp-1.log");
                    }
                    return JobService.NodeOutcome.successful();
                });
        long failedJobId = installs.start(cluster.getId(),
                List.of("18-init-k8s-cluster", "20-add-control-nodes"));
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        Job failed = jobs.findById(failedJobId).orElseThrow();
        assertThat(failed.getStatus()).isEqualTo("failed");
        assertThat(jobs.findById(failedJobId).orElseThrow().getStatus()).isEqualTo("failed");
    }

    private Answer<JobService.NodeOutcome> countingAnswer(
            Map<String, AtomicInteger> active,
            Map<String, AtomicInteger> maximum,
            Map<String, Gate> gates) {
        return invocation -> {
            InstallStep step = invocation.getArgument(4);
            AtomicInteger current = active.computeIfAbsent(step.key(), ignored -> new AtomicInteger());
            AtomicInteger max = maximum.computeIfAbsent(step.key(), ignored -> new AtomicInteger());
            int now = current.incrementAndGet();
            max.accumulateAndGet(now, Math::max);
            Gate gate = gates.get(step.key());
            try {
                if (gate != null) {
                    gate.entered().countDown();
                    assertThat(gate.release().await(5, TimeUnit.SECONDS)).isTrue();
                } else {
                    Thread.sleep(25);
                }
                return JobService.NodeOutcome.successful();
            } finally {
                current.decrementAndGet();
            }
        };
    }

    private Node saveNode(String hostname, String ip, String role) {
        Node node = new Node(cluster);
        node.update(hostname, ip, "", role, "root", 22);
        node.completeNodeTest("kylin", "V10", "amd64");
        return nodes.saveAndFlush(node);
    }

    private record Gate(CountDownLatch entered, CountDownLatch release) {
    }
}
