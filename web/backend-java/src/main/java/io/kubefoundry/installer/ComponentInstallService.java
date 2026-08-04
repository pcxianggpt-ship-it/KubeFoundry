package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponent;
import io.kubefoundry.cluster.ClusterComponentRepository;
import io.kubefoundry.cluster.ClusterComponentState;
import io.kubefoundry.cluster.ClusterComponentStateRepository;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.KubemateComponentCatalog;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.JobService;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;

/** Transactional admission boundary for future component plans. */
@Service
public class ComponentInstallService {
    private final ClusterRepository clusters;
    private final ClusterComponentRepository components;
    private final ClusterComponentStateRepository states;
    private final NodeRepository nodes;
    private final JobService jobs;
    private final InstallerAdmission admission;
    private final InstallationSnapshotService snapshots;
    private final InstallPlanAssembler assembler;
    private final InstallPlanFactory plans;
    private final RemoteStepRunner runner;
    private final ClusterSettingsService settings;
    private final ComponentMediaService media;

    public ComponentInstallService(
            ClusterRepository clusters,
            ClusterComponentRepository components,
            ClusterComponentStateRepository states,
            NodeRepository nodes,
            JobService jobs,
            InstallerAdmission admission,
            InstallationSnapshotService snapshots,
            InstallPlanAssembler assembler,
            InstallPlanFactory plans,
            RemoteStepRunner runner,
            ClusterSettingsService settings,
            ComponentMediaService media) {
        this.clusters = clusters;
        this.components = components;
        this.states = states;
        this.nodes = nodes;
        this.jobs = jobs;
        this.admission = admission;
        this.snapshots = snapshots;
        this.assembler = assembler;
        this.plans = plans;
        this.runner = runner;
        this.settings = settings;
        this.media = media;
    }

    public long start(long clusterId) {
        Cluster cluster = clusters.findById(clusterId)
                .orElseThrow(() -> new IllegalArgumentException("集群不存在: " + clusterId));
        if (!cluster.isInstallationLocked()) {
            throw new IllegalStateException("Kubernetes 基础安装完成后才能补装组件");
        }
        List<Node> configuredNodes = InstallationNodes.normalize(nodes.findByClusterIdOrderById(clusterId));
        InstallationSnapshotPayload snapshot = snapshots.previewPayload(cluster, configuredNodes);
        Set<String> candidates = installableGroups(snapshot, clusterId);
        InstallPlan plan = media.verifyAndChecksum(assembler.forExistingCluster(snapshot, candidates));
        if (plan.steps().isEmpty()) throw new IllegalStateException("没有可补装的 Kubemate 组件组");
        List<JobService.StepDefinition> definitions = new ArrayList<>();
        for (int index = 0; index < plan.steps().size(); index++) {
            InstallStep step = plan.steps().get(index);
            List<Node> targets = plans.resolveTargets(step, cluster, configuredNodes);
            if (targets.isEmpty()) {
                throw new IllegalArgumentException("组件安装步骤缺少目标节点: " + step.key());
            }
            List<JobService.NodeOperation> operations = targets.stream()
                    .map(node -> JobService.NodeOperation.withOutcome(node.getId(), jobId -> {
                        RuntimeSettings runtimeSettings = settings.runtimeSettings(cluster, node);
                        return runner.run(jobId, cluster, configuredNodes, node, step, runtimeSettings);
                    }))
                    .toList();
            definitions.add(new JobService.StepDefinition(step.name(), index + 1, step.maxWorkers(),
                    step.failFast(), operations, step.componentGroupKey()));
        }
        return submit(clusterId, snapshot.componentConfigurationVersion(), definitions, media.checksums(plan));
    }

    public long submit(
            long clusterId,
            long expectedConfigurationVersion,
            List<JobService.StepDefinition> steps,
            Map<String, String> mediaChecksums) {
        return admission.submit(clusterId, () -> {
            Cluster cluster = clusters.findByIdForUpdate(clusterId)
                    .orElseThrow(() -> new IllegalArgumentException("集群不存在: " + clusterId));
            if (cluster.getComponentConfigVersion() != expectedConfigurationVersion) {
                throw new IllegalStateException("组件配置已变化，请重新预检查并生成安装计划");
            }
            Set<String> groupKeys = componentGroupKeys(steps);
            validateSubmission(cluster, groupKeys);
            long jobId = jobs.submit(new JobService.JobDefinition(
                    clusterId, ComponentInstallationStateService.JOB_TYPE, List.copyOf(steps)));
            List<Node> configuredNodes = InstallationNodes.normalize(nodes.findByClusterIdOrderById(clusterId));
            snapshots.capture(jobId, cluster, configuredNodes,
                    mediaChecksums == null ? Map.of() : Map.copyOf(mediaChecksums));
            return jobId;
        });
    }

    private void validateSubmission(Cluster cluster, Set<String> groupKeys) {
        if (!cluster.isKubemateEnabled()) {
            throw new IllegalStateException("Kubemate 组件安装总开关未启用");
        }
        for (String groupKey : groupKeys) {
            KubemateComponentCatalog.Group definition = KubemateComponentCatalog.find(groupKey);
            if (definition == null || !definition.available()) {
                throw new IllegalArgumentException("组件组不可安装: " + groupKey);
            }
            ClusterComponent component = components.findByClusterIdAndComponentKey(cluster.getId(), groupKey)
                    .orElseThrow(() -> new IllegalStateException("组件组配置不存在: " + groupKey));
            if (!component.isEnabled()) {
                throw new IllegalStateException("组件组未启用: " + groupKey);
            }
            ClusterComponentState state = states.findByClusterIdAndComponentKey(cluster.getId(), groupKey)
                    .orElseThrow(() -> new IllegalStateException("组件组状态不存在: " + groupKey));
            if (!ClusterComponentState.NOT_INSTALLED.equals(state.getStatus())
                    && !ClusterComponentState.FAILED.equals(state.getStatus())) {
                throw new IllegalStateException("组件组当前不可安装: " + groupKey);
            }
        }
    }

    private static Set<String> componentGroupKeys(List<JobService.StepDefinition> steps) {
        if (steps == null || steps.isEmpty()) {
            throw new IllegalArgumentException("组件安装任务缺少步骤");
        }
        Set<String> groupKeys = new LinkedHashSet<>();
        for (JobService.StepDefinition step : steps) {
            if (step == null) throw new IllegalArgumentException("组件安装步骤不能为空");
            if (step.componentGroupKey() != null && !step.componentGroupKey().isBlank()) {
                groupKeys.add(step.componentGroupKey());
            }
        }
        if (groupKeys.isEmpty()) throw new IllegalArgumentException("组件安装任务缺少组件组");
        return groupKeys;
    }

    private Set<String> installableGroups(InstallationSnapshotPayload snapshot, long clusterId) {
        Set<String> values = new LinkedHashSet<>();
        for (ClusterComponentState state : states.findByClusterIdOrderByComponentKey(clusterId)) {
            if (ClusterComponentState.NOT_INSTALLED.equals(state.getStatus())
                    || ClusterComponentState.FAILED.equals(state.getStatus())) {
                values.add(state.getComponentKey());
            }
        }
        values.retainAll(snapshot.componentGroups().stream()
                .filter(InstallationSnapshotPayload.ComponentGroup::enabled)
                .map(InstallationSnapshotPayload.ComponentGroup::key)
                .collect(java.util.stream.Collectors.toSet()));
        return values;
    }
}
