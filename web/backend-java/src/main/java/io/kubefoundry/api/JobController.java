package io.kubefoundry.api;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobService;
import io.kubefoundry.job.JobStep;
import io.kubefoundry.job.JobStepNode;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/jobs")
public class JobController {

    private final JobService jobs;

    public JobController(JobService jobs) {
        this.jobs = jobs;
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

    public record Items<T>(List<T> items) {
    }

    public record JobResponse(
            long id,
            @JsonProperty("cluster_id") long clusterId,
            @JsonProperty("job_type") String jobType,
            String status,
            @JsonProperty("log_path") String logPath) {
        static JobResponse from(Job job) {
            return new JobResponse(job.getId(), job.getCluster().getId(), job.getType(),
                    job.getStatus(), job.getLogPath());
        }
    }

    public record StepResponse(
            long id,
            String name,
            int order,
            String status,
            List<NodeResponse> nodes) {
        static StepResponse from(JobStep step, List<JobStepNode> nodes) {
            return new StepResponse(step.getId(), step.getName(), step.getOrder(), step.getStatus(),
                    nodes.stream().map(NodeResponse::from).toList());
        }
    }

    public record NodeResponse(
            long id,
            @JsonProperty("node_id") long nodeId,
            String hostname,
            String status) {
        static NodeResponse from(JobStepNode value) {
            return new NodeResponse(value.getId(), value.getNode().getId(),
                    value.getNode().getHostname(), value.getStatus());
        }
    }
}
