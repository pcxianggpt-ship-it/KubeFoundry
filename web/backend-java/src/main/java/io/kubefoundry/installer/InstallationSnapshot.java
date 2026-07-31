package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.job.Job;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "installation_snapshots")
public class InstallationSnapshot {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "job_id", nullable = false, unique = true)
    private Job job;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "cluster_id", nullable = false)
    private Cluster cluster;

    @Column(name = "snapshot_json", nullable = false, columnDefinition = "CLOB")
    private String snapshotJson;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    protected InstallationSnapshot() {
    }

    public InstallationSnapshot(Job job, Cluster cluster, String snapshotJson) {
        if (job == null || cluster == null) throw new IllegalArgumentException("任务和集群不能为空");
        if (snapshotJson == null || snapshotJson.isBlank()) {
            throw new IllegalArgumentException("安装快照不能为空");
        }
        this.job = job;
        this.cluster = cluster;
        this.snapshotJson = snapshotJson;
    }

    public Long getId() { return id; }
    public Job getJob() { return job; }
    public Cluster getCluster() { return cluster; }
    public String getSnapshotJson() { return snapshotJson; }
    public LocalDateTime getCreatedAt() { return createdAt; }
}
