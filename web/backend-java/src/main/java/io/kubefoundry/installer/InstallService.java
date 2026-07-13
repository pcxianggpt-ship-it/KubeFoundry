package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class InstallService {

    private final ClusterRepository clusters;
    private final NodeRepository nodes;
    private final JobRepository jobs;
    private final JobService jobService;
    private final InstallPlanFactory plans;
    private final RemoteStepRunner runner;

    public InstallService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobRepository jobs,
            JobService jobService,
            InstallPlanFactory plans,
            RemoteStepRunner runner) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobs = jobs;
        this.jobService = jobService;
        this.plans = plans;
        this.runner = runner;
    }

    public long start(long clusterId, List<String> selectedSteps) {
        Cluster cluster = clusters.findById(clusterId)
                .orElseThrow(() -> new IllegalArgumentException("集群不存在: " + clusterId));
        List<Node> configuredNodes = nodes.findByClusterIdOrderById(clusterId);
        InstallationGate.requireSuccessfulNodeTests(cluster, configuredNodes);
        rejectActiveJob(clusterId, "install");
        InstallPlan plan = plans.select(selectedSteps);
        List<JobService.StepDefinition> definitions = new ArrayList<>();
        for (int index = 0; index < plan.steps().size(); index++) {
            InstallStep step = plan.steps().get(index);
            List<Node> targets = plans.resolveTargets(step, configuredNodes);
            if (targets.isEmpty() && List.of("primary_control_plane", "registry")
                    .contains(step.targetScope())) {
                throw new IllegalArgumentException("安装步骤缺少目标节点: " + step.key());
            }
            List<JobService.NodeOperation> operations = targets.stream()
                    .map(node -> JobService.NodeOperation.withOutcome(node.getId(), jobId ->
                            runner.run(jobId, cluster, configuredNodes, node, step)))
                    .toList();
            definitions.add(new JobService.StepDefinition(
                    step.name(), index + 1, step.maxWorkers(), step.failFast(), operations));
        }
        return jobService.submit(new JobService.JobDefinition(clusterId, "install", definitions));
    }

    private void rejectActiveJob(long clusterId, String type) {
        jobs.findFirstByClusterIdAndTypeAndStatusInOrderByIdDesc(
                clusterId, type, List.of("pending", "running"))
                .ifPresent(job -> { throw new ActiveInstallerJobException(type, job.getId()); });
    }
}
