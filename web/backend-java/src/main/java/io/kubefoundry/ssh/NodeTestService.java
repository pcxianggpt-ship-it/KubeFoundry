package io.kubefoundry.ssh;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.credential.AesGcmCredentialCipher;
import io.kubefoundry.credential.EncryptedCredential;
import io.kubefoundry.job.EventService;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;

@Service
public class NodeTestService {

    private static final List<String> ACTIVE_STATUSES = List.of("pending", "running");

    private final ClusterRepository clusters;
    private final NodeRepository nodes;
    private final JobRepository jobs;
    private final JobService jobService;
    private final EventService events;
    private final ClusterKeyService clusterKeys;
    private final NodeTestRunner runner;
    private final ObjectProvider<AesGcmCredentialCipher> cipherProvider;
    private final ConcurrentMap<Long, Object> admissionLocks = new ConcurrentHashMap<>();

    public NodeTestService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobRepository jobs,
            JobService jobService,
            EventService events,
            ClusterKeyService clusterKeys,
            NodeTestRunner runner,
            ObjectProvider<AesGcmCredentialCipher> cipherProvider) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobs = jobs;
        this.jobService = jobService;
        this.events = events;
        this.clusterKeys = clusterKeys;
        this.runner = runner;
        this.cipherProvider = cipherProvider;
    }

    public long startClusterTest(long clusterId, boolean failedOnly) {
        ClusterKeyMaterial key = clusterKeys.getOrCreate(clusterId);
        synchronized (admissionLockFor(clusterId)) {
            Cluster cluster = requireCluster(clusterId);
            rejectActiveJob(clusterId);
            List<Node> selected = nodes.findByClusterIdOrderById(clusterId);
            if (failedOnly) {
                selected = selected.stream()
                        .filter(node -> "failed".equals(node.getNodeTestStatus()))
                        .toList();
            }
            validateNodes(selected, failedOnly);
            clusters.updateNodeTestStatus(clusterId, "running");
            try {
                return submit(clusterId, selected, key, cluster.getNodeConfigVersion());
            } catch (RuntimeException exception) {
                clusters.updateNodeTestStatus(clusterId, "failed");
                throw exception;
            }
        }
    }

    public long startNodeTest(long nodeId) {
        Node initial = nodes.findById(nodeId)
                .orElseThrow(() -> new IllegalArgumentException("节点不存在: " + nodeId));
        long clusterId = initial.getCluster().getId();
        ClusterKeyMaterial key = clusterKeys.getOrCreate(clusterId);
        synchronized (admissionLockFor(clusterId)) {
            Node node = nodes.findById(nodeId)
                    .orElseThrow(() -> new IllegalArgumentException("节点不存在: " + nodeId));
            Cluster cluster = requireCluster(clusterId);
            rejectActiveJob(clusterId);
            validateNodes(List.of(node), false);
            clusters.updateNodeTestStatus(clusterId, "running");
            try {
                return submit(clusterId, List.of(node), key, cluster.getNodeConfigVersion());
            } catch (RuntimeException exception) {
                clusters.updateNodeTestStatus(clusterId, "failed");
                throw exception;
            }
        }
    }

    private long submit(
            long clusterId, List<Node> selected, ClusterKeyMaterial key, long expectedConfigVersion) {
        List<JobService.NodeOperation> operations = selected.stream()
                .map(node -> new JobService.NodeOperation(node.getId(), jobId ->
                        testOne(jobId, node.getId(), key, expectedConfigVersion)))
                .toList();
        return jobService.submit(new JobService.JobDefinition(clusterId, "node_test", List.of(
                new JobService.StepDefinition("测试 SSH 连通性并识别系统", 1, operations))));
    }

    private void testOne(
            long jobId, long nodeId, ClusterKeyMaterial key, long expectedConfigVersion)
            throws Exception {
        Node node = nodes.findById(nodeId).orElseThrow();
        EncryptedCredential encrypted = node.encryptedPassword();
        char[] password = null;
        try {
            password = cipherProvider.getObject().decrypt(encrypted);
            NodeProbe probe = runner.test(node, password, key,
                    phase -> updatePhase(jobId, nodeId, expectedConfigVersion, phase),
                    expectedConfigVersion);
            if (nodes.completeTestIfConfigurationUnchanged(
                    nodeId, expectedConfigVersion,
                    probe.osType(), probe.osVersion(), probe.architecture()) != 1) {
                throw new NodeConfigurationChangedException(nodeId);
            }
            Node completed = nodes.findById(nodeId).orElseThrow();
            publishNodeStatus(jobId, completed, "success");
            updateClusterAggregate(completed.getCluster().getId());
        } catch (NodeConfigurationChangedException exception) {
            throw exception;
        } catch (Exception exception) {
            String message = truncate(redact(exception.getMessage(), password), 1000);
            if (nodes.failTestIfConfigurationUnchanged(
                    nodeId, expectedConfigVersion, message) != 1) {
                throw new NodeConfigurationChangedException(nodeId);
            }
            Node failed = nodes.findById(nodeId).orElseThrow();
            publishNodeStatus(jobId, failed, "failed");
            updateClusterAggregate(failed.getCluster().getId());
            throw new IllegalStateException(message);
        } finally {
            if (password != null) Arrays.fill(password, '\0');
        }
    }

    private void updatePhase(
            long jobId, long nodeId, long expectedConfigVersion, String phase) {
        if (!List.of("password_connecting", "key_installing", "key_verifying").contains(phase)) {
            throw new IllegalArgumentException("未知节点测试阶段: " + phase);
        }
        if (nodes.updateTestPhaseIfConfigurationUnchanged(
                nodeId, expectedConfigVersion, phase) != 1) {
            throw new NodeConfigurationChangedException(nodeId);
        }
        Node node = nodes.findById(nodeId).orElseThrow();
        publishNodeStatus(jobId, node, phase);
    }

    private void publishNodeStatus(long jobId, Node node, String status) {
        events.publish(jobId, "node.status", Map.of(
                "node_id", node.getId(),
                "hostname", node.getHostname(),
                "status", status));
    }

    private void updateClusterAggregate(long clusterId) {
        clusters.refreshNodeTestAggregate(clusterId);
    }

    private Object admissionLockFor(long clusterId) {
        return admissionLocks.computeIfAbsent(clusterId, ignored -> new Object());
    }

    private void rejectActiveJob(long clusterId) {
        jobs.findFirstByClusterIdAndTypeAndStatusInOrderByIdDesc(
                clusterId, "node_test", ACTIVE_STATUSES).ifPresent(job -> {
                    throw new ActiveNodeTestException(job.getId());
                });
    }

    private static void validateNodes(List<Node> selected, boolean failedOnly) {
        if (selected.isEmpty()) {
            throw new IllegalArgumentException(failedOnly ? "没有需要重试的失败节点" : "集群没有可测试节点");
        }
        List<String> problems = new ArrayList<>();
        for (Node node : selected) {
            if (node.isDraft()) problems.add(node.getHostname() + " 是草稿节点");
            if (node.getIp() == null || node.getIp().isBlank()) problems.add(node.getHostname() + " 缺少 IP");
            if (!node.hasPassword()) problems.add(node.getHostname() + " 缺少登录密码");
        }
        if (!problems.isEmpty()) throw new IllegalArgumentException(String.join("；", problems));
    }

    private Cluster requireCluster(long clusterId) {
        return clusters.findById(clusterId)
                .orElseThrow(() -> new IllegalArgumentException("集群不存在: " + clusterId));
    }

    static String redact(String value, char[] secret) {
        if (value == null || value.isBlank()) return "节点测试失败";
        if (secret == null || secret.length == 0) return value;
        StringBuilder result = new StringBuilder(value.length());
        int index = 0;
        while (index < value.length()) {
            if (matches(value, index, secret)) {
                result.append("***");
                index += secret.length;
            } else {
                result.append(value.charAt(index++));
            }
        }
        return result.toString();
    }

    private static String truncate(String value, int maximumLength) {
        return value.length() <= maximumLength ? value : value.substring(0, maximumLength);
    }

    private static boolean matches(String value, int offset, char[] secret) {
        if (offset + secret.length > value.length()) return false;
        for (int index = 0; index < secret.length; index++) {
            if (value.charAt(offset + index) != secret[index]) return false;
        }
        return true;
    }

    public static class ActiveNodeTestException extends IllegalStateException {
        private final long jobId;

        public ActiveNodeTestException(long jobId) {
            super("集群已有正在运行的节点测试任务");
            this.jobId = jobId;
        }

        public long jobId() { return jobId; }
    }
}
