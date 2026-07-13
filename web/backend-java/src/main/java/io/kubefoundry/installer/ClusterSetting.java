package io.kubefoundry.installer;

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
@Table(name = "cluster_settings")
public class ClusterSetting {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "cluster_id", nullable = false)
    private Cluster cluster;

    @Column(name = "setting_key", nullable = false, length = 128)
    private String key;

    @Lob
    @Column(name = "setting_value", nullable = false)
    private String value;

    @Column(nullable = false, length = 32)
    private String status = "active";

    protected ClusterSetting() {
    }

    public ClusterSetting(Cluster cluster, String key, String value) {
        this.cluster = cluster;
        this.key = key;
        this.value = value;
    }

    public Long getId() { return id; }
    public Cluster getCluster() { return cluster; }
    public String getKey() { return key; }
    public String getValue() { return value; }
    public String getStatus() { return status; }

    public void updateValue(String value) {
        this.value = value;
        this.status = "active";
    }
}
