package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import java.time.Duration;
import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class PrecheckService {

    static final String CHECK_COMMAND = """
            set -o pipefail
            test "$(id -u)" = 0
            test "$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc)" -ge 2
            test "$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)" -ge 2048
            command -v bash >/dev/null
            command -v systemctl >/dev/null
            """;

    private final ClusterRepository clusters;
    private final NodeRepository nodes;
    private final JobRepository jobs;
    private final JobService jobService;
    private final RemoteStepRunner runner;

    public PrecheckService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobRepository jobs,
            JobService jobService,
            RemoteStepRunner runner) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobs = jobs;
        this.jobService = jobService;
        this.runner = runner;
    }

    public long start(long clusterId) {
        Cluster cluster = clusters.findById(clusterId)
                .orElseThrow(() -> new IllegalArgumentException("集群不存在: " + clusterId));
        List<Node> configuredNodes = nodes.findByClusterIdOrderById(clusterId);
        InstallationGate.requireSuccessfulNodeTests(cluster, configuredNodes);
        jobs.findFirstByClusterIdAndTypeAndStatusInOrderByIdDesc(
                clusterId, "precheck", List.of("pending", "running"))
                .ifPresent(job -> { throw new ActiveInstallerJobException("precheck", job.getId()); });
        List<JobService.NodeOperation> operations = configuredNodes.stream()
                .map(node -> JobService.NodeOperation.withOutcome(node.getId(), jobId ->
                        runner.runCommand(jobId, cluster, node, "web-precheck-node-env",
                                CHECK_COMMAND, Duration.ofSeconds(60))))
                .toList();
        JobService.StepDefinition step = new JobService.StepDefinition(
                "节点环境预检查", 1, 5, false, operations);
        return jobService.submit(new JobService.JobDefinition(
                clusterId, "precheck", List.of(step)));
    }
}
