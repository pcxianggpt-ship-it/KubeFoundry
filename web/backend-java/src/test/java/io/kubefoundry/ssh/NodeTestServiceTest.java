package io.kubefoundry.ssh;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.ClusterService;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.credential.AesGcmCredentialCipher;
import io.kubefoundry.job.JobEvent;
import io.kubefoundry.job.EventService;
import io.kubefoundry.job.JobEventRepository;
import io.kubefoundry.job.JobExecutor;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import java.security.KeyPairGenerator;
import java.security.spec.ECGenParameterSpec;
import java.util.Base64;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.ObjectProvider;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:node-test-service;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate"
})
@Import(NodeTestServiceTest.TestCredentialConfiguration.class)
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
class NodeTestServiceTest {

    @Autowired
    ClusterService clusterService;

    @Autowired
    ClusterRepository clusters;

    @Autowired
    NodeRepository nodes;

    @Autowired
    NodeTestService service;

    @Autowired
    JobExecutor executor;

    @Autowired
    JobEventRepository events;

    @Autowired
    JobRepository jobs;

    @Autowired
    MockMvc mvc;

    @MockBean
    NodeTestRunner runner;

    @MockBean
    ClusterKeyService clusterKeys;

    Cluster cluster;
    ClusterKeyMaterial clusterKey;

    @BeforeEach
    void setUp() throws Exception {
        cluster = clusters.save(new Cluster("node-test-" + System.nanoTime()));
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        clusterKey = new ClusterKeyMaterial(
                "ecdsa-sha2-nistp256 test", generator.generateKeyPair());
        when(clusterKeys.getOrCreate(cluster.getId())).thenReturn(clusterKey);
    }

    @AfterEach
    void cleanUp() {
        clusters.deleteAll();
    }

    @Test
    void runsPhasesInOrderAndPersistsDiscovery() throws Exception {
        Node node = createNode("node-a", "10.0.0.1", "Password-1");
        doAnswer(invocation -> {
            NodeTestRunner.PhaseReporter reporter = invocation.getArgument(3);
            reporter.report("password_connecting");
            reporter.report("key_installing");
            reporter.report("key_verifying");
            return new NodeProbe("remote-node-a", "kylin", "V10", "arm64");
        }).when(runner).test(any(), any(), any(), any(), anyLong());

        long jobId = service.startClusterTest(cluster.getId(), false);
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        Node stored = nodes.findById(node.getId()).orElseThrow();
        assertThat(stored.getNodeTestStatus()).isEqualTo("success");
        assertThat(stored.getHostname()).isEqualTo("node-a");
        assertThat(stored.getOsType()).isEqualTo("kylin");
        assertThat(stored.getOsVersion()).isEqualTo("V10");
        assertThat(stored.getArchitecture()).isEqualTo("arm64");
        assertThat(nodeStatuses(jobId)).containsExactly(
                "running", "password_connecting", "key_installing", "key_verifying", "success");
    }

