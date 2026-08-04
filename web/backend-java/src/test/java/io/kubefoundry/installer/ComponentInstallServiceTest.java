package io.kubefoundry.installer;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponent;
import io.kubefoundry.cluster.ClusterComponentRepository;
import io.kubefoundry.cluster.ClusterComponentState;
import io.kubefoundry.cluster.ClusterComponentStateRepository;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.JobExecutor;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import io.kubefoundry.job.JobStepRepository;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:component-install-service;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate",
        "kubefoundry.project-dir=target/component-install-media"
})
class ComponentInstallServiceTest {

    @Autowired ClusterRepository clusters;
    @Autowired ClusterComponentRepository components;
    @Autowired ClusterComponentStateRepository states;
    @Autowired NodeRepository nodes;
    @Autowired JobRepository jobs;
    @Autowired JobStepRepository jobSteps;
    @Autowired InstallationSnapshotRepository snapshots;
    @Autowired ComponentInstallService service;
    @Autowired ObjectMapper mapper;

    @MockBean JobExecutor executor;

    @BeforeEach
    void prepareComponentMedia() throws Exception {
        Path root = Path.of("target/component-install-media");
        Path helm = root.resolve("tools/helm-amd");
        Path traefik = root.resolve("kube-media/03.setup_file/v1.30.14/traefik/3.3");
        Files.createDirectories(helm.getParent());
        Files.createDirectories(traefik);
        Files.writeString(helm, "helm", StandardCharsets.UTF_8);
        Files.writeString(traefik.resolve("traefik.yaml"), "apiVersion: v1\n", StandardCharsets.UTF_8);
    }

    @AfterEach
    void cleanUp() {
        clusters.deleteAll();
    }

    @Test
    void acceptsOnlyTheCurrentConfigurationAndCapturesTheComponentPlan() throws Exception {
        Cluster cluster = preparedCluster("accepted");
        long jobId = service.submit(cluster.getId(), cluster.getComponentConfigVersion(), List.of(
                new JobService.StepDefinition("安装 Traefik", 1, 1, true,
                        List.of(new JobService.NodeOperation(nodeId(cluster), () -> { })), "traefik")),
                Map.of("tools/helm-amd", "b".repeat(64)));

        assertThat(jobs.findById(jobId).orElseThrow().getType())
                .isEqualTo(ComponentInstallationStateService.JOB_TYPE);
        assertThat(states.findByClusterIdAndComponentKey(cluster.getId(), "traefik").orElseThrow())
                .satisfies(state -> {
                    assertThat(state.getStatus()).isEqualTo(ClusterComponentState.INSTALLING);
                    assertThat(state.getLastJobId()).isEqualTo(jobId);
                });
        InstallationSnapshot snapshot = snapshots.findByJobId(jobId).orElseThrow();
        InstallationSnapshotPayload payload = mapper.readValue(
                snapshot.getSnapshotJson(), InstallationSnapshotPayload.class);
        assertThat(payload.componentConfigurationVersion()).isEqualTo(cluster.getComponentConfigVersion());
        assertThat(payload.componentGroups()).extracting(InstallationSnapshotPayload.ComponentGroup::key)
                .containsExactly("traefik");
        assertThat(payload.mediaChecksums()).containsEntry("tools/helm-amd", "b".repeat(64));
        assertThat(snapshot.getSnapshotJson()).doesNotContain("password", "token", "secret");
        verify(executor).submit(any());

        assertThatThrownBy(() -> service.submit(cluster.getId(), cluster.getComponentConfigVersion(), List.of(
                new JobService.StepDefinition("安装 Traefik", 1, 1, true,
                        List.of(new JobService.NodeOperation(nodeId(cluster), () -> { })), "traefik")), Map.of()))
                .isInstanceOf(ActiveInstallerJobException.class)
                .hasMessageContaining("component_install");
    }

    @Test
    void refusesAStaleConfigurationVersionBeforeSubmittingAJob() {
        Cluster cluster = preparedCluster("stale");

        assertThatThrownBy(() -> service.submit(cluster.getId(), cluster.getComponentConfigVersion() - 1,
                List.of(new JobService.StepDefinition("安装 Traefik", 1, 1, true,
                        List.of(new JobService.NodeOperation(nodeId(cluster), () -> { })), "traefik")), Map.of()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("组件配置已变化");
        assertThat(jobs.count()).isZero();
    }

    @Test
    void buildsAComponentOnlyPlanForAnInstalledCluster() {
        Cluster cluster = preparedCluster("supplement");
        cluster.markInstallationStarted();
        cluster.markInstallationFinished(true);
        clusters.saveAndFlush(cluster);

        long jobId = service.start(cluster.getId());

        assertThat(jobs.findById(jobId).orElseThrow().getType())
                .isEqualTo(ComponentInstallationStateService.JOB_TYPE);
        assertThat(jobSteps.findByJobIdOrderByOrder(jobId)).extracting(step -> step.getName())
                .containsExactly("安装 Helm", "创建 Kubemate 命名空间", "安装 Traefik 网关");
        assertThat(cluster.isInstallationLocked()).isTrue();
    }

    private Cluster preparedCluster(String suffix) {
        Cluster cluster = clusters.saveAndFlush(new Cluster("component-install-" + suffix + System.nanoTime()));
        cluster.update(null, null, "1.30.14", "10.244.0.0/16", "10.96.0.0/12",
                "registry", "10.0.0.20", 5000, null);
        cluster.updateInstallationConfiguration("/data/kubernetes", "REGISTRY");
        cluster.updateKubemateEnabled(true);
        cluster.markComponentConfigurationChanged();
        clusters.saveAndFlush(cluster);
        Node node = new Node(cluster);
        node.update("cp-" + suffix, "10.0.0.10", "", "control_plane", "root", 22);
        nodes.saveAndFlush(node);
        components.saveAndFlush(new ClusterComponent(cluster, "traefik", true, "{}"));
        states.saveAndFlush(new ClusterComponentState(cluster, "traefik"));
        return cluster;
    }

    private long nodeId(Cluster cluster) {
        return nodes.findByClusterIdOrderById(cluster.getId()).get(0).getId();
    }
}
