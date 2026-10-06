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
import io.kubefoundry.job.JobStep;
import io.kubefoundry.job.JobStepNode;
import io.kubefoundry.job.JobStepNodeRepository;
import io.kubefoundry.job.JobStepRepository;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:install-resume;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate",
        "kubefoundry.project-dir=target/install-resume-media",
        "kubefoundry.app-dir=target/install-resume-media",
        "kubefoundry.data-dir=target/install-resume-data"
})
class InstallResumeServiceTest {
    @Autowired JdbcTemplate jdbc;
    @Autowired ClusterRepository clusters;
    @Autowired NodeRepository nodes;
    @Autowired ClusterComponentRepository components;
    @Autowired ClusterComponentStateRepository states;
    @Autowired JobRepository jobs;
    @Autowired JobService jobService;
    @Autowired JobStepRepository steps;
    @Autowired JobStepNodeRepository stepNodes;
    @Autowired InstallationSnapshotRepository snapshots;
    @Autowired InstallService installs;
    @Autowired ComponentInstallService componentInstalls;
    @Autowired ComponentInstallationStateService componentStates;
    @Autowired InstallResumeService resumes;
    @Autowired ClusterSettingsService settings;
    @Autowired PlatformTransactionManager transactionManager;

    @MockBean JobExecutor executor;
    @MockBean RemoteStepRunner runner;

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
        jdbc.update("delete from app_settings");
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
    void resumesUnchangedSnapshotWithMinioRuntimeParameters() throws Exception {
        Path mediaRoot = Path.of("target/install-resume-media/kube-media/03.setup_file/v1.30.14");
        for (String directory : java.util.List.of("helmapp/openebs", "minio", "helmapp/loki", "helmapp/alloy")) {
            Path chart = mediaRoot.resolve(directory);
            Files.createDirectories(chart);
            Files.writeString(chart.resolve("Chart.yaml"), "name: test\n", StandardCharsets.UTF_8);
        }
        Cluster cluster = preparedCluster("minio-runtime", false);
        for (int index = 2; index <= 4; index++) {
            Node worker = new Node(cluster);
            worker.update("worker-minio-" + index, "10.0.0." + (10 + index), "", "worker", "root", 22);
            worker.replaceRoles(java.util.Set.of("worker"));
            worker.completeNodeTest("kylin", "V10", "amd64");
            nodes.saveAndFlush(worker);
        }
        components.saveAndFlush(new ClusterComponent(cluster, "storage_observability", true,
                "{\"minio_pvc_size\":\"20Gi\",\"minio_cpu_request\":\"500m\"}"));
        states.saveAndFlush(new ClusterComponentState(cluster, "storage_observability"));
        long sourceJobId = installs.start(cluster.getId());
        Job source = jobs.findById(sourceJobId).orElseThrow();
        source.markFailed();
        jobs.saveAndFlush(source);
        String frozen = snapshots.findByJobId(sourceJobId).orElseThrow().getSnapshotJson();
        componentStates.complete(source, false);
        assertThat(frozen).contains("\"minio_pvc_size\":\"20Gi\"");

        long resumedJobId = resumes.resume(cluster.getId(), sourceJobId);

        assertThat(jobs.findById(resumedJobId).orElseThrow().getSourceJob().getId()).isEqualTo(sourceJobId);
        assertThat(snapshots.findByJobId(resumedJobId).orElseThrow().getSnapshotJson()).isEqualTo(frozen);
    }

