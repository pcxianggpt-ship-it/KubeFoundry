package io.kubefoundry.installer;

import java.util.List;

public record InstallPlan(List<InstallStep> steps) {

    public InstallPlan {
        steps = List.copyOf(steps);
    }

    public InstallStep require(String key) {
        return steps.stream()
                .filter(step -> step.key().equals(key))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("未知安装步骤: " + key));
    }
}
