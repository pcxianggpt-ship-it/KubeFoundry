package io.kubefoundry.installer;

import io.kubefoundry.cluster.ClusterComponentState;
import io.kubefoundry.cluster.ClusterComponentStateRepository;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobStep;
import io.kubefoundry.job.JobStepRepository;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Applies component installation state transitions only when the owning job still matches. */
@Service
public class ComponentInstallationStateService {
    public static final String JOB_TYPE = "component_install";

    private final ClusterComponentStateRepository states;
    private final JobStepRepository steps;

    public ComponentInstallationStateService(
            ClusterComponentStateRepository states, JobStepRepository steps) {
        this.states = states;
        this.steps = steps;
    }

    @Transactional
    public void markAccepted(Job job, Set<String> groupKeys) {
        if (!isComponentJob(job)) return;
        if (groupKeys == null || groupKeys.isEmpty()) {
            throw new IllegalArgumentException("组件安装任务缺少组件组");
        }
        for (String groupKey : new LinkedHashSet<>(groupKeys)) {
            ClusterComponentState state = requireState(job, groupKey);
            if (!ClusterComponentState.NOT_INSTALLED.equals(state.getStatus())
                    && !ClusterComponentState.FAILED.equals(state.getStatus())) {
                throw new IllegalStateException("组件组当前不可安装: " + groupKey);
            }
            state.markInstalling(job.getId());
            states.save(state);
        }
    }

    @Transactional
    public void onStepSucceeded(Job job, String groupKey) {
        if (!isComponentJob(job) || groupKey == null || groupKey.isBlank()) return;
        ClusterComponentState state = stateOwnedBy(job, groupKey);
        if (state == null) return;
        List<JobStep> groupSteps = groupSteps(job.getId(), groupKey);
        if (!groupSteps.isEmpty() && groupSteps.stream().allMatch(step -> "success".equals(step.getStatus()))) {
            state.markInstalled(null, job.getId());
            states.save(state);
        }
    }

    @Transactional
    public void complete(Job job, boolean success) {
        if (!isComponentJob(job)) return;
        for (String groupKey : groupKeys(job.getId())) {
            ClusterComponentState state = stateOwnedBy(job, groupKey);
            if (state == null) continue;
            List<JobStep> groupSteps = groupSteps(job.getId(), groupKey);
            if (groupSteps.stream().allMatch(step -> "success".equals(step.getStatus()))) {
                state.markInstalled(null, job.getId());
            } else if (success) {
                state.markFailed("COMPONENT_STATE_INCOMPLETE", job.getId());
            } else if (groupSteps.stream().allMatch(step -> "pending".equals(step.getStatus()))) {
                state.reset();
            } else {
                state.markFailed("COMPONENT_INSTALL_FAILED", job.getId());
            }
            states.save(state);
        }
    }

    @Transactional
    public void recoverInterrupted(Job job) {
        if (!isComponentJob(job)) return;
        for (String groupKey : groupKeys(job.getId())) {
            ClusterComponentState state = stateOwnedBy(job, groupKey);
            if (state == null) continue;
            List<JobStep> groupSteps = groupSteps(job.getId(), groupKey);
            if (groupSteps.stream().allMatch(step -> "success".equals(step.getStatus()))) {
                state.markInstalled(null, job.getId());
            } else if (groupSteps.stream().allMatch(step -> "pending".equals(step.getStatus()))) {
                state.reset();
            } else {
                state.markFailed("COMPONENT_INSTALL_INTERRUPTED", job.getId());
            }
            states.save(state);
        }
    }

    @Transactional
    public void markNotStarted(Job job) {
        if (!isComponentJob(job)) return;
        for (String groupKey : groupKeys(job.getId())) {
            ClusterComponentState state = stateOwnedBy(job, groupKey);
            if (state == null) continue;
            state.reset();
            states.save(state);
        }
    }

    private ClusterComponentState requireState(Job job, String groupKey) {
        return states.findByClusterIdAndComponentKey(job.getCluster().getId(), groupKey)
                .orElseThrow(() -> new IllegalArgumentException("组件组状态不存在: " + groupKey));
    }

    private ClusterComponentState stateOwnedBy(Job job, String groupKey) {
        ClusterComponentState state = states.findByClusterIdAndComponentKey(job.getCluster().getId(), groupKey)
                .orElse(null);
        return state != null && job.getId().equals(state.getLastJobId()) ? state : null;
    }

    private List<JobStep> groupSteps(long jobId, String groupKey) {
        return steps.findByJobIdOrderByOrder(jobId).stream()
                .filter(step -> groupKey.equals(step.getComponentGroupKey())).toList();
    }

    private Set<String> groupKeys(long jobId) {
        Set<String> values = new LinkedHashSet<>();
        for (JobStep step : steps.findByJobIdOrderByOrder(jobId)) {
            if (step.getComponentGroupKey() != null && !step.getComponentGroupKey().isBlank()) {
                values.add(step.getComponentGroupKey());
            }
        }
        return values;
    }

    private static boolean isComponentJob(Job job) {
        return job != null && JOB_TYPE.equals(job.getType());
    }
}
