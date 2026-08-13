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

    @Column(name = "component_group_key", length = 64)
    private String componentGroupKey;

    @Column(nullable = false, length = 32)
    private String status = "pending";

    @Column(name = "log_path", length = 512)
    private String logPath;

    @Column(name = "status_reason", length = 256)
    private String statusReason;

    protected JobStep() {
    }

    public JobStep(Job job, String name, int order) {
        this(job, name, order, null);
    }

    public JobStep(Job job, String name, int order, String componentGroupKey) {
        this.job = job;
        this.name = name;
        this.order = order;
        this.componentGroupKey = componentGroupKey == null || componentGroupKey.isBlank()
                ? null : componentGroupKey.trim();
    }

    public Long getId() { return id; }
    public Job getJob() { return job; }
    public String getName() { return name; }
    public int getOrder() { return order; }
    public String getComponentGroupKey() { return componentGroupKey; }
    public String getStatus() { return status; }
    public String getLogPath() { return logPath; }
    public String getStatusReason() { return statusReason; }
    public void markRunning() { status = "running"; statusReason = null; }
    public void markSuccess() { status = "success"; statusReason = null; }
    public void markFailed() { markFailed("STEP_EXECUTION_FAILED"); }
    public void markFailed(String reason) { status = "failed"; statusReason = normalizeReason(reason); }
    public void markSkipped() { markSkipped("STEP_SKIPPED"); }
    public void markSkipped(String reason) { status = "skipped"; statusReason = normalizeReason(reason); }

    private static String normalizeReason(String reason) {
        if (reason == null || reason.isBlank()) return null;
        String normalized = reason.trim();
        return normalized.length() <= 256 ? normalized : normalized.substring(0, 256);
    }
}
