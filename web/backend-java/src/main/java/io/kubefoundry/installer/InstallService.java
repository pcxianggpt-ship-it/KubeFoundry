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
    private final RemoteStepRunner runner;
    private final ClusterSettingsService settings;
    private final InstallerAdmission admission;

    @Autowired
    public InstallService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobService jobService,
            InstallPlanFactory plans,
            RemoteStepRunner runner,
            ClusterSettingsService settings,
            InstallerAdmission admission) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobService = jobService;
        this.plans = plans;
        this.runner = runner;
        this.settings = settings;
        this.admission = admission;
    }

    public InstallService(
            ClusterRepository clusters,
            NodeRepository nodes,
            io.kubefoundry.job.JobRepository jobs,
            JobService jobService,
            InstallPlanFactory plans,
            RemoteStepRunner runner) {
        this(clusters, nodes, jobService, plans, runner, null, new InstallerAdmission(jobs));
    }

    public long start(long clusterId, List<String> selectedSteps) {
        Cluster cluster = clusters.findById(clusterId)
                .orElseThrow(() -> ResourceNotFoundException.cluster(clusterId));
        List<Node> configuredNodes = nodes.findByClusterIdOrderById(clusterId);
        InstallationGate.requireSuccessfulNodeTests(cluster, configuredNodes);
        InstallPlan plan = plans.select(selectedSteps);
        List<JobService.StepDefinition> definitions = new ArrayList<>();
        for (int index = 0; index < plan.steps().size(); index++) {
            InstallStep step = plan.steps().get(index);
            List<Node> targets = plans.resolveTargets(step, cluster, configuredNodes);
            if (targets.isEmpty() && List.of("primary_control_plane", "registry")
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
                    step.name(), index + 1, step.maxWorkers(), step.failFast(), operations));
        }
        return admission.submit(clusterId, () ->
                jobService.submit(new JobService.JobDefinition(clusterId, "install", definitions)));
    }
}
