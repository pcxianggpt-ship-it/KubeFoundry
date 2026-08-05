package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponentStateRepository;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.ClusterService.ResourceNotFoundException;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.JobService;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;

/** Submits the destructive reset as an auditable remote job, never as an HTTP-side action. */
@Service
public class ClusterResetService {
    private final ClusterRepository clusters;
    private final NodeRepository nodes;
    private final JobService jobs;
    private final RemoteStepRunner runner;
    private final InstallerAdmission admission;
    private final InstallationSnapshotService snapshots;
    private final ResetPlanFactory plans;
    private final ClusterComponentStateRepository componentStates;

    public ClusterResetService(ClusterRepository clusters, NodeRepository nodes, JobService jobs,
            RemoteStepRunner runner, InstallerAdmission admission,
            InstallationSnapshotService snapshots, ResetPlanFactory plans,
            ClusterComponentStateRepository componentStates) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobs = jobs;
        this.runner = runner;
        this.admission = admission;
        this.snapshots = snapshots;
        this.plans = plans;
        this.componentStates = componentStates;
    }

    public long start(long clusterId, boolean acknowledged, String confirmationPhrase) {
        Cluster cluster = clusters.findById(clusterId)
                .orElseThrow(() -> ResourceNotFoundException.cluster(clusterId));
        requireConfirmation(cluster, acknowledged, confirmationPhrase);
        if (!cluster.isInstallationLocked()) {
            throw new IllegalArgumentException("仅已成功安装并锁定的集群可以重置");
        }
        InstallationSnapshotPayload snapshot = snapshots.latestInstallPayload(clusterId);
        List<SnapshotTarget> targets = resolveSnapshotTargets(clusterId, snapshot);
        Set<String> componentGroups = ResetPlanFactory.componentGroups(snapshot,
                componentStates.findByClusterIdOrderByComponentKey(clusterId));
        RuntimeSettings runtimeSettings = plans.runtimeSettings(snapshot, componentGroups);
        InstallStep componentCleanup = componentGroups.isEmpty() ? null : plans.componentCleanupStep();
        InstallStep cleanup = plans.nodeCleanupStep();
        InstallStep verification = plans.nodeVerificationStep();
        return admission.submit(clusterId, () -> {
            Cluster admittedCluster = clusters.findById(clusterId)
                    .orElseThrow(() -> ResourceNotFoundException.cluster(clusterId));
            long jobId = jobs.submit(new JobService.JobDefinition(clusterId, "reset",
                    stepDefinitions(cluster, targets, componentCleanup, cleanup, verification, runtimeSettings)));
            admittedCluster.markResetStarted();
            clusters.save(admittedCluster);
            return jobId;
        });
    }

    private static void requireConfirmation(
            Cluster cluster, boolean acknowledged, String confirmationPhrase) {
        String expected = "RESET " + cluster.getName();
        if (!acknowledged || !expected.equals(confirmationPhrase)) {
            throw new ResetConfirmationMismatchException(
                    "重置集群是破坏性操作，请勾选确认并输入 " + expected);
        }
    }

    private List<JobService.StepDefinition> stepDefinitions(
            Cluster cluster,
            List<SnapshotTarget> targets,
            InstallStep componentCleanup,
            InstallStep cleanup,
            InstallStep verification,
            RuntimeSettings runtimeSettings) {
        List<Node> allTargets = targets.stream().map(SnapshotTarget::node).toList();
        List<SnapshotTarget> controls = targets.stream()
                .filter(target -> target.roles().contains("control_plane")).toList();
        SnapshotTarget primary = controls.stream()
                .min(java.util.Comparator.comparing(target -> target.node().getId()))
                .orElse(null);
        List<List<SnapshotTarget>> groups = List.of(
                targets.stream().filter(target -> target.roles().contains("worker")).toList(),
                controls.stream().filter(target -> primary == null || target != primary).toList(),
                primary == null ? List.of() : List.of(primary),
                targets.stream().filter(target -> target.roles().contains("registry")
                        && !target.roles().contains("worker")
                        && !target.roles().contains("control_plane")).toList());
        List<String> names = List.of("重置工作节点", "重置其他控制节点", "重置主控制节点", "清理 Registry 节点");
        List<JobService.StepDefinition> definitions = new java.util.ArrayList<>();
        if (componentCleanup != null) {
            if (primary == null) {
                throw new IllegalArgumentException("安装快照没有主控制节点，拒绝清理 Kubemate 组件");
            }
            definitions.add(new JobService.StepDefinition("清理 Kubemate 受管组件", 1, 1, true,
                    List.of(JobService.NodeOperation.withOutcome(primary.node().getId(), jobId -> runner.run(
                            jobId, cluster, allTargets, primary.node(), componentCleanup, runtimeSettings)))));
        }
        for (int index = 0; index < groups.size(); index++) {
            List<JobService.NodeOperation> operations = groups.get(index).stream().map(target ->
                    JobService.NodeOperation.withOutcome(target.node().getId(), jobId -> runner.run(
                            jobId, cluster, allTargets, target.node(), cleanup, runtimeSettings))).toList();
            if (!operations.isEmpty()) {
                definitions.add(new JobService.StepDefinition(
                        names.get(index), definitions.size() + 1, index == 0 ? 3 : 1, true, operations));
            }
        }
        if (definitions.isEmpty()) throw new IllegalArgumentException("安装快照没有可重置的服务器节点");
        List<JobService.NodeOperation> verifyOperations = targets.stream().map(target ->
                JobService.NodeOperation.withOutcome(target.node().getId(), jobId -> runner.run(
                        jobId, cluster, allTargets, target.node(), verification, runtimeSettings))).toList();
        definitions.add(new JobService.StepDefinition(
                "验证重置结果", definitions.size() + 1, 3, true, verifyOperations));
        return List.copyOf(definitions);
    }

    private List<SnapshotTarget> resolveSnapshotTargets(long clusterId, InstallationSnapshotPayload snapshot) {
        if (snapshot.clusterId() != clusterId) {
            throw new IllegalArgumentException("安装快照所属集群不匹配");
        }
        Map<Long, Node> current = new LinkedHashMap<>();
        for (Node node : nodes.findByClusterIdOrderById(clusterId)) current.put(node.getId(), node);
        List<SnapshotTarget> targets = snapshot.nodes().stream().map(target -> {
            Node node = current.get(target.id());
            if (node == null || !target.hostname().equals(node.getHostname())
                    || !target.ip().equals(node.getIp()) || !target.sshUser().equals(node.getSshUser())
                    || target.sshPort() != node.getSshPort()) {
                throw new IllegalArgumentException("安装快照目标节点已变化，拒绝执行远程重置: " + target.hostname());
            }
            return new SnapshotTarget(node, target.roles());
        }).toList();
        if (targets.isEmpty()) throw new IllegalArgumentException("安装快照没有可重置的服务器节点");
        Map<Long, SnapshotTarget> unique = new LinkedHashMap<>();
        targets.forEach(target -> unique.putIfAbsent(target.node().getId(), target));
        return List.copyOf(unique.values());
    }

    private record SnapshotTarget(Node node, Set<String> roles) { }
}
