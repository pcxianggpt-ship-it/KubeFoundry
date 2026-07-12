package io.kubefoundry.job;

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
@Table(name = "job_steps")
public class JobStep {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "job_id", nullable = false)
    private Job job;

    @Column(name = "step_name", nullable = false, length = 128)
    private String name;

    @Column(name = "step_order", nullable = false)
    private int order;

    @Column(nullable = false, length = 32)
    private String status = "pending";

    @Column(name = "log_path", length = 512)
    private String logPath;

    protected JobStep() {
    }

    public JobStep(Job job, String name, int order) {
        this.job = job;
        this.name = name;
        this.order = order;
    }

    public Long getId() { return id; }
    public Job getJob() { return job; }
    public String getName() { return name; }
    public int getOrder() { return order; }
    public String getStatus() { return status; }
    public String getLogPath() { return logPath; }
    public void markRunning() { status = "running"; }
    public void markSuccess() { status = "success"; }
    public void markFailed() { status = "failed"; }
}
