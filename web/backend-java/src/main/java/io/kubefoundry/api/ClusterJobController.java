package io.kubefoundry.api;

import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Provides a cluster-scoped job lookup so a task ID cannot be viewed through another cluster URL. */
@RestController
@RequestMapping("/api/clusters/{clusterId}/jobs")
public class ClusterJobController {
    private final JobService jobs;

    public ClusterJobController(JobService jobs) {
        this.jobs = jobs;
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

    public static class ClusterJobMismatchException extends RuntimeException {
        public ClusterJobMismatchException(long clusterId, long jobId) {
            super("任务 " + jobId + " 不属于集群 " + clusterId);
        }
    }
}
