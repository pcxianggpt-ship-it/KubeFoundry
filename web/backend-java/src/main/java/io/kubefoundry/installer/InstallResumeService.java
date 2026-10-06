package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.ClusterService.ResourceNotFoundException;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobService;
import io.kubefoundry.job.JobStep;
import io.kubefoundry.job.JobStepNode;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import org.springframework.stereotype.Service;

/** Creates a new immutable-snapshot-driven job from an eligible terminal installation job. */
@Service
public class InstallResumeService {
    private static final Set<String> SUPPORTED_TYPES = Set.of(
            "install", ComponentInstallationStateService.JOB_TYPE);
    private static final Set<String> SUPPORTED_STATUSES = Set.of(
            "failed", "interrupted", "partial_success");

    private final ClusterRepository clusters;
    private final NodeRepository nodes;
    private final JobService jobs;
    private final InstallerAdmission admission;
    private final InstallationSnapshotService snapshots;
    private final InstallPlanAssembler assembler;
    private final InstallPlanFactory plans;
    private final RemoteStepRunner runner;
    private final ComponentMediaService media;

    public InstallResumeService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobService jobs,
            InstallerAdmission admission,
            InstallationSnapshotService snapshots,
            InstallPlanAssembler assembler,
            InstallPlanFactory plans,
            RemoteStepRunner runner,
            ComponentMediaService media) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobs = jobs;
        this.admission = admission;
        this.snapshots = snapshots;
        this.assembler = assembler;
        this.plans = plans;
        this.runner = runner;
        this.media = media;
    }

    public long resume(long clusterId, long sourceJobId) {
        return submit(clusterId, sourceJobId, "resume");
    }

    public long rerun(long clusterId, long sourceJobId) {
        return submit(clusterId, sourceJobId, "rerun");
    }

    private long submit(long clusterId, long sourceJobId, String runMode) {
        if (!clusters.existsById(clusterId)) {
            throw ResourceNotFoundException.cluster(clusterId);
        }
        return admission.submit(clusterId, () -> submitLocked(clusterId, sourceJobId, runMode));
    }

    private long submitLocked(long clusterId, long sourceJobId, String runMode) {
        Cluster cluster = clusters.findByIdForUpdate(clusterId)
                .orElseThrow(() -> new InstallResumeException(
                        "RESUME_SOURCE_NOT_SUPPORTED", "集群不存在"));
        Job source = jobs.get(sourceJobId);
        validateSource(clusterId, source);
        InstallationSnapshotPayload snapshot = snapshots.payloadForJob(sourceJobId);
        List<Node> configuredNodes = InstallationNodes.normalize(
                nodes.findByClusterIdOrderById(clusterId));
        validateSnapshot(cluster, configuredNodes, snapshot);

        Set<String> componentGroups = sourceComponentGroups(source);
        InstallPlan generated = "install".equals(source.getType())
                ? assembler.forNewCluster(snapshot)
                : assembler.forExistingCluster(snapshot, componentGroups);
        InstallPlan plan = media.applySnapshotChecksums(generated, snapshot);
        List<JobService.StepDefinition> definitions = definitions(
                cluster, configuredNodes, snapshot, plan,
                ComponentInstallationStateService.JOB_TYPE.equals(source.getType()));
        validateSourcePlan(source, definitions);
        if ("resume".equals(runMode)) {
            definitions = reuseCompletedNodes(source, snapshot, plan, definitions);
        }

        if ("install".equals(source.getType())) {
            cluster.markInstallationStarted();
            clusters.save(cluster);
        }
        long jobId = jobs.submit(new JobService.JobDefinition(
                clusterId, source.getType(), definitions, sourceJobId, runMode));
        snapshots.copyForResume(sourceJobId, jobId);
        return jobId;
    }

    private List<JobService.StepDefinition> reuseCompletedNodes(
            Job source, InstallationSnapshotPayload snapshot,
            InstallPlan plan,
            List<JobService.StepDefinition> definitions) {
        Map<StepNodeKey, Boolean> latestOutcomes = new HashMap<>();
        Set<Long> visited = new HashSet<>();
        for (Job ancestor = source; ancestor != null; ancestor = ancestor.getSourceJob()) {
            if (!visited.add(ancestor.getId())
                    || !ancestor.getCluster().getId().equals(source.getCluster().getId())
                    || !ancestor.getType().equals(source.getType())
                    || !snapshots.payloadForJob(ancestor.getId()).equals(snapshot)) {
                throw changed("来源任务血缘与快照不一致");
            }
            validateSourcePlan(ancestor, definitions);
            for (JobStep step : jobs.listSteps(ancestor.getId())) {
                for (JobStepNode node : jobs.listStepNodes(step.getId())) {
                    Boolean reusable = reusableOutcome(node);
                    if (reusable != null) {
                        latestOutcomes.putIfAbsent(
                                new StepNodeKey(step.getStepKey(), node.getNode().getId()), reusable);
                    }
                }
            }
            // 全量重跑重新建立执行基线；它之前的成功结果不能覆盖这次的失败。
            if (!"resume".equals(ancestor.getRunMode())) break;
        }

        Set<String> requiredArtifacts = new HashSet<>();
        for (InstallStep step : plan.steps()) {
            List<JobService.NodeOperation> targets = definitions.stream()
                    .filter(definition -> definition.stepKey().equals(step.key()))
                    .findFirst().orElseThrow().nodes();
            if (targets.stream().anyMatch(operation -> !Boolean.TRUE.equals(
                    latestOutcomes.get(new StepNodeKey(step.key(), operation.nodeId()))))) {
                for (InstallStep.Resource resource : step.resources()) {
                    if (resource.artifactKey() != null) requiredArtifacts.add(resource.artifactKey());
                }
            }
        }
        for (InstallStep step : plan.steps()) {
            if (step.outputs().stream().anyMatch(output -> requiredArtifacts.contains(output.key()))) {
                // 后继节点需要新任务的产物时，重新进入产出步骤的前置验证与恢复流程。
                // 例如 18-init-k8s-cluster 会刷新 join token 并下载到当前任务目录。
                definitions.stream().filter(definition -> definition.stepKey().equals(step.key()))
                        .findFirst().orElseThrow().nodes().forEach(operation ->
                                latestOutcomes.put(
                                        new StepNodeKey(step.key(), operation.nodeId()), false));
            }
        }

        List<JobService.StepDefinition> reused = new ArrayList<>();
        for (JobService.StepDefinition step : definitions) {
            List<JobService.NodeOperation> operations = step.nodes().stream().map(operation ->
                    Boolean.TRUE.equals(latestOutcomes.get(
                            new StepNodeKey(step.stepKey(), operation.nodeId())))
                            ? JobService.NodeOperation.withOutcome(operation.nodeId(),
                                    ignored -> JobService.NodeOutcome.resumed())
                            : operation).toList();
            reused.add(new JobService.StepDefinition(
                    step.name(), step.order(), step.maxWorkers(), step.failFast(), operations,
                    step.componentGroupKey(), step.stepKey(), step.stageKey(), step.stageName(),
                    step.stageOrder(), step.stepOrderInStage()));
        }
        return List.copyOf(reused);
    }

    private static Boolean reusableOutcome(JobStepNode node) {
        if ("success".equals(node.getStatus())) return true;
        if ("skipped".equals(node.getStatus()) && Set.of(
                "PREVERIFY_SATISFIED", "RESUME_SOURCE_SUCCEEDED").contains(node.getMessage())) {
            return true;
        }
        if ("failed".equals(node.getStatus()) || "running".equals(node.getStatus())) {
            return false;
        }
        return null;
    }

    private record StepNodeKey(String stepKey, long nodeId) {}

    private void validateSource(long clusterId, Job source) {
        if (!source.getCluster().getId().equals(clusterId)) {
            throw new InstallResumeException(
                    "RESUME_SOURCE_NOT_SUPPORTED", "来源任务不属于当前集群");
        }
        if (!SUPPORTED_TYPES.contains(source.getType())) {
            throw new InstallResumeException(
                    "RESUME_SOURCE_NOT_SUPPORTED", "该任务类型不支持续跑");
        }
        if (!SUPPORTED_STATUSES.contains(source.getStatus())) {
            throw new InstallResumeException(
                    "RESUME_SOURCE_NOT_SUPPORTED", "该任务状态不支持续跑");
        }
    }

    private void validateSnapshot(
            Cluster cluster, List<Node> configuredNodes, InstallationSnapshotPayload snapshot) {
        if (snapshot.clusterId() != cluster.getId()) {
            throw new InstallResumeException(
                    "RESUME_SNAPSHOT_MISMATCH", "来源快照不属于当前集群");
        }
        if (!InstallationSnapshotPayload.COMPONENT_PLAN_VERSION.equals(snapshot.componentPlanVersion())
                || snapshot.clusterConfiguration() == null
                || snapshot.nodes().isEmpty()
                || snapshot.runtimeSettings().isEmpty()) {
            throw new InstallResumeException(
                    "RESUME_SNAPSHOT_MISMATCH", "来源任务不是可续跑的 v0.3.2 完整快照");
        }
        if (!Objects.equals(snapshot.clusterName(), cluster.getName())
                || !Objects.equals(snapshot.kubernetesVersion(), value(cluster.getKubernetesVersion()))
                || !Objects.equals(snapshot.kubernetesWorkDir(), value(cluster.getKubernetesWorkDir()))
                || !Objects.equals(snapshot.imageRegistryType(), value(cluster.getImageRegistryType()))
                || !snapshot.clusterConfiguration().equals(
                        InstallationSnapshotPayload.ClusterTarget.from(cluster))
                || snapshot.componentConfigurationVersion() != cluster.getComponentConfigVersion()) {
            throw changed("集群安装配置已变化");
        }

        InstallationSnapshotPayload current = InstallationSnapshotPayload.capture(
                cluster, configuredNodes, List.of(), Map.of());
        if (!snapshot.nodes().equals(current.nodes())) {
            throw changed("节点身份、SSH 参数、架构或凭据已变化");
        }
        // 与创建安装快照共用参数生成逻辑，包含已启用组件注入的运行参数。
        Map<Long, InstallationSnapshotPayload.RuntimeConfiguration> currentSettings =
                snapshots.previewPayload(cluster, configuredNodes).runtimeSettings();
        if (!snapshot.runtimeSettings().equals(currentSettings)) {
            throw changed("安装路径或运行参数已变化");
        }
    }

    private List<JobService.StepDefinition> definitions(
            Cluster cluster,
            List<Node> configuredNodes,
            InstallationSnapshotPayload snapshot,
            InstallPlan plan,
            boolean componentOnly) {
        List<JobService.StepDefinition> values = new ArrayList<>();
        InstallStepMetadata.Tracker metadata = InstallStepMetadata.tracker();
        for (int index = 0; index < plan.steps().size(); index++) {
            InstallStep step = plan.steps().get(index);
            List<Node> targets = plans.resolveTargets(step, cluster, configuredNodes);
            if (targets.isEmpty() && requiredTarget(step, componentOnly)) {
                throw new InstallResumeException(
                        "RESUME_SNAPSHOT_MISMATCH", "续跑步骤缺少目标节点: " + step.key());
            }
            List<JobService.NodeOperation> operations = targets.stream().map(node -> {
                InstallationSnapshotPayload.RuntimeConfiguration runtime =
                        snapshot.runtimeSettings().get(node.getId());
                if (runtime == null) {
                    throw new InstallResumeException(
                            "RESUME_SNAPSHOT_MISMATCH", "来源快照缺少节点运行参数");
                }
                return JobService.NodeOperation.withOutcome(node.getId(), jobId -> runner.run(
                        jobId, cluster, configuredNodes, node, step, runtime.toRuntimeSettings()));
            }).toList();
            values.add(metadata.definition(step, index + 1, operations));
        }
        return List.copyOf(values);
    }

    private void validateSourcePlan(Job source, List<JobService.StepDefinition> definitions) {
        List<JobStep> sourceSteps = jobs.listSteps(source.getId());
        if (sourceSteps.isEmpty() || sourceSteps.stream()
                .anyMatch(step -> step.getStepKey().startsWith("legacy-"))) {
            throw new InstallResumeException(
                    "RESUME_SNAPSHOT_MISMATCH", "来源任务缺少稳定步骤计划");
        }
        List<String> sourceKeys = sourceSteps.stream().map(JobStep::getStepKey).toList();
        List<String> rebuiltKeys = definitions.stream().map(JobService.StepDefinition::stepKey).toList();
        if (!sourceKeys.equals(rebuiltKeys)) {
            throw new InstallResumeException(
                    "RESUME_SNAPSHOT_MISMATCH", "来源任务计划与快照重建结果不一致");
        }
        for (int index = 0; index < sourceSteps.size(); index++) {
            Set<Long> sourceNodeIds = jobs.listStepNodes(sourceSteps.get(index).getId()).stream()
                    .map(item -> item.getNode().getId()).collect(java.util.stream.Collectors.toSet());
            Set<Long> rebuiltNodeIds = definitions.get(index).nodes().stream()
                    .map(JobService.NodeOperation::nodeId).collect(java.util.stream.Collectors.toSet());
            if (!sourceNodeIds.equals(rebuiltNodeIds)) {
                throw new InstallResumeException(
                        "RESUME_SNAPSHOT_MISMATCH", "来源任务目标节点与快照重建结果不一致");
            }
        }
    }

    private Set<String> sourceComponentGroups(Job source) {
        if ("install".equals(source.getType())) return Set.of();
        Set<String> values = new LinkedHashSet<>();
        for (JobStep step : jobs.listSteps(source.getId())) {
            if (step.getComponentGroupKey() != null && !step.getComponentGroupKey().isBlank()) {
                values.add(step.getComponentGroupKey());
            }
        }
        if (values.isEmpty()) {
            throw new InstallResumeException(
                    "RESUME_SNAPSHOT_MISMATCH", "来源组件任务缺少组件组计划");
        }
        return Set.copyOf(values);
    }

    private static boolean requiredTarget(InstallStep step, boolean componentOnly) {
        return componentOnly || List.of("primary_control_plane", "registry", "nfs_server")
                .contains(step.targetScope());
    }

    private static InstallResumeException changed(String message) {
        return new InstallResumeException("RESUME_SNAPSHOT_MISMATCH", message);
    }

    private static String value(String value) {
        return value == null ? "" : value.trim();
    }
}
