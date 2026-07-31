package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.JobEvent;
import io.kubefoundry.job.JobEventRepository;
import io.kubefoundry.job.JobExecutor;
import io.kubefoundry.job.JobRepository;
import java.nio.file.Path;
import org.springframework.beans.factory.annotation.Autowired;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:precheck-service;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate"
})
class PrecheckServiceTest {

    @Autowired
    ClusterRepository clusters;

    @Autowired
    NodeRepository nodes;

    @Autowired
    JobRepository jobs;

    @Autowired
    JobExecutor executor;

    @Autowired
    PrecheckService service;

    @Autowired
    PrecheckResultRepository results;

    @Autowired
    JobEventRepository events;

    @Autowired
    InstallService installs;

    @Autowired
    ClusterSettingsService settings;

    @MockBean
    RemoteStepRunner runner;

    Cluster cluster;
    Node node;

    @TempDir
    Path mediaDirectory;

    @BeforeEach
    void setUp() {
        settings.updateGlobalSettings(Map.of("paths", Map.of(
                "install_media", mediaDirectory.toString())));
        cluster = clusters.save(new Cluster("precheck-" + System.nanoTime()));
        cluster.markNodeTestStatus("success");
        cluster = clusters.saveAndFlush(cluster);
        node = new Node(cluster);
        node.update("cp-a", "10.0.0.1", "", "control_plane", "root", 22);
        node.completeNodeTest("kylin", "V10", "amd64");
        node = nodes.saveAndFlush(node);
        Node worker = new Node(cluster);
        worker.update("worker-a", "10.0.0.2", "", "worker", "root", 22);
        worker.completeNodeTest("kylin", "V10", "amd64");
        nodes.saveAndFlush(worker);
        Node registry = new Node(cluster);
        registry.update("registry", "10.0.0.9", "", "registry", "root", 22);
        registry.completeNodeTest("kylin", "V10", "amd64");
        nodes.saveAndFlush(registry);
    }

    @AfterEach
    void cleanUp() {
        clusters.deleteAll();
    }

    @Test
    void nonRootAndSwapAreWarningsButDoNotFailPrecheckJob() throws Exception {
        when(runner.runCommandCapture(anyLong(), any(Cluster.class), any(Node.class),
                eq("web-precheck-node-env"), any(), any()))
                .thenReturn(new RemoteStepRunner.CommandOutcome(
                        0, healthyOutput("""
                                __KF__USER=1000
                                __KF__SWAP=512
                                """), "", "logs/cp-a.log"));

        long jobId = service.start(cluster.getId());
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(jobs.findById(jobId).orElseThrow().getStatus()).isEqualTo("success");
        assertThat(results.findByJobIdOrderByNodeIdAscIdAsc(jobId))
                .filteredOn(result -> "cp-a".equals(result.getNode().getHostname())
                        && List.of("user", "swap").contains(result.getCheckKey()))
                .extracting(PrecheckResult::getStatus)
                .containsExactly("warning", "warning");
        assertThat(events.findTop100ByJobIdAndIdGreaterThanOrderById(jobId, 0))
                .filteredOn(event -> "precheck.result".equals(event.getType()))
                .extracting(JobEvent::getPayload)
                .anySatisfy(payload -> assertThat(payload).containsEntry("check_key", "user"));
    }

    @Test
    void errorSeverityFailuresFailNodeAndJobAndPersistStructuredResults() throws Exception {
        when(runner.runCommandCapture(anyLong(), any(Cluster.class), any(Node.class),
                eq("web-precheck-node-env"), any(), any()))
                .thenReturn(new RemoteStepRunner.CommandOutcome(
                        0, healthyOutput("""
                                __KF__USER=0
                                __KF__CPU=1
                                __KF__MEM=1024
                                __KF__BASH=missing
                                __KF__PORT_6443=used
                                __KF__ARCH=aarch64
                                """), "", "logs/cp-a.log"));

        long jobId = service.start(cluster.getId());
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(jobs.findById(jobId).orElseThrow().getStatus()).isEqualTo("failed");
        assertThat(results.findByJobIdOrderByNodeIdAscIdAsc(jobId))
                .filteredOn(result -> "fail".equals(result.getStatus()))
                .extracting(PrecheckResult::getCheckKey)
                .contains("cpu", "memory", "bash", "ports", "system_drift");
        assertThat(nodes.findById(node.getId()).orElseThrow().getNodeTestStatus()).isEqualTo("stale");
        assertThat(clusters.findById(cluster.getId()).orElseThrow().getNodeTestStatus()).isEqualTo("stale");
        org.assertj.core.api.Assertions.assertThatThrownBy(() -> installs.start(cluster.getId(), List.of()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("stale");
    }

    @Test
    void twoControlPlanesFailTheControlPlaneCountCheck() throws Exception {
        Node secondControl = new Node(cluster);
        secondControl.update("cp-b", "10.0.0.3", "", "control_plane", "root", 22);
        secondControl.completeNodeTest("kylin", "V10", "amd64");
        nodes.saveAndFlush(secondControl);
        stubHealthyPrecheck();

        long jobId = service.start(cluster.getId());
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(jobs.findById(jobId).orElseThrow().getStatus()).isEqualTo("failed");
        assertThat(results.findByJobIdOrderByNodeIdAscIdAsc(jobId))
                .filteredOn(result -> "control_plane_count".equals(result.getCheckKey()))
                .extracting(PrecheckResult::getStatus)
                .containsOnly("fail");
    }

    @Test
    void missingOfflineMediaDirectoryFailsPrecheck() throws Exception {
        Path missingDirectory = mediaDirectory.resolve("missing-media");
        settings.updateGlobalSettings(Map.of("paths", Map.of(
                "install_media", missingDirectory.toString())));
        stubHealthyPrecheck();

        long jobId = service.start(cluster.getId());
        assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();

        assertThat(jobs.findById(jobId).orElseThrow().getStatus()).isEqualTo("failed");
        assertThat(results.findByJobIdOrderByNodeIdAscIdAsc(jobId))
                .filteredOn(result -> "offline_media".equals(result.getCheckKey()))
                .extracting(PrecheckResult::getStatus)
                .containsOnly("fail");
    }

    private void stubHealthyPrecheck() {
        when(runner.runCommandCapture(anyLong(), any(Cluster.class), any(Node.class),
                eq("web-precheck-node-env"), any(), any()))
                .thenReturn(new RemoteStepRunner.CommandOutcome(
                        0, healthyOutput(""), "", "logs/precheck.log"));
    }

    private static String healthyOutput(String overrides) {
        return """
                __KF__USER=0
                __KF__OS=Kylin Linux Advanced Server V10
                __KF__OS_RELEASE__ID="kylin"
                __KF__OS_RELEASE__VERSION_ID="V10"
                __KF__OS_RELEASE__PRETTY_NAME="Kylin Linux Advanced Server V10"
                __KF__CPU=4
                __KF__MEM=8192
                __KF__DISK=20480
                __KF__SWAP=0
                __KF__HOSTNAME=cp-a
                __KF__ARCH=x86_64
                __KF__BASH=present
                __KF__SYSTEMD=present
                __KF__PORT_6443=free
                __KF__PORT_2379=free
                __KF__PORT_2380=free
                __KF__PORT_10250=free
                __KF__PORT_10257=free
                __KF__PORT_10259=free
                """ + overrides;
    }
}
