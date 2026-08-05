package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.ClusterService.ResourceNotFoundException;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.JobService;
import java.util.ArrayList;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class InstallService {

    private final ClusterRepository clusters;
    private final NodeRepository nodes;
    private final JobService jobService;
    private final InstallPlanFactory plans;
    private final InstallPlanAssembler assembler;
    private final RemoteStepRunner runner;
    private final ClusterSettingsService settings;
    private final InstallerAdmission admission;
    private final InstallationSnapshotService snapshots;
    private final ComponentMediaService media;

    @Autowired
    public InstallService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobService jobService,
            InstallPlanFactory plans,
            InstallPlanAssembler assembler,
            RemoteStepRunner runner,
            ClusterSettingsService settings,
            InstallerAdmission admission,
            InstallationSnapshotService snapshots,
            ComponentMediaService media) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobService = jobService;
        this.plans = plans;
        this.assembler = assembler;
        this.runner = runner;
        this.settings = settings;
        this.admission = admission;
        this.snapshots = snapshots;
        this.media = media;
    }

    public InstallService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobService jobService,
            InstallPlanFactory plans,
            RemoteStepRunner runner,
            ClusterSettingsService settings,
            InstallerAdmission admission,
            InstallationSnapshotService snapshots) {
        this(clusters, nodes, jobService, plans, null, runner, settings, admission, snapshots, null);
    }

    public long start(long clusterId) {
        return start(clusterId, List.of());
    }

    /** Client step selection is retained only to return a stable validation error for legacy callers. */
    public long start(long clusterId, List<String> selectedSteps) {
        if (selectedSteps != null && !selectedSteps.isEmpty()) {
            throw new IllegalArgumentException("安装步骤由服务端计划决定，不能由客户端选择");
        }
        Cluster cluster = clusters.findById(clusterId)
                .orElseThrow(() -> ResourceNotFoundException.cluster(clusterId));
        List<Node> configuredNodes = InstallationNodes.normalize(
                nodes.findByClusterIdOrderById(clusterId));
        ClusterTopologyValidator.requireValid(configuredNodes, cluster.getImageRegistryType());
        InstallationGate.requireSuccessfulNodeTests(cluster, configuredNodes);
        InstallPlan generatedPlan = assembler == null
                ? plans.create()
                : assembler.forNewCluster(snapshots.previewPayload(cluster, configuredNodes));
        InstallPlan plan = media == null ? generatedPlan : media.verifyAndChecksum(generatedPlan);
        List<JobService.StepDefinition> definitions = new ArrayList<>();
        for (int index = 0; index < plan.steps().size(); index++) {
            InstallStep step = plan.steps().get(index);
            List<Node> targets = plans.resolveTargets(step, cluster, configuredNodes);
            if (targets.isEmpty() && List.of("primary_control_plane", "registry", "nfs_server")
                    .contains(step.targetScope())) {
                throw new IllegalArgumentException("安装步骤缺少目标节点: " + step.key());
            }
            List<JobService.NodeOperation> operations = targets.stream()
                    .map(node -> JobService.NodeOperation.withOutcome(node.getId(), jobId -> {
                        RuntimeSettings runtimeSettings = settings == null
                                ? null : settings.runtimeSettings(cluster, node);
                        return runtimeSettings == null
                                ? runner.run(jobId, cluster, configuredNodes, node, step)
                                : runner.run(jobId, cluster, configuredNodes, node, step, runtimeSettings);
                    }))
                    .toList();
            definitions.add(new JobService.StepDefinition(
                    step.name(), index + 1, step.maxWorkers(), step.failFast(), operations,
                    step.componentGroupKey()));
        }
        return admission.submit(clusterId, () -> {
            Cluster admittedCluster = clusters.findById(clusterId)
                    .orElseThrow(() -> ResourceNotFoundException.cluster(clusterId));
            admittedCluster.markInstallationStarted();
            clusters.save(admittedCluster);
            long jobId = jobService.submit(new JobService.JobDefinition(clusterId, "install", definitions));
            if (media == null) {
                snapshots.capture(jobId, admittedCluster, configuredNodes);
            } else {
                snapshots.capture(jobId, admittedCluster, configuredNodes, media.checksums(plan));
            }
            return jobId;
        });
    }

    public InstallPlan preview(long clusterId) {
        Cluster cluster = clusters.findById(clusterId)
                .orElseThrow(() -> ResourceNotFoundException.cluster(clusterId));
        List<Node> configuredNodes = InstallationNodes.normalize(nodes.findByClusterIdOrderById(clusterId));
        return assembler == null ? plans.create()
                : assembler.forNewCluster(snapshots.previewPayload(cluster, configuredNodes));
    }
}
