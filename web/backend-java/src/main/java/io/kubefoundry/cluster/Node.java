package io.kubefoundry.cluster;

import io.kubefoundry.credential.EncryptedCredential;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Lob;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.Set;

@Entity
@Table(name = "nodes")
public class Node {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "cluster_id", nullable = false)
    private Cluster cluster;

    @Column(name = "name", length = 128)
    private String hostname = "";

    @Column(name = "host", length = 255)
    private String ip = "";

    @Column(name = "hostname_normalized", length = 128)
    private String hostnameNormalized;

    @Column(name = "ip_normalized", length = 15)
    private String ipNormalized;

    @Column(nullable = false, length = 128)
    private String ipv6 = "";

    @Column(name = "node_role", nullable = false, length = 32)
    private String role;

    @OneToMany(mappedBy = "node", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.EAGER)
    private Set<NodeRole> roleAssignments = new LinkedHashSet<>();

    @Column(name = "username", nullable = false, length = 128)
    private String sshUser;

    @Column(name = "port", nullable = false)
    private int sshPort;

    @Column(name = "password_ciphertext")
    @Lob
    private String passwordCiphertext;

    @Column(name = "password_iv", length = 64)
    private String passwordIv;

    @Column(name = "password_version")
    private Integer passwordVersion;

    @Column(name = "is_draft", nullable = false)
    private boolean draft;

    @Column(name = "node_test_status", nullable = false, length = 32)
    private String nodeTestStatus = "pending";

    @Column(name = "host_fingerprint", length = 256)
    private String hostFingerprint;

    @Column(name = "os_type", length = 128)
    private String osType;

    @Column(name = "os_version", length = 128)
    private String osVersion;

    @Column(name = "architecture", length = 64)
    private String architecture;

    @Column(name = "node_test_message", length = 1024)
    private String nodeTestMessage;

    @Column(nullable = false, length = 32)
    private String status = "pending";

    protected Node() {
    }

    public Node(Cluster cluster) {
        this.cluster = cluster;
    }

    public Long getId() { return id; }
    public Cluster getCluster() { return cluster; }
    public String getHostname() { return hostname; }
    public String getIp() { return ip; }
    public String getHostnameNormalized() { return hostnameNormalized; }
    public String getIpNormalized() { return ipNormalized; }
    public String getIpv6() { return ipv6; }
    public String getRole() { return role; }
    public Set<String> getRoles() {
        return roleAssignments.stream().map(NodeRole::getRole)
                .collect(java.util.stream.Collectors.toUnmodifiableSet());
    }
    public boolean hasRole(String expectedRole) {
        return expectedRole != null && getRoles().contains(expectedRole);
    }
    public String getSshUser() { return sshUser; }
    public int getSshPort() { return sshPort; }
    public boolean isDraft() { return draft; }
    public String getNodeTestStatus() { return nodeTestStatus; }
    public String getHostFingerprint() { return hostFingerprint; }
    public String getOsType() { return osType; }
    public String getOsVersion() { return osVersion; }
    public String getArchitecture() { return architecture; }
    public String getNodeTestMessage() { return nodeTestMessage; }
    public String getStatus() { return status; }
    public boolean hasPassword() { return passwordCiphertext != null && !passwordCiphertext.isBlank(); }

    public EncryptedCredential encryptedPassword() {
        return hasPassword() && passwordIv != null && passwordVersion != null
                ? new EncryptedCredential(passwordCiphertext, passwordIv, passwordVersion)
                : null;
    }

    public void update(
            String hostname, String ip, String ipv6, String role, String sshUser, Integer sshPort) {
        if (hostname != null) this.hostname = hostname.trim();
        if (ip != null) this.ip = ip.trim();
        if (ipv6 != null) this.ipv6 = ipv6.trim();
        if (role != null) this.role = role;
        if (sshUser != null) this.sshUser = sshUser.trim();
        if (sshPort != null) this.sshPort = sshPort;
    }

    public void updateNormalizedIdentity(String normalizedHostname, String normalizedIp) {
        hostnameNormalized = normalizedHostname;
        ipNormalized = normalizedIp;
    }

    public void replaceRoles(Collection<String> values) {
        Set<String> desired = values == null ? Set.of() : values.stream()
                .filter(value -> value != null && !value.isBlank()).map(String::trim)
                .collect(java.util.stream.Collectors.toSet());
        roleAssignments.removeIf(assignment -> !desired.contains(assignment.getRole()));
        desired.stream().filter(value -> roleAssignments.stream()
                .noneMatch(existing -> value.equals(existing.getRole())))
                .forEach(value -> roleAssignments.add(new NodeRole(this, value)));
        // node_role remains only as a database compatibility column during the v0.2.1 migration.
        role = roleAssignments.stream().map(NodeRole::getRole).sorted().findFirst().orElse(null);
    }

    public void replacePassword(EncryptedCredential credential) {
        passwordCiphertext = credential.ciphertext();
        passwordIv = credential.iv();
        passwordVersion = credential.version();
    }

    public void markDraft(boolean value) {
        draft = value;
        if (value) updateNormalizedIdentity(null, null);
    }

    public void markTestStale(boolean resetHostFingerprint) {
        nodeTestStatus = "stale";
        if (resetHostFingerprint) hostFingerprint = null;
        osType = null;
        osVersion = null;
        architecture = null;
        nodeTestMessage = null;
    }

    public void markPendingAndClearDiscovery() {
        nodeTestStatus = "pending";
        hostFingerprint = null;
        osType = null;
        osVersion = null;
        architecture = null;
        nodeTestMessage = null;
    }

    public void recordHostFingerprint(String fingerprint) {
        if (fingerprint == null || fingerprint.isBlank()) {
            throw new IllegalArgumentException("主机指纹不能为空");
        }
        hostFingerprint = fingerprint;
    }

    public void markNodeTestPhase(String phase) {
        nodeTestStatus = phase;
        nodeTestMessage = null;
    }

    public void completeNodeTest(String detectedOsType, String detectedOsVersion, String detectedArchitecture) {
        nodeTestStatus = "success";
        nodeTestMessage = "测试成功";
        osType = detectedOsType;
        osVersion = detectedOsVersion;
        architecture = detectedArchitecture;
    }

    public void failNodeTest(String message) {
        nodeTestStatus = "failed";
        nodeTestMessage = message;
        osType = null;
        osVersion = null;
        architecture = null;
    }

    public void copyCredentialFrom(Node source) {
        passwordCiphertext = source.passwordCiphertext;
        passwordIv = source.passwordIv;
        passwordVersion = source.passwordVersion;
    }
}
