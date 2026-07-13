package io.kubefoundry.job;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

@Service
public class JobService {

    private final ClusterRepository clusters;
    private final NodeRepository nodes;
    private final JobRepository jobs;
    private final JobStepRepository steps;
    private final JobStepNodeRepository stepNodes;
    private final JobExecutor executor;
    private final EventService events;

    public JobService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobRepository jobs,
            JobStepRepository steps,
            JobStepNodeRepository stepNodes,
            JobExecutor executor,
            EventService events) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobs = jobs;
        this.steps = steps;
        this.stepNodes = stepNodes;
        this.executor = executor;
        this.events = events;
    }

    public long submit(JobDefinition definition) {
        validate(definition);
        Cluster cluster = clusters.findById(definition.clusterId())
                .orElseThrow(() -> new IllegalArgumentException("集群不存在: " + definition.clusterId()));
        Map<Long, Node> operationNodes = resolveNodes(definition);
        Job job = jobs.saveAndFlush(new Job(cluster, definition.type()));
        try {
            for (StepDefinition stepDefinition : definition.steps().stream()
                    .sorted(Comparator.comparingInt(StepDefinition::order)).toList()) {
                JobStep step = steps.saveAndFlush(
                        new JobStep(job, stepDefinition.name(), stepDefinition.order()));
                for (NodeOperation operation : stepDefinition.nodes()) {
                    Node node = operationNodes.get(operation.nodeId());
                    stepNodes.save(new JobStepNode(step, node));
                }
            }
            executor.submit(() -> run(job.getId(), definition));
        } catch (RuntimeException exception) {
            jobs.deleteById(job.getId());
            throw exception;
        }
        return job.getId();
    }

    public int recoverInterruptedJobs() {
        return jobs.replaceStatus("running");
    }

    @EventListener(ApplicationReadyEvent.class)
    public void recoverOnStartup() {
        recoverInterruptedJobs();
    }

    public List<Job> list(Long clusterId) {
        return clusterId == null
                ? jobs.findAllByOrderByIdDesc()
                : jobs.findByClusterIdOrderByIdDesc(clusterId);
    }

    public Job get(long jobId) {
        return jobs.findById(jobId)
                .orElseThrow(() -> new IllegalArgumentException("任务不存在: " + jobId));
    }

    public List<JobStep> listSteps(long jobId) {
        get(jobId);
        return steps.findByJobIdOrderByOrder(jobId);
    }

    public List<JobStepNode> listStepNodes(long stepId) {
        return stepNodes.findByStepIdOrderById(stepId);
    }

    private void run(long jobId, JobDefinition definition) {
        Job job = get(jobId);
        job.markRunning();
        jobs.saveAndFlush(job);
        events.publish(jobId, "job.status", Map.of("status", "running"));

        try {
            Map<Integer, JobStep> persistedSteps = listSteps(jobId).stream()
                    .collect(java.util.stream.Collectors.toMap(JobStep::getOrder, value -> value));
            for (StepDefinition stepDefinition : definition.steps().stream()
                    .sorted(Comparator.comparingInt(StepDefinition::order)).toList()) {
                JobStep step = persistedSteps.get(stepDefinition.order());
                step.markRunning();
                steps.saveAndFlush(step);
                events.publish(jobId, "step.status", Map.of(
                        "step_id", step.getId(), "status", "running"));

                Map<Long, JobStepNode> persistedNodes = listStepNodes(step.getId()).stream()
                        .collect(java.util.stream.Collectors.toMap(
                                value -> value.getNode().getId(), value -> value));
                List<JobExecutor.NodeWork> work = stepDefinition.nodes().stream()
                        .map(operation -> new JobExecutor.NodeWork(operation.nodeId(), () -> {
                            JobStepNode item = persistedNodes.get(operation.nodeId());
                            item.markRunning();
                            stepNodes.saveAndFlush(item);
                            try {
                                operation.action().run(jobId);
                                item.markSuccess();
                                stepNodes.saveAndFlush(item);
                            } catch (Exception exception) {
                                item.markFailed();
                                stepNodes.saveAndFlush(item);
                                throw exception;
                            }
                        })).toList();
                JobExecutor.ExecutionSummary summary = executor.executeNodes(work);
                if ("failed".equals(summary.status())) {
                    step.markFailed();
                    steps.saveAndFlush(step);
                    events.publish(jobId, "step.status", Map.of(
                            "step_id", step.getId(), "status", "failed"));
                    job.markFailed();
                    jobs.saveAndFlush(job);
                    events.publish(jobId, "job.status", Map.of("status", "failed"));
                    return;
                }
                step.markSuccess();
                steps.saveAndFlush(step);
                events.publish(jobId, "step.status", Map.of(
                        "step_id", step.getId(), "status", "success"));
            }
            job.markSuccess();
            jobs.saveAndFlush(job);
            events.publish(jobId, "job.status", Map.of("status", "success"));
        } catch (RuntimeException exception) {
            job.markFailed();
            jobs.saveAndFlush(job);
            events.publish(jobId, "job.status", Map.of("status", "failed"));
        }
    }

    private static void validate(JobDefinition definition) {
        if (definition == null) throw new IllegalArgumentException("任务定义不能为空");
        if (definition.type() == null || definition.type().isBlank()) {
            throw new IllegalArgumentException("任务类型不能为空");
        }
        if (definition.steps() == null || definition.steps().isEmpty()) {
            throw new IllegalArgumentException("任务步骤不能为空");
        }
        Set<Integer> orders = new HashSet<>();
        for (StepDefinition step : definition.steps()) {
            if (step == null || step.name() == null || step.name().isBlank()) {
                throw new IllegalArgumentException("任务步骤名称不能为空");
            }
            if (!orders.add(step.order())) throw new IllegalArgumentException("任务步骤顺序不能重复");
            if (step.nodes() == null) throw new IllegalArgumentException("节点任务列表不能为空");
            Set<Long> nodeIds = new HashSet<>();
            for (NodeOperation operation : step.nodes()) {
                if (operation == null) throw new IllegalArgumentException("节点任务不能为空");
                if (!nodeIds.add(operation.nodeId())) {
                    throw new IllegalArgumentException("同一步骤不能包含重复节点");
                }
            }
        }
    }

    private Map<Long, Node> resolveNodes(JobDefinition definition) {
        Map<Long, Node> resolved = new HashMap<>();
        for (StepDefinition step : definition.steps()) {
            for (NodeOperation operation : step.nodes()) {
                if (resolved.containsKey(operation.nodeId())) continue;
                Node node = nodes.findByIdAndClusterId(operation.nodeId(), definition.clusterId())
                        .orElseThrow(() -> nodes.existsById(operation.nodeId())
                                ? new IllegalArgumentException("节点不属于任务集群: " + operation.nodeId())
                                : new IllegalArgumentException("节点不存在: " + operation.nodeId()));
                resolved.put(operation.nodeId(), node);
            }
        }
        return resolved;
    }

    public record JobDefinition(long clusterId, String type, List<StepDefinition> steps) {
    }

    public record StepDefinition(String name, int order, List<NodeOperation> nodes) {
    }

    @FunctionalInterface
    public interface JobAction {
        void run(long jobId) throws Exception;
    }

    public record NodeOperation(long nodeId, JobAction action) {
        public NodeOperation {
            if (action == null) throw new IllegalArgumentException("节点任务不能为空");
        }

        public NodeOperation(long nodeId, JobExecutor.CheckedRunnable action) {
            this(nodeId, ignored -> action.run());
        }
    }
}
