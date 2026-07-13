package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.job.Job;
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
@Table(name = "precheck_results")
public class PrecheckResult {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "cluster_id", nullable = false)
    private Cluster cluster;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "job_id", nullable = false)
    private Job job;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "node_id", nullable = false)
    private Node node;

    @Column(name = "check_key", nullable = false, length = 128)
    private String checkKey;

    @Column(name = "check_name", nullable = false, length = 128)
    private String checkName;

    @Column(nullable = false, length = 32)
    private String severity;

    @Column(nullable = false, length = 32)
    private String status;

    @Column(nullable = false, length = 1024)
    private String message;

    @Lob
    private String detail;

    protected PrecheckResult() {
    }

    public PrecheckResult(
            Cluster cluster,
            Job job,
            Node node,
            String checkKey,
            String checkName,
            String severity,
            String status,
            String message,
            String detail) {
        this.cluster = cluster;
        this.job = job;
        this.node = node;
        this.checkKey = checkKey;
        this.checkName = checkName;
        this.severity = severity;
        this.status = status;
        this.message = message;
        this.detail = detail == null ? "" : detail;
    }

    public Long getId() { return id; }
    public Cluster getCluster() { return cluster; }
    public Job getJob() { return job; }
    public Node getNode() { return node; }
    public String getCheckKey() { return checkKey; }
    public String getCheckName() { return checkName; }
    public String getSeverity() { return severity; }
    public String getStatus() { return status; }
    public String getMessage() { return message; }
    public String getDetail() { return detail; }
}
