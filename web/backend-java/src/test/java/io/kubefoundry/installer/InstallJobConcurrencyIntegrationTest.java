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
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

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
    JobService jobService;

    @Autowired
    JobExecutor executor;

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
        Map<String, Gate> gates = Map.of(
                "13-install-k8s-deps", new Gate(first13BatchEntered, release13),
                "16-install-containerd", new Gate(first16BatchEntered, release16));
        List<Node> configuredNodes = nodes.findByClusterIdOrderById(cluster.getId());
        List<Node> kubernetesNodes = configuredNodes.stream()
                .filter(node -> hasRole(node, "control_plane") || hasRole(node, "worker"))
                .toList();

        long jobId = jobService.submit(new JobService.JobDefinition(cluster.getId(), "install", List.of(
                countedStep("13-install-k8s-deps", 1, 5, false, kubernetesNodes,
                        active, maximum, gates),
                countedStep("16-install-containerd", 2, 5, false, configuredNodes,
                        active, maximum, gates))));
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
        List<Node> controlPlanes = nodes.findByClusterIdOrderById(cluster.getId()).stream()
                .filter(node -> hasRole(node, "control_plane"))
                .toList();
        Node primaryControlPlane = controlPlanes.get(0);
        Node otherControlPlane = controlPlanes.get(1);

        long successJobId = jobService.submit(new JobService.JobDefinition(cluster.getId(), "install", List.of(
                countedStep("18-init-k8s-cluster", 1, 1, true, List.of(primaryControlPlane),
                        active, maximum, Map.of()),
                countedStep("20-add-control-nodes", 2, 1, true, List.of(otherControlPlane),
                        active, maximum, Map.of()))));
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();
        assertThat(jobs.findById(successJobId).orElseThrow().getStatus()).isEqualTo("success");
        assertThat(maximum.get("18-init-k8s-cluster")).hasValue(1);
        assertThat(maximum.get("20-add-control-nodes")).hasValue(1);

        AtomicInteger failedStep20Executions = new AtomicInteger();
        long failedJobId = jobService.submit(new JobService.JobDefinition(cluster.getId(), "install", List.of(
                new JobService.StepDefinition("18-init-k8s-cluster", 1, 1, true, List.of(
                        JobService.NodeOperation.withOutcome(primaryControlPlane.getId(), ignored ->
                                new JobService.NodeOutcome(false, 9, "initialization failed", "logs/cp-1.log")))),
                new JobService.StepDefinition("20-add-control-nodes", 2, 1, true, List.of(
                        new JobService.NodeOperation(otherControlPlane.getId(),
                                failedStep20Executions::incrementAndGet))))));
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        Job failed = jobs.findById(failedJobId).orElseThrow();
        assertThat(failed.getStatus()).isEqualTo("failed");
        assertThat(failedStep20Executions).hasValue(0);
    }

    private JobService.StepDefinition countedStep(
            String stepKey,
            int order,
            int maxWorkers,
            boolean failFast,
            List<Node> targets,
            Map<String, AtomicInteger> active,
            Map<String, AtomicInteger> maximum,
            Map<String, Gate> gates) {
        return new JobService.StepDefinition(stepKey, order, maxWorkers, failFast,
                targets.stream().map(node -> JobService.NodeOperation.withOutcome(node.getId(),
                        countingAction(stepKey, active, maximum, gates))).toList());
    }

    private JobService.OutcomeJobAction countingAction(
            String stepKey,
            Map<String, AtomicInteger> active,
            Map<String, AtomicInteger> maximum,
            Map<String, Gate> gates) {
        return ignored -> {
            AtomicInteger current = active.computeIfAbsent(stepKey, ignoredKey -> new AtomicInteger());
            AtomicInteger max = maximum.computeIfAbsent(stepKey, ignoredKey -> new AtomicInteger());
            int now = current.incrementAndGet();
            max.accumulateAndGet(now, Math::max);
            Gate gate = gates.get(stepKey);
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

    private boolean hasRole(Node node, String role) {
        return node.hasRole(role) || role.equals(node.getRole());
    }

    private record Gate(CountDownLatch entered, CountDownLatch release) {
    }
}
