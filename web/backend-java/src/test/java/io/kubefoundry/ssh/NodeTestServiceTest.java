package io.kubefoundry.ssh;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.ClusterService;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.credential.AesGcmCredentialCipher;
import io.kubefoundry.job.JobEvent;
import io.kubefoundry.job.JobEventRepository;
import io.kubefoundry.job.JobExecutor;
import java.security.KeyPairGenerator;
import java.security.spec.ECGenParameterSpec;
import java.util.List;
import java.util.concurrent.TimeUnit;
import javax.crypto.spec.SecretKeySpec;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.when;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:node-test-service;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate"
})
@Import(NodeTestServiceTest.TestCredentialConfiguration.class)
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

    @MockBean
    NodeTestRunner runner;

    @MockBean
    ClusterKeyService clusterKeys;

    Cluster cluster;

    @BeforeEach
    void setUp() throws Exception {
        cluster = clusters.save(new Cluster("node-test-" + System.nanoTime()));
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        when(clusterKeys.getOrCreate(cluster.getId())).thenReturn(
                new ClusterKeyMaterial("ecdsa-sha2-nistp256 test", generator.generateKeyPair()));
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
            return new NodeProbe("kylin", "V10", "arm64");
        }).when(runner).test(any(), any(), any(), any());

        long jobId = service.startClusterTest(cluster.getId(), false);
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        Node stored = nodes.findById(node.getId()).orElseThrow();
        assertThat(stored.getNodeTestStatus()).isEqualTo("success");
        assertThat(stored.getOsType()).isEqualTo("kylin");
        assertThat(stored.getOsVersion()).isEqualTo("V10");
        assertThat(stored.getArchitecture()).isEqualTo("arm64");
        assertThat(nodeStatuses(jobId)).containsExactly(
                "password_connecting", "key_installing", "key_verifying", "success");
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
            return new NodeProbe("kylin", "V10", "amd64");
        }).when(runner).test(any(), any(), any(), any());

        service.startClusterTest(cluster.getId(), false);
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();
        Node failed = nodes.findById(bad.getId()).orElseThrow();
        assertThat(failed.getNodeTestStatus()).isEqualTo("failed");
        assertThat(failed.getNodeTestMessage()).doesNotContain("Secret-Password");

        doAnswer(invocation -> {
            NodeTestRunner.PhaseReporter reporter = invocation.getArgument(3);
            reporter.report("password_connecting");
            reporter.report("key_installing");
            reporter.report("key_verifying");
            return new NodeProbe("kylin", "V10", "amd64");
        }).when(runner).test(any(), any(), any(), any());
        long retryJobId = service.startClusterTest(cluster.getId(), true);
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(nodes.findById(good.getId()).orElseThrow().getNodeTestStatus()).isEqualTo("success");
        assertThat(nodes.findById(bad.getId()).orElseThrow().getNodeTestStatus()).isEqualTo("success");
        assertThat(events.findTop100ByJobIdAndIdGreaterThanOrderById(retryJobId, 0).stream()
                .filter(event -> "node.status".equals(event.getType()))
                .map(event -> ((Number) event.getPayload().get("node_id")).longValue()))
                .containsOnly(bad.getId());
    }

    private Node createNode(String hostname, String ip, String password) {
        clusterService.createNode(cluster.getId(), new ClusterService.NodeRequest(
                hostname, ip, "", "worker", "root", 22, password));
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

    @TestConfiguration
    static class TestCredentialConfiguration {
        @Bean
        @Primary
        AesGcmCredentialCipher testCredentialCipher() {
            return new AesGcmCredentialCipher(new SecretKeySpec(new byte[32], "AES"));
        }
    }
}
