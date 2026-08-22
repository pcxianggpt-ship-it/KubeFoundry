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

    @Column(name = "step_key", nullable = false, length = 128)
    private String stepKey;

    @Column(name = "stage_key", nullable = false, length = 128)
    private String stageKey;

    @Column(name = "stage_name", nullable = false, length = 128)
    private String stageName;

    @Column(name = "stage_order", nullable = false)
    private int stageOrder;

    @Column(name = "step_order_in_stage", nullable = false)
    private int stepOrderInStage;

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
        this(job, name, order, null, "step-" + order, "default", "任务步骤", 1, order);
    }

    public JobStep(Job job, String name, int order, String componentGroupKey) {
        this(job, name, order, componentGroupKey, "step-" + order,
                componentGroupKey == null || componentGroupKey.isBlank() ? "default" : componentGroupKey,
                componentGroupKey == null || componentGroupKey.isBlank() ? "任务步骤" : componentGroupKey,
                1, order);
    }

    public JobStep(
            Job job,
            String name,
            int order,
            String componentGroupKey,
            String stepKey,
            String stageKey,
            String stageName,
            int stageOrder,
            int stepOrderInStage) {
        if (job == null) throw new IllegalArgumentException("任务不能为空");
        if (name == null || name.isBlank()) throw new IllegalArgumentException("步骤名称不能为空");
        if (order < 1) throw new IllegalArgumentException("步骤顺序必须为正整数");
        if (stepKey == null || stepKey.isBlank()) throw new IllegalArgumentException("步骤键不能为空");
        if (stageKey == null || stageKey.isBlank()) throw new IllegalArgumentException("部署单元键不能为空");
        if (stageName == null || stageName.isBlank()) throw new IllegalArgumentException("部署单元名称不能为空");
        if (stageOrder < 1 || stepOrderInStage < 1) {
            throw new IllegalArgumentException("部署单元和单元内顺序必须为正整数");
        }
        this.job = job;
        this.name = name.trim();
        this.order = order;
        this.componentGroupKey = componentGroupKey == null || componentGroupKey.isBlank()
                ? null : componentGroupKey.trim();
        this.stepKey = normalizeMetadata(stepKey, "步骤键");
        this.stageKey = normalizeMetadata(stageKey, "部署单元键");
        this.stageName = normalizeMetadata(stageName, "部署单元名称");
        this.stageOrder = stageOrder;
        this.stepOrderInStage = stepOrderInStage;
    }

    public Long getId() { return id; }
    public Job getJob() { return job; }
    public String getName() { return name; }
    public int getOrder() { return order; }
    public String getStepKey() { return stepKey; }
    public String getStageKey() { return stageKey; }
    public String getStageName() { return stageName; }
    public int getStageOrder() { return stageOrder; }
    public int getStepOrderInStage() { return stepOrderInStage; }
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

    private static String normalizeMetadata(String value, String label) {
        String normalized = value.trim();
        if (normalized.length() > 128) throw new IllegalArgumentException(label + "不能超过 128 个字符");
        return normalized;
    }
}