    @Test
    void retriesOnlyFailedNodesAndRedactsPassword() throws Exception {
        Node good = createNode("node-good", "10.0.0.2", "Good-Password");
        Node bad = createNode("node-bad", "10.0.0.3", "Secret-Password");
        doAnswer(invocation -> {
            Node node = invocation.getArgument(0);
            NodeTestRunner.PhaseReporter reporter = invocation.getArgument(3);
            reporter.report("password_connecting");
            if (node.getId().equals(bad.getId())) {
                throw new IllegalStateException("认证失败 Secret-Password");
            }
            reporter.report("key_installing");
            reporter.report("key_verifying");
            return new NodeProbe(node.getHostname(), "kylin", "V10", "amd64");
        }).when(runner).test(any(), any(), any(), any(), anyLong());

        service.startClusterTest(cluster.getId(), false);
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();
        Node failed = nodes.findById(bad.getId()).orElseThrow();
        assertThat(failed.getNodeTestStatus()).isEqualTo("failed");
        assertThat(failed.getNodeTestMessage())
                .contains("node-bad", "密码连接", "password_connecting", "认证失败", "***")
                .doesNotContain("Secret-Password");

        doAnswer(invocation -> {
            NodeTestRunner.PhaseReporter reporter = invocation.getArgument(3);
            reporter.report("password_connecting");
            reporter.report("key_installing");
            reporter.report("key_verifying");
            return new NodeProbe("node-bad", "kylin", "V10", "amd64");
        }).when(runner).test(any(), any(), any(), any(), anyLong());
        long retryJobId = service.startClusterTest(cluster.getId(), true);
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(nodes.findById(good.getId()).orElseThrow().getNodeTestStatus()).isEqualTo("success");
        assertThat(nodes.findById(bad.getId()).orElseThrow().getNodeTestStatus()).isEqualTo("success");
        assertThat(events.findTop100ByJobIdAndIdGreaterThanOrderById(retryJobId, 0).stream()
                .filter(event -> "node.status".equals(event.getType()))
                .map(event -> ((Number) event.getPayload().get("node_id")).longValue()))
                .containsOnly(bad.getId());
    }

    @Test
    void concurrentStartsCreateOneJobAndReturnCurrentJobId() throws Exception {
        Node node = createNode("node-concurrent", "10.0.0.4", "Concurrent-Password");
        CountDownLatch callersReady = new CountDownLatch(2);
        CountDownLatch callersMayStart = new CountDownLatch(1);
        CountDownLatch runnerStarted = new CountDownLatch(1);
        CountDownLatch runnerMayFinish = new CountDownLatch(1);
        doAnswer(invocation -> {
            runnerStarted.countDown();
            assertThat(runnerMayFinish.await(5, TimeUnit.SECONDS)).isTrue();
            return new NodeProbe("node-concurrent", "kylin", "V10", "amd64");
        }).when(runner).test(any(), any(), any(), any(), anyLong());

        ExecutorService callers = Executors.newFixedThreadPool(2);
        try {
            CompletableFuture<Long> first = CompletableFuture.supplyAsync(
                    () -> startAfterGate(callersReady, callersMayStart,
                            () -> service.startClusterTest(cluster.getId(), false)), callers);
            CompletableFuture<Long> second = CompletableFuture.supplyAsync(
                    () -> startAfterGate(callersReady, callersMayStart,
                            () -> service.startNodeTest(node.getId())), callers);
            assertThat(callersReady.await(5, TimeUnit.SECONDS)).isTrue();
            callersMayStart.countDown();

            List<CompletableFuture<Long>> calls = List.of(first, second);
            List<Long> created = calls.stream().filter(call -> {
                try {
                    call.get(5, TimeUnit.SECONDS);
                    return true;
                } catch (Exception ignored) {
                    return false;
                }
            }).map(call -> {
                try {
                    return call.get();
                } catch (Exception exception) {
                    throw new AssertionError(exception);
                }
            }).toList();
            assertThat(created).hasSize(1);
            long currentJobId = created.get(0);
            CompletableFuture<Long> rejected = first.isCompletedExceptionally() ? first : second;
            assertThatThrownBy(rejected::join)
                    .isInstanceOf(CompletionException.class)
                    .cause().isInstanceOf(NodeTestService.ActiveNodeTestException.class)
                    .extracting(throwable -> ((NodeTestService.ActiveNodeTestException) throwable).jobId())
                    .isEqualTo(currentJobId);
            assertThat(jobs.findByClusterIdOrderByIdDesc(cluster.getId())).hasSize(1);
            assertThat(runnerStarted.await(5, TimeUnit.SECONDS)).isTrue();
        } finally {
            runnerMayFinish.countDown();
            assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();
            callers.shutdownNow();
        }
    }

