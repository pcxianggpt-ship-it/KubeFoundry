package io.kubefoundry.cluster;

import io.kubefoundry.credential.EncryptedCredential;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Lob;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

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

    @Column(nullable = false, length = 128)
    private String ipv6 = "";

    @Column(name = "node_role", nullable = false, length = 32)
    private String role;

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
    public String getIpv6() { return ipv6; }
    public String getRole() { return role; }
    public String getSshUser() { return sshUser; }
    public int getSshPort() { return sshPort; }
    public boolean isDraft() { return draft; }
    public String getNodeTestStatus() { return nodeTestStatus; }
    public String getStatus() { return status; }
    public boolean hasPassword() { return passwordCiphertext != null && !passwordCiphertext.isBlank(); }

    public void update(
            String hostname, String ip, String ipv6, String role, String sshUser, Integer sshPort) {
        if (hostname != null) this.hostname = hostname.trim();
        if (ip != null) this.ip = ip.trim();
        if (ipv6 != null) this.ipv6 = ipv6.trim();
        if (role != null) this.role = role;
        if (sshUser != null) this.sshUser = sshUser.trim();
        if (sshPort != null) this.sshPort = sshPort;
    }

    public void replacePassword(EncryptedCredential credential) {
        passwordCiphertext = credential.ciphertext();
        passwordIv = credential.iv();
        passwordVersion = credential.version();
    }

    public void markDraft(boolean value) { draft = value; }

    public void markTestStale() {
        nodeTestStatus = "stale";
        hostFingerprint = null;
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

    public void copyCredentialFrom(Node source) {
        passwordCiphertext = source.passwordCiphertext;
        passwordIv = source.passwordIv;
        passwordVersion = source.passwordVersion;
    }
}
