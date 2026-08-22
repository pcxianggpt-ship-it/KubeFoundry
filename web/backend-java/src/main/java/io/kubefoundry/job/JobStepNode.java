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

    @Column(name = "log_path", length = 512)
    private String logPath;

    @Column(name = "exit_code")
    private Integer exitCode;

    @Column(length = 1024)
    private String message;

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
    public String getLogPath() { return logPath; }
    public Integer getExitCode() { return exitCode; }
    public String getMessage() { return message; }
    public void markRunning() { status = "running"; }
    public void markSuccess() {
        status = "success";
        exitCode = 0;
        message = "执行成功";
    }
    public void markFailed() { markFailed("执行失败"); }
    public void markFailed(String failureMessage) {
        status = "failed";
        if (exitCode == null) exitCode = 1;
        if (message == null || message.isBlank()) message = failureMessage;
    }
    public void markSkipped(String skipMessage) {
        status = "skipped";
        exitCode = null;
        message = skipMessage == null || skipMessage.isBlank()
                ? "组件组前置步骤失败，已跳过" : skipMessage;
    }
    public void complete(JobService.NodeOutcome outcome) {
        status = outcome.status();
        exitCode = "skipped".equals(status) ? null : outcome.exitCode();
        message = outcome.message();
        logPath = outcome.logPath();
    }
}
