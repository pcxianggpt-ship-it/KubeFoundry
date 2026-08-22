package io.kubefoundry.api;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.kubefoundry.installer.PrecheckResult;
import io.kubefoundry.installer.PrecheckResultRepository;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobLogService;
import io.kubefoundry.job.JobService;
import io.kubefoundry.job.JobStep;
import io.kubefoundry.job.JobStepNode;
import java.util.List;
import java.time.LocalDateTime;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/jobs")
public class JobController {

    private final JobService jobs;
    private final JobLogService logs;
    private final PrecheckResultRepository precheckResults;

    public JobController(JobService jobs, JobLogService logs, PrecheckResultRepository precheckResults) {
        this.jobs = jobs;
        this.logs = logs;
        this.precheckResults = precheckResults;
    }

    @GetMapping
    public Items<JobResponse> list(@RequestParam(name = "cluster_id", required = false) Long clusterId) {
        return new Items<>(jobs.list(clusterId).stream().map(JobResponse::from).toList());
    }

    @GetMapping("/{jobId}")
    public JobResponse get(@PathVariable long jobId) {
        return JobResponse.from(jobs.get(jobId));
    }

    @GetMapping("/{jobId}/steps")
    public Items<StepResponse> steps(@PathVariable long jobId) {
        return new Items<>(jobs.listSteps(jobId).stream().map(step -> StepResponse.from(
                step, jobs.listStepNodes(step.getId()))).toList());
    }

    @GetMapping("/{jobId}/precheck-results")
    public Items<PrecheckResultResponse> precheckResults(@PathVariable long jobId) {
        jobs.get(jobId);
        return new Items<>(precheckResults.findByJobIdOrderByNodeIdAscIdAsc(jobId)
                .stream().map(PrecheckResultResponse::from).toList());
    }

    @GetMapping("/{jobId}/logs")
    public Items<JobLogService.LogEntry> logs(@PathVariable long jobId) {
        return new Items<>(logs.list(jobId));
    }

    public record Items<T>(List<T> items) {
    }

    public record JobResponse(
            long id,
            @JsonProperty("cluster_id") long clusterId,
            @JsonProperty("job_type") String jobType,
            @JsonProperty("source_job_id") Long sourceJobId,
            @JsonProperty("run_mode") String runMode,
            String status,
            @JsonProperty("log_path") String logPath,
            @JsonProperty("created_at") LocalDateTime createdAt,
            @JsonProperty("started_at") LocalDateTime startedAt,
            @JsonProperty("finished_at") LocalDateTime finishedAt) {
        static JobResponse from(Job job) {
            return new JobResponse(job.getId(), job.getCluster().getId(), job.getType(),
                    job.getSourceJob() == null ? null : job.getSourceJob().getId(), job.getRunMode(),
                    job.getStatus(), job.getLogPath(), job.getCreatedAt(),
                    job.getStartedAt(), job.getFinishedAt());
        }
    }

    public record StepResponse(
            long id,
            @JsonProperty("step_key") String stepKey,
            String name,
            int order,
            @JsonProperty("stage_key") String stageKey,
            @JsonProperty("stage_name") String stageName,
            @JsonProperty("stage_order") int stageOrder,
            @JsonProperty("step_order_in_stage") int stepOrderInStage,
            String status,
            @JsonProperty("status_reason") String statusReason,
            List<NodeResponse> nodes) {
        static StepResponse from(JobStep step, List<JobStepNode> nodes) {
            return new StepResponse(step.getId(), step.getStepKey(), step.getName(), step.getOrder(),
                    step.getStageKey(), step.getStageName(), step.getStageOrder(),
                    step.getStepOrderInStage(), step.getStatus(), step.getStatusReason(),
                    nodes.stream().map(NodeResponse::from).toList());
        }
    }

    public record NodeResponse(
            long id,
            @JsonProperty("node_id") long nodeId,
            String hostname,
            String status,
            @JsonProperty("log_path") String logPath,
            @JsonProperty("exit_code") Integer exitCode,
            String message) {
        static NodeResponse from(JobStepNode value) {
            return new NodeResponse(value.getId(), value.getNode().getId(),
                    value.getNode().getHostname(), value.getStatus(), value.getLogPath(),
                    value.getExitCode(), value.getMessage());
        }
    }

    public record PrecheckResultResponse(
            long id,
            @JsonProperty("node_id") long nodeId,
            String hostname,
            String ip,
            String role,
            @JsonProperty("check_key") String checkKey,
            @JsonProperty("check_name") String checkName,
            String severity,
            String status,
            String message,
            String detail) {
        static PrecheckResultResponse from(PrecheckResult value) {
            return new PrecheckResultResponse(value.getId(), value.getNode().getId(),
                    value.getNode().getHostname(), value.getNode().getIp(),
                    value.getNode().getRole(), value.getCheckKey(), value.getCheckName(),
                    value.getSeverity(), value.getStatus(), value.getMessage(), value.getDetail());
        }
    }
}
