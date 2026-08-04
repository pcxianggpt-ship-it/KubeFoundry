package io.kubefoundry.installer;

import java.util.List;

public record InstallPlan(List<InstallStep> steps) {

    public InstallPlan {
        steps = List.copyOf(steps);
        long distinctKeys = steps.stream().map(InstallStep::key).distinct().count();
        if (distinctKeys != steps.size()) throw new IllegalArgumentException("安装计划包含重复步骤键");
    }

    public InstallStep require(String key) {
        return steps.stream()
                .filter(step -> step.key().equals(key))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("未知安装步骤: " + key));
    }

    public static InstallPlan combine(InstallPlan first, InstallPlan second) {
        List<InstallStep> left = first == null ? List.of() : first.steps();
        List<InstallStep> right = second == null ? List.of() : second.steps();
        return new InstallPlan(java.util.stream.Stream.concat(left.stream(), right.stream()).toList());
    }
}