    @Test
    void concurrentStartsForDifferentClustersDoNotBlockEachOther() throws Exception {
        ClusterRepository testClusters = mock(ClusterRepository.class);
        NodeRepository testNodes = mock(NodeRepository.class);
        JobRepository testJobs = mock(JobRepository.class);
        JobService testJobService = mock(JobService.class);
        ClusterKeyService testKeys = mock(ClusterKeyService.class);
        EventService testEvents = mock(EventService.class);
        NodeTestRunner testRunner = mock(NodeTestRunner.class);
        @SuppressWarnings("unchecked")
        ObjectProvider<AesGcmCredentialCipher> testCipherProvider = mock(ObjectProvider.class);
        Cluster firstCluster = mock(Cluster.class);
        Cluster secondCluster = mock(Cluster.class);
        Node firstNode = mock(Node.class);
        Node secondNode = mock(Node.class);
        CountDownLatch firstSubmitEntered = new CountDownLatch(1);
        CountDownLatch releaseFirstSubmit = new CountDownLatch(1);

        when(firstCluster.getId()).thenReturn(1L);
        when(secondCluster.getId()).thenReturn(2L);
        when(firstNode.getId()).thenReturn(11L);
        when(secondNode.getId()).thenReturn(22L);
        when(firstNode.getCluster()).thenReturn(firstCluster);
        when(secondNode.getCluster()).thenReturn(secondCluster);
        when(firstNode.getIp()).thenReturn("10.0.0.11");
        when(secondNode.getIp()).thenReturn("10.0.0.22");
        when(firstNode.getHostname()).thenReturn("first-node");
        when(secondNode.getHostname()).thenReturn("second-node");
        when(firstNode.hasPassword()).thenReturn(true);
        when(secondNode.hasPassword()).thenReturn(true);
        when(testClusters.findById(1L)).thenReturn(Optional.of(firstCluster));
        when(testClusters.findById(2L)).thenReturn(Optional.of(secondCluster));
        when(testNodes.findByClusterIdOrderById(1L)).thenReturn(List.of(firstNode));
        when(testNodes.findByClusterIdOrderById(2L)).thenReturn(List.of(secondNode));
        when(testJobs.findFirstByClusterIdAndTypeAndStatusInOrderByIdDesc(
                anyLong(), any(), any())).thenReturn(Optional.empty());
        when(testKeys.getOrCreate(anyLong())).thenReturn(testKey());
        when(testClusters.updateNodeTestStatusIfConfigurationUnchanged(
                anyLong(), anyLong(), any())).thenReturn(1);
        when(testJobService.submit(any())).thenAnswer(invocation -> {
            JobService.JobDefinition definition = invocation.getArgument(0);
            if (definition.clusterId() == 1L) {
                firstSubmitEntered.countDown();
                assertThat(releaseFirstSubmit.await(5, TimeUnit.SECONDS)).isTrue();
                return 101L;
            }
            return 202L;
        });
        NodeTestService testService = new NodeTestService(
                testClusters, testNodes, testJobs, testJobService, testEvents,
                testKeys, testRunner, testCipherProvider);
        ExecutorService callers = Executors.newFixedThreadPool(2);
        try {
            CompletableFuture<Long> first = CompletableFuture.supplyAsync(
                    () -> testService.startClusterTest(1L, false), callers);
            assertThat(firstSubmitEntered.await(5, TimeUnit.SECONDS)).isTrue();

            CompletableFuture<Long> second = CompletableFuture.supplyAsync(
                    () -> testService.startClusterTest(2L, false), callers);
            assertThat(second.get(1, TimeUnit.SECONDS)).isEqualTo(202L);
            releaseFirstSubmit.countDown();
            assertThat(first.get(5, TimeUnit.SECONDS)).isEqualTo(101L);
        } finally {
            releaseFirstSubmit.countDown();
            callers.shutdownNow();
        }
    }

