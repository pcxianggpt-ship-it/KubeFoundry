package io.kubefoundry.api;

import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobService;
import io.kubefoundry.installer.InstallResumeService;
import com.fasterxml.jackson.annotation.JsonProperty;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Provides a cluster-scoped job lookup so a task ID cannot be viewed through another cluster URL. */
@RestController
@RequestMapping("/api/clusters/{clusterId}/jobs")
public class ClusterJobController {
    private final JobService jobs;
    private final InstallResumeService resumes;

    public ClusterJobController(JobService jobs, InstallResumeService resumes) {
        this.jobs = jobs;
        this.resumes = resumes;
    }

    @GetMapping("/{jobId}")
    public JobController.JobResponse get(
            @PathVariable long clusterId,
            @PathVariable long jobId) {
        Job job = jobs.get(jobId);
        if (!job.getCluster().getId().equals(clusterId)) {
            throw new ClusterJobMismatchException(clusterId, jobId);
        }
        return JobController.JobResponse.from(job);
    }

    @PostMapping("/{jobId}/resume")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public ResumeResponse resume(
            @PathVariable long clusterId,
            @PathVariable long jobId) {
        long newJobId = resumes.resume(clusterId, jobId);
        return new ResumeResponse(newJobId, "pending", jobId, "resume");
    }

    public record ResumeResponse(
            @JsonProperty("job_id") long jobId,
            String status,
            @JsonProperty("source_job_id") long sourceJobId,
            @JsonProperty("run_mode") String runMode) {
    }

    public static class ClusterJobMismatchException extends RuntimeException {
        public ClusterJobMismatchException(long clusterId, long jobId) {
            super("任务 " + jobId + " 不属于集群 " + clusterId);
        }
    }
}
