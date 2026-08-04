package io.kubefoundry.installer;

import java.util.Set;
import org.springframework.stereotype.Component;

/** Assembles the base and component plans without querying mutable configuration. */
@Component
public class InstallPlanAssembler {
    private final BaseInstallPlanFactory basePlans;
    private final ComponentPlanFactory componentPlans;

    public InstallPlanAssembler(BaseInstallPlanFactory basePlans, ComponentPlanFactory componentPlans) {
        this.basePlans = basePlans;
        this.componentPlans = componentPlans;
    }

    public InstallPlan forNewCluster(InstallationSnapshotPayload snapshot) {
        return InstallPlan.combine(basePlans.create(), componentPlans.create(snapshot));
    }

    public InstallPlan forExistingCluster(InstallationSnapshotPayload snapshot, Set<String> groups) {
        return componentPlans.create(snapshot, groups);
    }
}