    @Test
    void concurrentAggregateUpdatesRemainConsistentWithAllNodes() throws Exception {
        Node successful = createNode("node-success", "10.0.0.5", "Success-Password");
        Node failed = createNode("node-failed", "10.0.0.6", "Failed-Password");
        successful.completeNodeTest("kylin", "V10", "amd64");
        failed.failNodeTest("expected failure");
        nodes.saveAllAndFlush(List.of(successful, failed));
        cluster.markNodeTestStatus("running");
        clusters.saveAndFlush(cluster);

        ExecutorService callers = Executors.newFixedThreadPool(2);
        try {
            CompletableFuture<Integer> first = CompletableFuture.supplyAsync(
                    () -> clusters.refreshNodeTestAggregate(
                            cluster.getId(), cluster.getNodeConfigVersion()), callers);
            CompletableFuture<Integer> second = CompletableFuture.supplyAsync(
                    () -> clusters.refreshNodeTestAggregate(
                            cluster.getId(), cluster.getNodeConfigVersion()), callers);
            assertThat(first.get(5, TimeUnit.SECONDS)).isEqualTo(1);
            assertThat(second.get(5, TimeUnit.SECONDS)).isEqualTo(1);
        } finally {
            callers.shutdownNow();
        }

        assertThat(clusters.findById(cluster.getId()).orElseThrow().getNodeTestStatus())
                .isEqualTo("failed");
    }

    @Test
    void configurationChangeDuringTestPreventsOldResultFromBeingStored() throws Exception {
        Node node = createNode("node-stale", "10.0.0.7", "Stale-Password");
        CountDownLatch runnerStarted = new CountDownLatch(1);
        CountDownLatch runnerMayFinish = new CountDownLatch(1);
        doAnswer(invocation -> {
            NodeTestRunner.PhaseReporter reporter = invocation.getArgument(3);
            reporter.report("password_connecting");
            runnerStarted.countDown();
            assertThat(runnerMayFinish.await(5, TimeUnit.SECONDS)).isTrue();
            return new NodeProbe("old-hostname", "old-os", "old-version", "old-arch");
        }).when(runner).test(any(), any(), any(), any(), anyLong());

        service.startNodeTest(node.getId());
        assertThat(runnerStarted.await(5, TimeUnit.SECONDS)).isTrue();
        clusterService.updateNode(node.getId(), new ClusterService.NodeRequest(
                null, "10.0.0.70", null, null, "admin", 2222, null));
        runnerMayFinish.countDown();
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        Node stored = nodes.findById(node.getId()).orElseThrow();
        assertThat(stored.getNodeTestStatus()).isEqualTo("stale");
        assertThat(stored.getHostFingerprint()).isNull();
        assertThat(stored.getOsType()).isNull();
        assertThat(stored.getOsVersion()).isNull();
        assertThat(stored.getArchitecture()).isNull();
    }

    @Test
    void singleNodeTestMarksClusterRunningThenSuccess() throws Exception {
        Node node = createNode("node-single", "10.0.0.8", "Single-Password");
        doAnswer(invocation -> {
            Thread.sleep(500);
            return new NodeProbe("remote-single", "kylin", "V10", "amd64");
        }).when(runner).test(any(), any(), any(), any(), anyLong());

        service.startNodeTest(node.getId());

        assertThat(clusters.findById(cluster.getId()).orElseThrow().getNodeTestStatus())
                .isEqualTo("running");
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();
        assertThat(clusters.findById(cluster.getId()).orElseThrow().getNodeTestStatus())
                .isEqualTo("success");
    }

    @Test
    void singleNodeFailureMarksClusterFailed() throws Exception {
        Node node = createNode("node-single-failed", "10.0.0.81", "Single-Failed-Password");
        doAnswer(invocation -> {
            NodeTestRunner.PhaseReporter reporter = invocation.getArgument(3);
            reporter.report("key_installing");
            throw new IllegalStateException("authorized_keys 写入失败");
        }).when(runner).test(any(), any(), any(), any(), anyLong());

        service.startNodeTest(node.getId());
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(clusters.findById(cluster.getId()).orElseThrow().getNodeTestStatus())
                .isEqualTo("failed");
    }

