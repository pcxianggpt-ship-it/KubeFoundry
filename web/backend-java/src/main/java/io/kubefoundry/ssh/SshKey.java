package io.kubefoundry.ssh;

import io.kubefoundry.cluster.Cluster;
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
@Table(name = "ssh_keys")
public class SshKey {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "cluster_id", nullable = false)
    private Cluster cluster;

    @Column(nullable = false, length = 128)
    private String name;

    @Lob
    @Column(name = "public_key", nullable = false)
    private String publicKey;

    @Column(name = "private_key_path", nullable = false, length = 512)
    private String privateKeyPath;

    @Column(nullable = false, length = 32)
    private String status = "active";

    protected SshKey() {
    }

    public SshKey(Cluster cluster, String name, String publicKey, String privateKeyPath) {
        this.cluster = cluster;
        this.name = name;
        this.publicKey = publicKey;
        this.privateKeyPath = privateKeyPath;
    }

    public Long getId() { return id; }
    public Cluster getCluster() { return cluster; }
    public String getName() { return name; }
    public String getPublicKey() { return publicKey; }
    public String getPrivateKeyPath() { return privateKeyPath; }
    public String getStatus() { return status; }
}
