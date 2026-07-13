package io.kubefoundry.job;

import java.util.Map;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Component
public class JobSubmissionFailureHandler {

    static final String FAILURE_MESSAGE = "任务未进入执行队列";

    private final JobRepository jobs;
    private final JobStepRepository steps;
    private final JobStepNodeRepository stepNodes;
    private final EventService events;

    public JobSubmissionFailureHandler(
            JobRepository jobs,
            JobStepRepository steps,
            JobStepNodeRepository stepNodes,
            EventService events) {
        this.jobs = jobs;
        this.steps = steps;
        this.stepNodes = stepNodes;
        this.events = events;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void compensate(long jobId) {
        Job job = jobs.findById(jobId).orElse(null);
        if (job == null || !"pending".equals(job.getStatus())) return;

        for (JobStep step : steps.findByJobIdOrderByOrder(jobId)) {
            for (JobStepNode node : stepNodes.findByStepIdOrderById(step.getId())) {
                node.markFailed(FAILURE_MESSAGE);
                stepNodes.save(node);
                events.publish(jobId, "node.status", Map.of(
                        "node_id", node.getNode().getId(),
                        "hostname", node.getNode().getHostname(),
                        "status", "failed",
                        "message", FAILURE_MESSAGE));
            }
            step.markFailed();
            steps.save(step);
            events.publish(jobId, "step.status", Map.of(
                    "step_id", step.getId(), "status", "failed"));
        }
        job.markInterrupted();
        jobs.save(job);
        events.publish(jobId, "job.status", Map.of("status", "interrupted"));
    }
}