    @Test
    void authenticationMaterialNeverAppearsInNodeApiOrSse() throws Exception {
        Node node = createNode("node-secret", "10.0.0.9", "Api-Sse-Secret");
        String ciphertext = node.encryptedPassword().ciphertext();
        String privateKey = Base64.getEncoder().encodeToString(clusterKey.keyPair().getPrivate().getEncoded());
        doAnswer(invocation -> {
            NodeTestRunner.PhaseReporter reporter = invocation.getArgument(3);
            reporter.report("password_connecting");
            throw new IllegalStateException("认证失败 Api-Sse-Secret");
        }).when(runner).test(any(), any(), any(), any(), anyLong());

        long jobId = service.startNodeTest(node.getId());
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();
        String apiBody = mvc.perform(get("/api/clusters/{id}/nodes", cluster.getId()))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        MvcResult started = mvc.perform(get("/api/jobs/{jobId}/events", jobId))
                .andExpect(request().asyncStarted()).andReturn();
        String sseBody = mvc.perform(asyncDispatch(started))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();

        assertThat(apiBody).doesNotContain("Api-Sse-Secret", ciphertext, privateKey);
        assertThat(sseBody).doesNotContain("Api-Sse-Secret", ciphertext, privateKey);
    }

    @Test
    void authenticationMaterialNeverAppearsInRuntimeLogs(CapturedOutput output) throws Exception {
        Node node = createNode("node-log-secret", "10.0.0.91", "Runtime-Log-Password");
        String ciphertext = node.encryptedPassword().ciphertext();
        String privateKey = Base64.getEncoder().encodeToString(
                clusterKey.keyPair().getPrivate().getEncoded());
        doAnswer(invocation -> {
            NodeTestRunner.PhaseReporter reporter = invocation.getArgument(3);
            reporter.report("key_verifying");
            throw new IllegalStateException(
                    "认证材料 Runtime-Log-Password " + ciphertext + " " + privateKey);
        }).when(runner).test(any(), any(), any(), any(), anyLong());

        long jobId = service.startNodeTest(node.getId());
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(jobs.findById(jobId).orElseThrow().getStatus()).isEqualTo("failed");
        assertThat(nodes.findById(node.getId()).orElseThrow().getNodeTestMessage())
                .doesNotContain("Runtime-Log-Password", ciphertext, privateKey);
        assertThat(output.getAll())
                .doesNotContain("Runtime-Log-Password", ciphertext, privateKey);
    }

    @Test
    void configurationChangeAfterVersionReadPreventsRunningAndJobSubmission() throws Exception {
        ClusterRepository testClusters = mock(ClusterRepository.class);
        NodeRepository testNodes = mock(NodeRepository.class);
        JobRepository testJobs = mock(JobRepository.class);
        JobService testJobService = mock(JobService.class);
        EventService testEvents = mock(EventService.class);
        ClusterKeyService testKeys = mock(ClusterKeyService.class);
        NodeTestRunner testRunner = mock(NodeTestRunner.class);
        @SuppressWarnings("unchecked")
        ObjectProvider<AesGcmCredentialCipher> testCipherProvider = mock(ObjectProvider.class);
        Cluster testCluster = mock(Cluster.class);
        Node testNode = mock(Node.class);
        when(testCluster.getId()).thenReturn(1L);
        when(testCluster.getNodeConfigVersion()).thenReturn(7L);
        when(testNode.getId()).thenReturn(11L);
        when(testNode.getCluster()).thenReturn(testCluster);
        when(testNode.getHostname()).thenReturn("stale-start-node");
        when(testNode.getIp()).thenReturn("10.0.0.11");
        when(testNode.hasPassword()).thenReturn(true);
        when(testKeys.getOrCreate(1L)).thenReturn(testKey());
        when(testClusters.findById(1L)).thenReturn(Optional.of(testCluster));
        when(testNodes.findByClusterIdOrderById(1L)).thenReturn(List.of(testNode));
        when(testJobs.findFirstByClusterIdAndTypeAndStatusInOrderByIdDesc(
                anyLong(), any(), any())).thenReturn(Optional.empty());
        when(testClusters.updateNodeTestStatusIfConfigurationUnchanged(
                1L, 7L, "running")).thenReturn(0);
        NodeTestService testService = new NodeTestService(
                testClusters, testNodes, testJobs, testJobService, testEvents,
                testKeys, testRunner, testCipherProvider);

        assertThatThrownBy(() -> testService.startClusterTest(1L, false))
                .isInstanceOf(NodeConfigurationChangedException.class);
        verify(testJobService, never()).submit(any());
    }

