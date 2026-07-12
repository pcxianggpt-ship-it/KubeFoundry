package io.kubefoundry.job;

import io.kubefoundry.cluster.Cluster;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "jobs")
public class Job {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "cluster_id", nullable = false)
    private Cluster cluster;

    @Column(name = "job_type", nullable = false, length = 64)
    private String type;

    @Column(nullable = false, length = 32)
    private String status = "pending";

    @Column(name = "log_path", length = 512)
    private String logPath;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime updatedAt;

    protected Job() {
    }

    public Job(Cluster cluster, String type) {
        if (cluster == null) throw new IllegalArgumentException("集群不能为空");
        if (type == null || type.isBlank()) throw new IllegalArgumentException("任务类型不能为空");
        this.cluster = cluster;
        this.type = type;
    }

    public Long getId() { return id; }
    public Cluster getCluster() { return cluster; }
    public String getType() { return type; }
    public String getStatus() { return status; }
    public String getLogPath() { return logPath; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public LocalDateTime getUpdatedAt() { return updatedAt; }

    public void markRunning() { status = "running"; }
    public void markSuccess() { status = "success"; }
    public void markFailed() { status = "failed"; }
    public void markInterrupted() { status = "interrupted"; }
}