    @Test
    void stillRejectsChangedGlobalRuntimeSettingsWithoutCreatingAJob() {
        Cluster cluster = preparedCluster("runtime-drift", false);
        long sourceJobId = installs.start(cluster.getId());
        Job source = jobs.findById(sourceJobId).orElseThrow();
        source.markFailed();
        jobs.saveAndFlush(source);
        long before = jobs.count();
        settings.updateGlobalSettings(java.util.Map.of("env", java.util.Map.of("containerd_root", "/data/changed")));

        assertThatThrownBy(() -> resumes.resume(cluster.getId(), sourceJobId))
                .isInstanceOf(InstallResumeException.class)
                .hasMessageContaining("安装路径或运行参数已变化");
        assertThat(jobs.count()).isEqualTo(before);
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
    void resumeReusesSuccessfulNodesButRerunExecutesThemAgain() throws Exception {
        Cluster cluster = preparedCluster("execution-range", false);
        long sourceId = installs.start(cluster.getId());
        List<JobStep> planned = jobService.listSteps(sourceId).stream()
                .filter(step -> !jobService.listStepNodes(step.getId()).isEmpty()).toList();
        JobStep completed = planned.get(0);
        JobStep failed = planned.get(1);
        completed.markSuccess();
        steps.saveAndFlush(completed);
        for (JobStepNode node : jobService.listStepNodes(completed.getId())) {
            node.complete(JobService.NodeOutcome.successful());
            stepNodes.saveAndFlush(node);
        }
        failed.markFailed();
        steps.saveAndFlush(failed);
        for (JobStepNode node : jobService.listStepNodes(failed.getId())) {
            node.markFailed("原任务失败");
            stepNodes.saveAndFlush(node);
        }
        Job source = jobs.findById(sourceId).orElseThrow();
        source.markFailed();
        jobs.saveAndFlush(source);
        executeSubmittedJobs();

        long resumedId = resumes.resume(cluster.getId(), sourceId);

        assertThat(jobs.findById(resumedId).orElseThrow().getStatus()).isEqualTo("success");
        assertThat(jobService.listSteps(resumedId)).hasSameSizeAs(jobService.listSteps(sourceId));
        assertThat(jobService.listSteps(resumedId).get(completed.getOrder() - 1).getStatusReason())
                .isEqualTo("RESUME_SOURCE_SUCCEEDED");
        verify(runner, never()).run(eq(resumedId), any(), anyList(), any(),
                argThat(step -> completed.getStepKey().equals(step.key())), any(RuntimeSettings.class));
        verify(runner, atLeastOnce()).run(eq(resumedId), any(), anyList(), any(),
                argThat(step -> failed.getStepKey().equals(step.key())), any(RuntimeSettings.class));

        long rerunId = resumes.rerun(cluster.getId(), sourceId);

        assertThat(jobs.findById(rerunId).orElseThrow().getRunMode()).isEqualTo("rerun");
        assertThat(jobs.findById(rerunId).orElseThrow().getSourceJob().getId()).isEqualTo(sourceId);
        verify(runner, atLeastOnce()).run(eq(rerunId), any(), anyList(), any(),
                argThat(step -> completed.getStepKey().equals(step.key())), any(RuntimeSettings.class));
        assertThat(jobService.listStepNodes(
                jobService.listSteps(sourceId).get(completed.getOrder() - 1).getId()))
                .allSatisfy(node -> assertThat(node.getStatus()).isEqualTo("success"));
    }

    @Test
    void secondResumeRecoversAncestorSuccessAfterFirstRunAborted() throws Exception {
        Cluster cluster = preparedCluster("ancestor", false);
        long sourceId = installs.start(cluster.getId());
        List<JobStep> planned = jobService.listSteps(sourceId).stream()
                .filter(step -> !jobService.listStepNodes(step.getId()).isEmpty()).toList();
        JobStep completed = planned.get(0);
        JobStep failed = planned.get(1);
        JobStep laterCompleted = planned.get(planned.size() - 1);
        for (JobStep step : List.of(completed, laterCompleted)) {
            step.markSuccess();
            steps.saveAndFlush(step);
            for (JobStepNode node : jobService.listStepNodes(step.getId())) {
                node.complete(JobService.NodeOutcome.successful());
                stepNodes.saveAndFlush(node);
            }
        }
        failed.markFailed();
        steps.saveAndFlush(failed);
        for (JobStepNode node : jobService.listStepNodes(failed.getId())) {
            node.markFailed("原任务失败");
            stepNodes.saveAndFlush(node);
        }
        Job source = jobs.findById(sourceId).orElseThrow();
        source.markPartialSuccess();
        jobs.saveAndFlush(source);
        AtomicInteger failures = new AtomicInteger(1);
        executeSubmittedJobs();
        when(runner.run(anyLong(), any(), anyList(), any(), any(), any(RuntimeSettings.class))).thenAnswer(invocation -> {
            InstallStep step = invocation.getArgument(4);
            if (step.key().equals(failed.getStepKey()) && failures.getAndDecrement() > 0) {
                return new JobService.NodeOutcome(false, 1, "本次执行失败", "");
            }
            return JobService.NodeOutcome.successful();
        });

        long firstId = resumes.resume(cluster.getId(), sourceId);
        assertThat(jobs.findById(firstId).orElseThrow().getStatus()).isEqualTo("failed");
        JobStep firstLater = jobService.listSteps(firstId).get(laterCompleted.getOrder() - 1);
        assertThat(firstLater.getStatusReason()).isEqualTo("JOB_ABORTED");

        long secondId = resumes.resume(cluster.getId(), firstId);

        assertThat(jobs.findById(secondId).orElseThrow().getStatus()).isEqualTo("success");
        verify(runner, never()).run(eq(secondId), any(), anyList(), any(),
                argThat(step -> completed.getStepKey().equals(step.key())), any(RuntimeSettings.class));
        verify(runner, never()).run(eq(secondId), any(), anyList(), any(),
                argThat(step -> laterCompleted.getStepKey().equals(step.key())), any(RuntimeSettings.class));
        verify(runner, atLeastOnce()).run(eq(secondId), any(), anyList(), any(),
                argThat(step -> failed.getStepKey().equals(step.key())), any(RuntimeSettings.class));
        assertThat(jobService.listSteps(secondId).get(laterCompleted.getOrder() - 1).getStatusReason())
                .isEqualTo("RESUME_SOURCE_SUCCEEDED");
    }

    @Test
    void resumeRechecksJoinProducerOnlyWhenAConsumerNeedsFreshArtifacts() throws Exception {
        Cluster cluster = preparedCluster("artifacts", false);
        long sourceId = installs.start(cluster.getId());
        JobStep producer = jobService.listSteps(sourceId).stream()
                .filter(step -> "18-init-k8s-cluster".equals(step.getStepKey()))
                .findFirst().orElseThrow();
        producer.markSuccess();
        steps.saveAndFlush(producer);
        for (JobStepNode node : jobService.listStepNodes(producer.getId())) {
            node.complete(JobService.NodeOutcome.successful());
            stepNodes.saveAndFlush(node);
        }
        JobStep consumer = jobService.listSteps(sourceId).stream()
                .filter(step -> "21-add-worker-nodes".equals(step.getStepKey()))
                .findFirst().orElseThrow();
        consumer.markSuccess();
        steps.saveAndFlush(consumer);
        for (JobStepNode node : jobService.listStepNodes(consumer.getId())) {
            node.complete(JobService.NodeOutcome.successful());
            stepNodes.saveAndFlush(node);
        }
        Job source = jobs.findById(sourceId).orElseThrow();
        source.markFailed();
        jobs.saveAndFlush(source);
        executeSubmittedJobs();

        long resumedId = resumes.resume(cluster.getId(), sourceId);

        verify(runner, never()).run(eq(resumedId), any(), anyList(), any(),
                argThat(step -> producer.getStepKey().equals(step.key())), any(RuntimeSettings.class));

        consumer.markFailed();
        steps.saveAndFlush(consumer);
        for (JobStepNode node : jobService.listStepNodes(consumer.getId())) {
            node.markFailed("需重试加入节点");
            stepNodes.saveAndFlush(node);
        }
        long retryId = resumes.resume(cluster.getId(), sourceId);

        verify(runner, atLeastOnce()).run(eq(retryId), any(), anyList(), any(),
                argThat(step -> producer.getStepKey().equals(step.key())), any(RuntimeSettings.class));
    }

    @Test
    void latestRerunFailureOverridesOlderSuccessfulStep() throws Exception {
        Cluster cluster = preparedCluster("rerun-baseline", false);
        long sourceId = installs.start(cluster.getId());
        JobStep completed = jobService.listSteps(sourceId).stream()
                .filter(step -> !jobService.listStepNodes(step.getId()).isEmpty())
                .findFirst().orElseThrow();
        completed.markSuccess();
        steps.saveAndFlush(completed);
        for (JobStepNode node : jobService.listStepNodes(completed.getId())) {
            node.complete(JobService.NodeOutcome.successful());
            stepNodes.saveAndFlush(node);
        }
        Job source = jobs.findById(sourceId).orElseThrow();
        source.markFailed();
        jobs.saveAndFlush(source);
        executeSubmittedJobs();
        AtomicInteger failures = new AtomicInteger(1);
        when(runner.run(anyLong(), any(), anyList(), any(), any(), any(RuntimeSettings.class)))
                .thenAnswer(invocation -> {
                    InstallStep step = invocation.getArgument(4);
                    if (step.key().equals(completed.getStepKey()) && failures.getAndDecrement() > 0) {
                        return new JobService.NodeOutcome(false, 1, "本次重跑失败", "");
                    }
                    return JobService.NodeOutcome.successful();
                });

        long rerunId = resumes.rerun(cluster.getId(), sourceId);
        assertThat(jobs.findById(rerunId).orElseThrow().getStatus()).isEqualTo("failed");

        long resumedId = resumes.resume(cluster.getId(), rerunId);

        verify(runner, atLeastOnce()).run(eq(resumedId), any(), anyList(), any(),
                argThat(step -> completed.getStepKey().equals(step.key())), any(RuntimeSettings.class));
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

    private void executeSubmittedJobs() throws Exception {
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        doAnswer(invocation -> {
            transaction.executeWithoutResult(status ->
                    invocation.getArgument(0, Runnable.class).run());
            return null;
        }).when(executor).submit(any(Runnable.class));
        when(executor.executeNodes(anyList(), anyInt(), anyBoolean())).thenAnswer(invocation -> {
            List<JobExecutor.NodeWork> work = invocation.getArgument(0);
            List<JobExecutor.NodeResult> results = new ArrayList<>();
            for (JobExecutor.NodeWork item : work) {
                try {
                    item.action().run();
                    results.add(new JobExecutor.NodeResult(item.nodeId(), "success", ""));
                } catch (Exception exception) {
                    results.add(new JobExecutor.NodeResult(item.nodeId(), "failed", exception.getMessage()));
                }
            }
            String status = results.stream().allMatch(result -> "success".equals(result.status()))
                    ? "success" : "failed";
            return new JobExecutor.ExecutionSummary(status, List.copyOf(results));
        });
        when(runner.run(anyLong(), any(), anyList(), any(), any(), any(RuntimeSettings.class)))
                .thenReturn(JobService.NodeOutcome.successful());
    }
}
