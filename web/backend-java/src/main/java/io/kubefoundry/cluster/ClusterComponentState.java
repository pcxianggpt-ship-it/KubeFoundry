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
@Table(name = "cluster_component_states", uniqueConstraints = @UniqueConstraint(
        name = "uk_cluster_component_states_cluster_key",
        columnNames = {"cluster_id", "component_key"}))
public class ClusterComponentState {
    public static final String NOT_INSTALLED = "not_installed";
    public static final String INSTALLING = "installing";
    public static final String INSTALLED = "installed";
    public static final String FAILED = "failed";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "cluster_id", nullable = false)
    private Cluster cluster;

    @Column(name = "component_key", nullable = false, length = 64)
    private String componentKey;

    @Column(nullable = false, length = 32)
    private String status = NOT_INSTALLED;

    @Column(name = "installed_version", length = 64)
    private String installedVersion;

    @Column(name = "last_job_id")
    private Long lastJobId;

    @Column(name = "last_error_code", length = 128)
    private String lastErrorCode;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime updatedAt;

    protected ClusterComponentState() {
    }

    public ClusterComponentState(Cluster cluster, String componentKey) {
        if (cluster == null) throw new IllegalArgumentException("集群不能为空");
        if (componentKey == null || componentKey.isBlank()) {
            throw new IllegalArgumentException("组件组标识不能为空");
        }
        this.cluster = cluster;
        this.componentKey = componentKey.trim();
    }

    public Long getId() { return id; }
    public Cluster getCluster() { return cluster; }
    public String getComponentKey() { return componentKey; }
    public String getStatus() { return status; }
    public String getInstalledVersion() { return installedVersion; }
    public Long getLastJobId() { return lastJobId; }
    public String getLastErrorCode() { return lastErrorCode; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public LocalDateTime getUpdatedAt() { return updatedAt; }

    public void markInstalling(Long jobId) {
        status = INSTALLING;
        lastJobId = jobId;
        lastErrorCode = null;
    }

    public void markInstalled(String version, Long jobId) {
        status = INSTALLED;
        installedVersion = normalizeOptional(version);
        lastJobId = jobId;
        lastErrorCode = null;
    }

    public void markFailed(String errorCode, Long jobId) {
        status = FAILED;
        lastJobId = jobId;
        lastErrorCode = normalizeOptional(errorCode);
    }

    public void reset() {
        status = NOT_INSTALLED;
        installedVersion = null;
        lastJobId = null;
        lastErrorCode = null;
    }

    private static String normalizeOptional(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }
}
