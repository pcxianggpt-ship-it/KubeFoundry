package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponent;
import io.kubefoundry.cluster.ClusterComponentRepository;
import io.kubefoundry.cluster.ClusterComponentState;
import io.kubefoundry.cluster.ClusterComponentStateRepository;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobExecutor;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:install-resume;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate",
        "kubefoundry.project-dir=target/install-resume-media",
        "kubefoundry.app-dir=target/install-resume-media"
})
class InstallResumeServiceTest {
    @Autowired JdbcTemplate jdbc;
    @Autowired ClusterRepository clusters;
    @Autowired NodeRepository nodes;
    @Autowired ClusterComponentRepository components;
    @Autowired ClusterComponentStateRepository states;
    @Autowired JobRepository jobs;
    @Autowired JobService jobService;
    @Autowired InstallationSnapshotRepository snapshots;
    @Autowired InstallService installs;
    @Autowired ComponentInstallService componentInstalls;
    @Autowired ComponentInstallationStateService componentStates;
    @Autowired InstallResumeService resumes;

    @MockBean JobExecutor executor;

    @BeforeEach
    void setUp() throws Exception {
        jdbc.update("delete from events");
        jdbc.update("delete from job_step_nodes");
        jdbc.update("delete from job_steps");
        jdbc.update("delete from installation_snapshots");
        jdbc.update("delete from jobs");
        jdbc.update("delete from cluster_component_states");
        jdbc.update("delete from cluster_components");
        jdbc.update("delete from cluster_settings");
        jdbc.update("delete from node_roles");
        jdbc.update("delete from nodes");
        jdbc.update("delete from clusters");

        Path root = Path.of("target/install-resume-media");
        Files.createDirectories(root.resolve("tools"));
        Files.createDirectories(root.resolve("kube-media/03.setup_file/v1.30.14/traefik/3.3"));
        Files.writeString(root.resolve("tools/helm-amd"), "helm", StandardCharsets.UTF_8);
        Files.writeString(root.resolve(
                "kube-media/03.setup_file/v1.30.14/traefik/3.3/traefik.yaml"),
                "apiVersion: v1\n", StandardCharsets.UTF_8);
    }

    @Test
    void resumesFailedBaseInstallAsANewSnapshotDrivenJob() {
        Cluster cluster = preparedCluster("base", false);
        long sourceJobId = installs.start(cluster.getId());
        Job source = jobs.findById(sourceJobId).orElseThrow();
        source.markFailed();
        jobs.saveAndFlush(source);
        String sourceSnapshot = snapshots.findByJobId(sourceJobId).orElseThrow().getSnapshotJson();
        var sourceStepIds = jobService.listSteps(sourceJobId).stream().map(step -> step.getId()).toList();

        long resumedJobId = resumes.resume(cluster.getId(), sourceJobId);

        Job resumed = jobs.findById(resumedJobId).orElseThrow();
        assertThat(resumed.getId()).isNotEqualTo(sourceJobId);
        assertThat(resumed.getSourceJob().getId()).isEqualTo(sourceJobId);
        assertThat(resumed.getRunMode()).isEqualTo("resume");
        assertThat(resumed.getType()).isEqualTo("install");
        assertThat(jobs.findById(sourceJobId).orElseThrow().getStatus()).isEqualTo("failed");
        assertThat(jobService.listSteps(sourceJobId)).allSatisfy(step ->
                assertThat(step.getStatus()).isEqualTo("pending"));
        assertThat(jobService.listSteps(sourceJobId).stream().map(step -> step.getId()).toList())
                .isEqualTo(sourceStepIds);
        assertThat(snapshots.findByJobId(resumedJobId).orElseThrow().getSnapshotJson())
                .isEqualTo(sourceSnapshot);
    }

    @Test
    void resumesFailedComponentInstallWithTheOriginalComponentPlan() {
        Cluster cluster = preparedCluster("component", true);
        cluster.markInstallationStarted();
        cluster.markInstallationFinished(true);
        clusters.saveAndFlush(cluster);
        components.saveAndFlush(new ClusterComponent(cluster, "traefik", true, "{}"));
        states.saveAndFlush(new ClusterComponentState(cluster, "traefik"));
        cluster.markComponentConfigurationChanged();
        clusters.saveAndFlush(cluster);

        long sourceJobId = componentInstalls.start(cluster.getId());
        Job source = jobs.findById(sourceJobId).orElseThrow();
        source.markFailed();
        jobs.saveAndFlush(source);
        componentStates.complete(source, false);

        long resumedJobId = resumes.resume(cluster.getId(), sourceJobId);

        Job resumed = jobs.findById(resumedJobId).orElseThrow();
        assertThat(resumed.getType()).isEqualTo(ComponentInstallationStateService.JOB_TYPE);
        assertThat(resumed.getSourceJob().getId()).isEqualTo(sourceJobId);
        assertThat(resumed.getRunMode()).isEqualTo("resume");
        assertThat(states.findByClusterIdAndComponentKey(cluster.getId(), "traefik").orElseThrow()
                .getLastJobId()).isEqualTo(resumedJobId);
    }

