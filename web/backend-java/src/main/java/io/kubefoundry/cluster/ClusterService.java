package io.kubefoundry.cluster;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.kubefoundry.credential.AesGcmCredentialCipher;
import io.kubefoundry.credential.EncryptedCredential;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.installer.InstallerAdmission;
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
    private final InstallerAdmission admission;

    public ClusterService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobRepository jobs,
            ObjectProvider<AesGcmCredentialCipher> credentialCipherProvider,
            InstallerAdmission admission) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobs = jobs;
        this.credentialCipherProvider = credentialCipherProvider;
        this.admission = admission;
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
        cluster.update(name, request.description(), request.k8sVersion(), null, null, null, null,
                null, request.status());
        updateInstallationConfiguration(cluster, request);
        return new UpsertClusterResult(response(clusters.save(cluster)), created);
    }

    @Transactional
    public ClusterResponse updateCluster(long id, ClusterRequest request) {
        Cluster cluster = requireCluster(id);
        requireConfigurationMutable(cluster);
        String name = request.name() == null ? null : required(request.name(), "集群名称不能为空");
        cluster.update(name, request.description(), request.k8sVersion(), null, null, null, null,
                null, request.status());
        updateInstallationConfiguration(cluster, request);
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
        Cluster cluster = requireClusterForUpdate(clusterId);
        requireConfigurationMutable(cluster);
        NormalizedNode normalized = validateAndNormalizeNode(request, true);
        requireUniqueNodeIdentity(clusterId, null, normalized);
        Node node = new Node(cluster);
        node.update(normalized.hostname(), normalized.ip(), valueOrEmpty(request.ipv6()), null,
                normalized.sshUser(), normalized.sshPort());
        node.updateNormalizedIdentity(normalized.hostnameNormalized(), normalized.ipNormalized());
        node.replaceRoles(request.roles());
        replacePasswordIfPresent(node, request.password());
        node.markDraft(false);
        node.markPendingAndClearDiscovery();
        NodeResponse response = NodeResponse.from(nodes.saveAndFlush(node));
        clusters.markNodeConfigurationChanged(clusterId);
        return response;
    }

    @Transactional
    public NodeResponse updateNode(long nodeId, NodeRequest request) {
        Node node = requireNode(nodeId);
        Cluster cluster = requireClusterForUpdate(node.getCluster().getId());
        requireConfigurationMutable(cluster);
        NodeRequest merged = merge(node, request);
        NormalizedNode normalized = validateAndNormalizeNode(merged, false);
        requireUniqueNodeIdentity(node.getCluster().getId(), node.getId(), normalized);
        boolean hostIdentityChanged = !normalized.ipNormalized().equals(node.getIpNormalized())
                || (request.sshPort() != null && request.sshPort() != node.getSshPort());
        boolean criticalChanged = !normalized.hostnameNormalized().equals(node.getHostnameNormalized())
                || !normalized.ipNormalized().equals(node.getIpNormalized())
                || changed(request.ipv6(), node.getIpv6())
                || (request.roles() != null && !Set.copyOf(request.roles()).equals(node.getRoles()))
                || changed(request.sshUser(), node.getSshUser())
                || (request.sshPort() != null && request.sshPort() != node.getSshPort())
                || (request.password() != null && !request.password().isBlank());
        node.update(normalized.hostname(), normalized.ip(), request.ipv6(), null,
                normalized.sshUser(), normalized.sshPort());
        node.updateNormalizedIdentity(normalized.hostnameNormalized(), normalized.ipNormalized());
        node.replaceRoles(merged.roles());
        replacePasswordIfPresent(node, request.password());
        if (node.isDraft()) node.markDraft(false);
        if (criticalChanged) {
            node.markTestStale(hostIdentityChanged);
            clusters.markNodeConfigurationChanged(node.getCluster().getId());
        }
        return NodeResponse.from(nodes.saveAndFlush(node));
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
            target.update(source.getHostname(), source.getIp(), source.getIpv6(), null,
                    source.getSshUser(), source.getSshPort());
            target.replaceRoles(source.getRoles());
            target.copyCredentialFrom(source);
            target.markDraft(true);
            target.markPendingAndClearDiscovery();
            return NodeResponse.from(nodes.save(target));
        }).toList();
        clusters.markNodeConfigurationChanged(clusterId);
        return copied;
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

    private NormalizedNode validateAndNormalizeNode(NodeRequest request, boolean passwordRequired) {
        String hostname = required(request.hostname(), "节点主机名不能为空");
        String ip = required(request.ip(), "节点 IPv4 不能为空");
        String normalizedIp = normalizeIpv4(ip);
        if (normalizedIp == null) {
            throw new IllegalArgumentException("节点 IPv4 格式无效");
        }
        if (request.roles() == null || request.roles().isEmpty()
                || !NODE_ROLES.containsAll(Set.copyOf(request.roles()))) {
            throw new IllegalArgumentException("节点角色无效");
        }
        if (request.roles().contains("control_plane") && request.roles().contains("worker")) {
            throw new IllegalArgumentException("同一台服务器不能同时配置控制节点和工作节点角色");
        }
        String sshUser = required(request.sshUser(), "SSH 用户不能为空");
        if (request.sshPort() == null || request.sshPort() < 1 || request.sshPort() > 65535) {
            throw new IllegalArgumentException("SSH 端口必须在 1 到 65535 之间");
        }
        if (passwordRequired && (request.password() == null || request.password().isBlank())) {
            throw new IllegalArgumentException("节点登录密码不能为空");
        }
        return new NormalizedNode(hostname, normalizeHostname(hostname), normalizedIp, normalizedIp,
                sshUser, request.sshPort());
    }

    private void requireUniqueNodeIdentity(long clusterId, Long excludedNodeId, NormalizedNode identity) {
        Node hostnameConflict = nodes.findByClusterIdAndHostnameNormalized(
                clusterId, identity.hostnameNormalized()).filter(node -> !node.getId().equals(excludedNodeId))
                .orElse(null);
        Node ipConflict = nodes.findByClusterIdAndIpNormalized(
                clusterId, identity.ipNormalized()).filter(node -> !node.getId().equals(excludedNodeId))
                .orElse(null);
        if (hostnameConflict != null || ipConflict != null) {
            throw new NodeIdentityConflictException(hostnameConflict, ipConflict);
        }
    }

    private Cluster requireCluster(long id) {
        return clusters.findById(id).orElseThrow(() -> ResourceNotFoundException.cluster(id));
    }

    private Cluster requireClusterForUpdate(long id) {
        return clusters.findByIdForUpdate(id).orElseThrow(() -> ResourceNotFoundException.cluster(id));
    }

    private Node requireNode(long id) {
        return nodes.findById(id).orElseThrow(() -> ResourceNotFoundException.node(id));
    }

    private ClusterResponse response(Cluster cluster) {
        return ClusterResponse.from(cluster, isConfigurationLocked(cluster));
    }

    private static void updateInstallationConfiguration(Cluster cluster, ClusterRequest request) {
        String workDir = request.kubernetesWorkDir();
        if (workDir != null) {
            if (workDir.isBlank() || !workDir.trim().startsWith("/")) {
                throw new IllegalArgumentException("Kubernetes 工作目录必须是绝对路径");
            }
        }
        String registryType = request.imageRegistryType();
        if (registryType != null && !"REGISTRY".equals(registryType)) {
            throw new IllegalArgumentException("当前版本仅支持安装 Registry，Harbor 将在后续版本开放");
        }
        cluster.updateInstallationConfiguration(workDir, registryType);
    }

    private void requireConfigurationMutable(Cluster cluster) {
        admission.requireConfigurationWritable(cluster.getId(), isConfigurationLocked(cluster));
    }

    private boolean isConfigurationLocked(Cluster cluster) {
        return cluster.isInstallationLocked();
    }

    private static String required(String value, String message) {
        if (value == null || value.trim().isEmpty()) throw new IllegalArgumentException(message);
        return value.trim();
    }

    private static String valueOrEmpty(String value) { return value == null ? "" : value; }
    private static String normalizeHostname(String value) {
        String normalized = value.trim().toLowerCase(java.util.Locale.ROOT);
        return normalized.endsWith(".") ? normalized.substring(0, normalized.length() - 1) : normalized;
    }

    private static String normalizeIpv4(String value) {
        String[] parts = value.split("\\.", -1);
        if (parts.length != 4) return null;
        String[] normalized = new String[4];
        for (String part : parts) {
            if (part.isEmpty() || part.length() > 3 || !part.chars().allMatch(Character::isDigit)) {
                return null;
            }
            int octet = Integer.parseInt(part);
            if (octet > 255) return null;
        }
        for (int index = 0; index < parts.length; index++) {
            normalized[index] = Integer.toString(Integer.parseInt(parts[index]));
        }
        return String.join(".", normalized);
    }
    private static boolean changed(String incoming, String current) {
        return incoming != null && !incoming.trim().equals(current == null ? "" : current);
    }

    private static NodeRequest merge(Node node, NodeRequest request) {
        return new NodeRequest(
                request.hostname() == null ? node.getHostname() : request.hostname(),
                request.ip() == null ? node.getIp() : request.ip(),
                request.ipv6() == null ? node.getIpv6() : request.ipv6(),
                request.roles() == null ? node.getRoles().stream().toList() : request.roles(),
                request.sshUser() == null ? node.getSshUser() : request.sshUser(),
                request.sshPort() == null ? node.getSshPort() : request.sshPort(),
                request.password());
    }

    public record ClusterRequest(
            String name,
            String description,
            @JsonProperty("k8s_version") String k8sVersion,
            @JsonProperty("kubernetes_work_dir") String kubernetesWorkDir,
            @JsonProperty("image_registry_type") String imageRegistryType,
            String status) {}

    public record ClusterResponse(
            long id,
            String name,
            String description,
            @JsonProperty("k8s_version") String k8sVersion,
            @JsonProperty("kubernetes_work_dir") String kubernetesWorkDir,
            @JsonProperty("image_registry_type") String imageRegistryType,
            String status,
            @JsonProperty("node_config_version") long nodeConfigVersion,
            @JsonProperty("node_test_status") String nodeTestStatus,
            @JsonProperty("configuration_locked") boolean configurationLocked) {
        static ClusterResponse from(Cluster value, boolean configurationLocked) {
            return new ClusterResponse(value.getId(), value.getName(), value.getDescription(),
                    value.getKubernetesVersion(), value.getKubernetesWorkDir(), value.getImageRegistryType(),
                    value.getStatus(), value.getNodeConfigVersion(), value.getNodeTestStatus(),
                    configurationLocked);
        }
    }

    public record NodeRequest(
            String hostname,
            String ip,
            String ipv6,
            List<String> roles,
            @JsonProperty("ssh_user") String sshUser,
            @JsonProperty("ssh_port") Integer sshPort,
            String password) {}

    private record NormalizedNode(
            String hostname,
            String hostnameNormalized,
            String ip,
            String ipNormalized,
            String sshUser,
            int sshPort) {}

    public record NodeResponse(
            long id,
            @JsonProperty("cluster_id") long clusterId,
            String hostname,
            String ip,
            String ipv6,
            List<String> roles,
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
                    value.getIp(), value.getIpv6(), value.getRoles().stream().sorted().toList(), value.getSshUser(),
                    value.getSshPort(), value.hasPassword(), value.isDraft(),
                    value.getNodeTestStatus(), value.getOsType(), value.getOsVersion(),
                    value.getArchitecture(), value.getNodeTestMessage(), value.getStatus());
        }
    }

    public record UpsertClusterResult(ClusterResponse cluster, boolean created) {}

    public static final class ClusterConfigurationLockedException extends RuntimeException {
        public ClusterConfigurationLockedException(String message) { super(message); }
    }

    public static final class NodeIdentityConflictException extends RuntimeException {
        private final Node hostnameConflict;
        private final Node ipConflict;

        NodeIdentityConflictException(Node hostnameConflict, Node ipConflict) {
            super(message(hostnameConflict, ipConflict));
            this.hostnameConflict = hostnameConflict;
            this.ipConflict = ipConflict;
        }

        public Node hostnameConflict() { return hostnameConflict; }
        public Node ipConflict() { return ipConflict; }
        public String code() {
            if (hostnameConflict != null && ipConflict != null) return "NODE_IDENTITY_DUPLICATE";
            return hostnameConflict != null ? "NODE_HOSTNAME_DUPLICATE" : "NODE_IP_DUPLICATE";
        }

        private static String message(Node hostnameConflict, Node ipConflict) {
            if (hostnameConflict != null && ipConflict != null) return "主机名和 IP 地址已被当前集群的其他节点使用";
            return hostnameConflict != null ? "主机名已被当前集群的其他节点使用" : "IP 地址已被当前集群的其他节点使用";
        }
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