    @Test
    void aggregateDoesNotOverwriteStaleAfterNodeResultWasStored() {
        Node node = createNode("aggregate-stale", "10.0.0.92", "Aggregate-Password");
        long expectedVersion = clusters.findById(cluster.getId()).orElseThrow()
                .getNodeConfigVersion();
        assertThat(nodes.completeTestIfConfigurationUnchanged(
                node.getId(), expectedVersion, "kylin", "V10", "amd64")).isEqualTo(1);

        clusters.markNodeConfigurationChanged(cluster.getId());
        assertThat(clusters.refreshNodeTestAggregate(cluster.getId(), expectedVersion)).isZero();

        assertThat(clusters.findById(cluster.getId()).orElseThrow().getNodeTestStatus())
                .isEqualTo("stale");
    }

    @Test
    void runningStatusWriteRejectsAStaleConfigurationVersion() {
        long expectedVersion = clusters.findById(cluster.getId()).orElseThrow()
                .getNodeConfigVersion();

        clusters.markNodeConfigurationChanged(cluster.getId());

        assertThat(clusters.updateNodeTestStatusIfConfigurationUnchanged(
                cluster.getId(), expectedVersion, "running")).isZero();
        assertThat(clusters.findById(cluster.getId()).orElseThrow().getNodeTestStatus())
                .isEqualTo("stale");
    }

    private Node createNode(String hostname, String ip, String password) {
        clusterService.createNode(cluster.getId(), new ClusterService.NodeRequest(
                hostname, ip, "", java.util.List.of("worker"), "root", 22, password));
        return nodes.findByClusterIdOrderById(cluster.getId()).stream()
                .filter(node -> hostname.equals(node.getHostname())).findFirst().orElseThrow();
    }

    private List<String> nodeStatuses(long jobId) {
        return events.findTop100ByJobIdAndIdGreaterThanOrderById(jobId, 0).stream()
                .filter(event -> "node.status".equals(event.getType()))
                .map(JobEvent::getPayload)
                .map(payload -> (String) payload.get("status"))
                .toList();
    }

    private static long startAfterGate(
            CountDownLatch callersReady,
            CountDownLatch callersMayStart,
            java.util.function.LongSupplier start) {
        callersReady.countDown();
        try {
            if (!callersMayStart.await(5, TimeUnit.SECONDS)) {
                throw new IllegalStateException("concurrent start gate timed out");
            }
            return start.getAsLong();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("concurrent start gate interrupted", exception);
        }
    }

    private static ClusterKeyMaterial testKey() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        return new ClusterKeyMaterial("ecdsa-sha2-nistp256 test", generator.generateKeyPair());
    }

    @TestConfiguration
    static class TestCredentialConfiguration {
        @Bean
        @Primary
        AesGcmCredentialCipher testCredentialCipher() {
            return new AesGcmCredentialCipher(new SecretKeySpec(new byte[32], "AES"));
        }
    }
}
