package io.kubefoundry.job;

import io.kubefoundry.cluster.Node;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "job_step_nodes")
public class JobStepNode {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "job_step_id", nullable = false)
    private JobStep step;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "node_id", nullable = false)
    private Node node;

    @Column(nullable = false, length = 32)
    private String status = "pending";

    protected JobStepNode() {
    }

    public JobStepNode(JobStep step, Node node) {
        this.step = step;
        this.node = node;
    }

    public Long getId() { return id; }
    public JobStep getStep() { return step; }
    public Node getNode() { return node; }
    public String getStatus() { return status; }
    public void markRunning() { status = "running"; }
    public void markSuccess() { status = "success"; }
    public void markFailed() { status = "failed"; }
}
