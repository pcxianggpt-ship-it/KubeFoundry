package io.kubefoundry.cluster;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.kubefoundry.credential.AesGcmCredentialCipher;
import io.kubefoundry.credential.EncryptedCredential;
import io.kubefoundry.job.JobRepository;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ClusterService {

    private static final Set<String> NODE_ROLES = Set.of("control_plane", "worker", "registry");

    private final ClusterRepository clusters;
    private final NodeRepository nodes;
    private final JobRepository jobs;
    private final ObjectProvider<AesGcmCredentialCipher> credentialCipherProvider;

    public ClusterService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobRepository jobs,
            ObjectProvider<AesGcmCredentialCipher> credentialCipherProvider) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobs = jobs;
        this.credentialCipherProvider = credentialCipherProvider;
    }

    @Transactional(readOnly = true)
    public List<ClusterResponse> listClusters() {
        return clusters.findAll().stream().map(this::response).toList();
    }

    @Transactional(readOnly = true)
    public ClusterResponse getCluster(long id) {
        return response(requireCluster(id));
    }

    @Transactional
    public UpsertClusterResult upsertCluster(ClusterRequest request) {
        String name = required(request.name(), "集群名称不能为空");
        Cluster cluster = clusters.findByName(name).orElse(null);
        boolean created = cluster == null;
        if (created) cluster = new Cluster(name);
        cluster.update(name, request.description(), request.k8sVersion(), request.podSubnet(),
                request.serviceSubnet(), request.registryHostname(), request.registryIp(),
                request.registryPort(), request.status());
        return new UpsertClusterResult(response(clusters.save(cluster)), created);
    }

    @Transactional
    public ClusterResponse updateCluster(long id, ClusterRequest request) {
        Cluster cluster = requireCluster(id);
        requireConfigurationMutable(cluster);
        String name = request.name() == null ? null : required(request.name(), "集群名称不能为空");
        cluster.update(name, request.description(), request.k8sVersion(), request.podSubnet(),
                request.serviceSubnet(), request.registryHostname(), request.registryIp(),
                request.registryPort(), request.status());
        return response(clusters.save(cluster));
    }

    @Transactional
    public void deleteCluster(long id) {
        if (!clusters.existsById(id)) throw ResourceNotFoundException.cluster(id);
        clusters.deleteById(id);
    }

    @Transactional(readOnly = true)
    public List<NodeResponse> listNodes(long clusterId) {
        requireCluster(clusterId);
        return nodes.findByClusterIdOrderById(clusterId).stream().map(NodeResponse::from).toList();
    }

    @Transactional
    public NodeResponse createNode(long clusterId, NodeRequest request) {
        Cluster cluster = requireCluster(clusterId);
        requireConfigurationMutable(cluster);
        validateNode(request, true);
        Node node = new Node(cluster);
        node.update(request.hostname(), request.ip(), valueOrEmpty(request.ipv6()), request.role(),
                request.sshUser(), request.sshPort());
        replacePasswordIfPresent(node, request.password());
        node.markDraft(false);
        node.markPendingAndClearDiscovery();
        NodeResponse response = NodeResponse.from(nodes.save(node));
        clusters.markNodeConfigurationChanged(clusterId);
        return response;
    }

    @Transactional
    public NodeResponse updateNode(long nodeId, NodeRequest request) {
        Node node = requireNode(nodeId);
        requireConfigurationMutable(node.getCluster());
        boolean hostIdentityChanged = changed(request.ip(), node.getIp())
                || (request.sshPort() != null && request.sshPort() != node.getSshPort());
        boolean criticalChanged = changed(request.hostname(), node.getHostname())
                || changed(request.ip(), node.getIp())
                || changed(request.ipv6(), node.getIpv6())
                || changed(request.role(), node.getRole())
                || changed(request.sshUser(), node.getSshUser())
                || (request.sshPort() != null && request.sshPort() != node.getSshPort())
                || (request.password() != null && !request.password().isBlank());
        NodeRequest merged = merge(node, request);
        validateNode(merged, false);
        node.update(request.hostname(), request.ip(), request.ipv6(), request.role(),
                request.sshUser(), request.sshPort());
        replacePasswordIfPresent(node, request.password());
        if (node.isDraft()) node.markDraft(false);
        if (criticalChanged) {
            node.markTestStale(hostIdentityChanged);
            clusters.markNodeConfigurationChanged(node.getCluster().getId());
        }
        return NodeResponse.from(nodes.save(node));
    }

    @Transactional
    public void deleteNode(long nodeId) {
        Node node = requireNode(nodeId);
        requireConfigurationMutable(node.getCluster());
        long clusterId = node.getCluster().getId();
        nodes.delete(node);
        clusters.markNodeConfigurationChanged(clusterId);
    }

    @Transactional
    public List<NodeResponse> copyNodes(long clusterId, List<Long> nodeIds) {
        Cluster cluster = requireCluster(clusterId);
        requireConfigurationMutable(cluster);
        if (nodeIds == null || nodeIds.isEmpty()) {
            throw new IllegalArgumentException("请选择需要复制的节点");
        }
        if (nodeIds.size() != Set.copyOf(nodeIds).size()) {
            throw new IllegalArgumentException("复制节点列表不能包含重复项");
        }
        List<NodeResponse> copied = nodeIds.stream().map(id -> {
            Node source = requireNode(id);
            if (!source.getCluster().getId().equals(clusterId)) {
                throw new IllegalArgumentException("节点不属于当前集群");
            }
            Node target = new Node(cluster);
            target.update("", "", "", source.getRole(), source.getSshUser(), source.getSshPort());
            target.copyCredentialFrom(source);
            target.markDraft(true);
            target.markPendingAndClearDiscovery();
            return NodeResponse.from(nodes.save(target));
        }).toList();
        clusters.markNodeConfigurationChanged(clusterId);
        return copied;
    }

    @Transactional
    public ClusterResponse resetCluster(long id) {
        Cluster cluster = requireCluster(id);
        if (!isConfigurationLocked(cluster)) {
            throw new IllegalArgumentException("集群尚未开始安装，无需重置");
        }
        if (jobs.findFirstByClusterIdAndTypeInAndStatusInOrderByIdDesc(
                id, List.of("install", "precheck"), List.of("pending", "running")).isPresent()) {
            throw new ClusterConfigurationLockedException("当前安装或预检查任务仍在执行，暂不能重置集群");
        }
        for (Node node : nodes.findByClusterIdOrderById(id)) {
            node.markTestStale(false);
            nodes.save(node);
        }
        cluster.resetInstallation();
        return response(clusters.save(cluster));
    }

    private void replacePasswordIfPresent(Node node, String password) {
        if (password == null || password.isBlank()) return;
        char[] chars = password.toCharArray();
        try {
            EncryptedCredential credential = credentialCipherProvider.getObject().encrypt(chars);
            node.replacePassword(credential);
        } finally {
            Arrays.fill(chars, '\0');
        }
    }

    private void validateNode(NodeRequest request, boolean passwordRequired) {
        required(request.hostname(), "节点主机名不能为空");
        String ip = required(request.ip(), "节点 IPv4 不能为空");
        if (!isIpv4(ip)) {
            throw new IllegalArgumentException("节点 IPv4 格式无效");
        }
        if (!NODE_ROLES.contains(request.role())) {
            throw new IllegalArgumentException("节点角色无效");
        }
        required(request.sshUser(), "SSH 用户不能为空");
        if (request.sshPort() == null || request.sshPort() < 1 || request.sshPort() > 65535) {
            throw new IllegalArgumentException("SSH 端口必须在 1 到 65535 之间");
        }
        if (passwordRequired && (request.password() == null || request.password().isBlank())) {
            throw new IllegalArgumentException("节点登录密码不能为空");
        }
    }

    private Cluster requireCluster(long id) {
        return clusters.findById(id).orElseThrow(() -> ResourceNotFoundException.cluster(id));
    }

    private Node requireNode(long id) {
        return nodes.findById(id).orElseThrow(() -> ResourceNotFoundException.node(id));
    }

    private ClusterResponse response(Cluster cluster) {
        return ClusterResponse.from(cluster, isConfigurationLocked(cluster));
    }

    private void requireConfigurationMutable(Cluster cluster) {
        if (isConfigurationLocked(cluster)) {
            throw new ClusterConfigurationLockedException("安装任务已开始，重置集群后才能修改集群信息、服务器节点或安装配置");
        }
    }

    private boolean isConfigurationLocked(Cluster cluster) {
        return cluster.isInstallationLocked();
    }

    private static String required(String value, String message) {
        if (value == null || value.trim().isEmpty()) throw new IllegalArgumentException(message);
        return value.trim();
    }

    private static String valueOrEmpty(String value) { return value == null ? "" : value; }
    private static boolean isIpv4(String value) {
        String[] parts = value.split("\\.", -1);
        if (parts.length != 4) return false;
        for (String part : parts) {
            if (part.isEmpty() || part.length() > 3 || !part.chars().allMatch(Character::isDigit)) {
                return false;
            }
            int octet = Integer.parseInt(part);
            if (octet > 255) return false;
        }
        return true;
    }
    private static boolean changed(String incoming, String current) {
        return incoming != null && !incoming.trim().equals(current == null ? "" : current);
    }

    private static NodeRequest merge(Node node, NodeRequest request) {
        return new NodeRequest(
                request.hostname() == null ? node.getHostname() : request.hostname(),
                request.ip() == null ? node.getIp() : request.ip(),
                request.ipv6() == null ? node.getIpv6() : request.ipv6(),
                request.role() == null ? node.getRole() : request.role(),
                request.sshUser() == null ? node.getSshUser() : request.sshUser(),
                request.sshPort() == null ? node.getSshPort() : request.sshPort(),
                request.password());
    }

    public record ClusterRequest(
            String name,
            String description,
            @JsonProperty("k8s_version") String k8sVersion,
            @JsonProperty("pod_subnet") String podSubnet,
            @JsonProperty("service_subnet") String serviceSubnet,
            @JsonProperty("registry_hostname") String registryHostname,
            @JsonProperty("registry_ip") String registryIp,
            @JsonProperty("registry_port") Integer registryPort,
            String status) {}

    public record ClusterResponse(
            long id,
            String name,
            String description,
            @JsonProperty("k8s_version") String k8sVersion,
            @JsonProperty("pod_subnet") String podSubnet,
            @JsonProperty("service_subnet") String serviceSubnet,
            @JsonProperty("registry_hostname") String registryHostname,
            @JsonProperty("registry_ip") String registryIp,
            @JsonProperty("registry_port") int registryPort,
            String status,
            @JsonProperty("node_config_version") long nodeConfigVersion,
            @JsonProperty("node_test_status") String nodeTestStatus,
            @JsonProperty("configuration_locked") boolean configurationLocked) {
        static ClusterResponse from(Cluster value, boolean configurationLocked) {
            return new ClusterResponse(value.getId(), value.getName(), value.getDescription(),
                    value.getKubernetesVersion(), value.getPodSubnet(), value.getServiceSubnet(),
                    value.getRegistryHostname(), value.getRegistryIp(), value.getRegistryPort(),
                    value.getStatus(), value.getNodeConfigVersion(), value.getNodeTestStatus(),
                    configurationLocked);
        }
    }

    public record NodeRequest(
            String hostname,
            String ip,
            String ipv6,
            String role,
            @JsonProperty("ssh_user") String sshUser,
            @JsonProperty("ssh_port") Integer sshPort,
            String password) {}

    public record NodeResponse(
            long id,
            @JsonProperty("cluster_id") long clusterId,
            String hostname,
            String ip,
            String ipv6,
            String role,
            @JsonProperty("ssh_user") String sshUser,
            @JsonProperty("ssh_port") int sshPort,
            @JsonProperty("has_password") boolean hasPassword,
            @JsonProperty("is_draft") boolean draft,
            @JsonProperty("node_test_status") String nodeTestStatus,
            @JsonProperty("os_type") String osType,
            @JsonProperty("os_version") String osVersion,
            @JsonProperty("arch") String architecture,
            @JsonProperty("node_test_message") String nodeTestMessage,
            String status) {
        static NodeResponse from(Node value) {
            return new NodeResponse(value.getId(), value.getCluster().getId(), value.getHostname(),
                    value.getIp(), value.getIpv6(), value.getRole(), value.getSshUser(),
                    value.getSshPort(), value.hasPassword(), value.isDraft(),
                    value.getNodeTestStatus(), value.getOsType(), value.getOsVersion(),
                    value.getArchitecture(), value.getNodeTestMessage(), value.getStatus());
        }
    }

    public record UpsertClusterResult(ClusterResponse cluster, boolean created) {}

    public static final class ClusterConfigurationLockedException extends RuntimeException {
        public ClusterConfigurationLockedException(String message) { super(message); }
    }

    public static final class ResourceNotFoundException extends RuntimeException {
        private final String code;

        private ResourceNotFoundException(String code, String message) {
            super(message);
            this.code = code;
        }

        public String code() { return code; }
        public static ResourceNotFoundException cluster(long id) {
            return new ResourceNotFoundException("CLUSTER_NOT_FOUND", "集群不存在: " + id);
        }
        public static ResourceNotFoundException node(long id) {
            return new ResourceNotFoundException("NODE_NOT_FOUND", "节点不存在: " + id);
        }
    }
}
