package io.kubefoundry.cluster;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.LocalDateTime;

@Entity
@Table(name = "cluster_components", uniqueConstraints = @UniqueConstraint(
        name = "uk_cluster_components_cluster_key", columnNames = {"cluster_id", "component_key"}))
public class ClusterComponent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "cluster_id", nullable = false)
    private Cluster cluster;

    @Column(name = "component_key", nullable = false, length = 64)
    private String componentKey;

    @Column(nullable = false)
    private boolean enabled;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime updatedAt;

    protected ClusterComponent() {
    }

    public ClusterComponent(Cluster cluster, String componentKey, boolean enabled) {
        if (cluster == null) throw new IllegalArgumentException("集群不能为空");
        if (componentKey == null || componentKey.isBlank()) {
            throw new IllegalArgumentException("组件标识不能为空");
        }
        this.cluster = cluster;
        this.componentKey = componentKey.trim();
        this.enabled = enabled;
    }

    public Long getId() { return id; }
    public Cluster getCluster() { return cluster; }
    public String getComponentKey() { return componentKey; }
    public boolean isEnabled() { return enabled; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public LocalDateTime getUpdatedAt() { return updatedAt; }

    public void setEnabled(boolean value) { enabled = value; }
}