    @Test
    void rejectsSuccessAndConfigurationDriftWithoutCreatingAJob() {
        Cluster successCluster = preparedCluster("success", false);
        long successJobId = installs.start(successCluster.getId());
        Job successful = jobs.findById(successJobId).orElseThrow();
        successful.markSuccess();
        jobs.saveAndFlush(successful);

        assertThatThrownBy(() -> resumes.resume(successCluster.getId(), successJobId))
                .isInstanceOf(InstallResumeException.class)
                .hasMessageContaining("状态不支持");

        Cluster changedCluster = preparedCluster("changed", false);
        long changedJobId = installs.start(changedCluster.getId());
        Job failed = jobs.findById(changedJobId).orElseThrow();
        failed.markFailed();
        jobs.saveAndFlush(failed);
        Node changedNode = nodes.findByClusterIdOrderById(changedCluster.getId()).get(0);
        changedNode.update(null, null, null, null, null, 2202);
        nodes.saveAndFlush(changedNode);
        long before = jobs.count();

        assertThatThrownBy(() -> resumes.resume(changedCluster.getId(), changedJobId))
                .isInstanceOf(InstallResumeException.class)
                .hasMessageContaining("已变化");
        assertThat(jobs.count()).isEqualTo(before);
    }

    @Test
    void supportsASecondResumeWithoutChangingTheOriginalJob() {
        Cluster cluster = preparedCluster("chain", false);
        long originalId = installs.start(cluster.getId());
        Job original = jobs.findById(originalId).orElseThrow();
        original.markFailed();
        jobs.saveAndFlush(original);
        long firstResumeId = resumes.resume(cluster.getId(), originalId);
        Job firstResume = jobs.findById(firstResumeId).orElseThrow();
        firstResume.markInterrupted();
        jobs.saveAndFlush(firstResume);

        long secondResumeId = resumes.resume(cluster.getId(), firstResumeId);

        assertThat(jobs.findById(secondResumeId).orElseThrow().getSourceJob().getId())
                .isEqualTo(firstResumeId);
        assertThat(jobs.findById(firstResumeId).orElseThrow().getSourceJob().getId())
                .isEqualTo(originalId);
        assertThat(jobs.findById(originalId).orElseThrow().getSourceJob()).isNull();
    }

    @Test
    void rejectsHistoricalCrossClusterAndConcurrentResumeRequests() {
        Cluster historicalCluster = preparedCluster("historical", false);
        long historicalJobId = installs.start(historicalCluster.getId());
        Job historical = jobs.findById(historicalJobId).orElseThrow();
        historical.markFailed();
        jobs.saveAndFlush(historical);
        InstallationSnapshot historicalSnapshot = snapshots.findByJobId(historicalJobId).orElseThrow();
        jdbc.update("update installation_snapshots set snapshot_json = ? where id = ?",
                historicalSnapshot.getSnapshotJson().replace(
                        "\"componentPlanVersion\":\"v0.3.2\"",
                        "\"componentPlanVersion\":\"v0.3.1\""),
                historicalSnapshot.getId());

        assertThatThrownBy(() -> resumes.resume(historicalCluster.getId(), historicalJobId))
                .isInstanceOf(InstallResumeException.class)
                .hasMessageContaining("完整快照");

        Cluster otherCluster = preparedCluster("other", false);
        assertThatThrownBy(() -> resumes.resume(otherCluster.getId(), historicalJobId))
                .isInstanceOf(InstallResumeException.class)
                .hasMessageContaining("不属于当前集群");

        Cluster activeCluster = preparedCluster("active", false);
        long activeSourceId = installs.start(activeCluster.getId());
        Job activeSource = jobs.findById(activeSourceId).orElseThrow();
        activeSource.markFailed();
        jobs.saveAndFlush(activeSource);
        jobs.saveAndFlush(new Job(activeCluster, "reset"));

        assertThatThrownBy(() -> resumes.resume(activeCluster.getId(), activeSourceId))
                .isInstanceOf(ActiveInstallerJobException.class);

        Cluster unsupportedCluster = preparedCluster("unsupported", false);
        Job unsupported = new Job(unsupportedCluster, "precheck");
        unsupported.markFailed();
        unsupported = jobs.saveAndFlush(unsupported);
        long unsupportedId = unsupported.getId();
        assertThatThrownBy(() -> resumes.resume(unsupportedCluster.getId(), unsupportedId))
                .isInstanceOf(InstallResumeException.class)
                .hasMessageContaining("类型不支持");
    }

    private Cluster preparedCluster(String suffix, boolean kubemateEnabled) {
        Cluster cluster = new Cluster("resume-" + suffix + "-" + System.nanoTime());
        cluster.update(null, null, "1.30.14", "10.244.0.0/16", "10.96.0.0/12",
                "registry", "10.0.0.10", 5000, null);
        cluster.updateInstallationConfiguration("/data/kubernetes", "REGISTRY");
        cluster.updateKubemateEnabled(kubemateEnabled);
        cluster.markNodeTestStatus("success");
        cluster = clusters.saveAndFlush(cluster);

        Node control = new Node(cluster);
        control.update("cp-" + suffix, "10.0.0.10", "", null, "root", 22);
        control.replaceRoles(java.util.Set.of("control_plane", "registry"));
        control.completeNodeTest("kylin", "V10", "amd64");
        nodes.saveAndFlush(control);

        Node worker = new Node(cluster);
        worker.update("worker-" + suffix, "10.0.0.11", "", null, "root", 22);
        worker.replaceRoles(java.util.Set.of("worker"));
        worker.completeNodeTest("kylin", "V10", "amd64");
        nodes.saveAndFlush(worker);
        return cluster;
    }
}
