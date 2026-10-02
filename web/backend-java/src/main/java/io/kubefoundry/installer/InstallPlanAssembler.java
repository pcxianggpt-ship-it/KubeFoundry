package io.kubefoundry.installer;

import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import org.springframework.stereotype.Component;

/** Assembles the base and component plans without querying mutable configuration. */
@Component
public class InstallPlanAssembler {
    private final BaseInstallPlanFactory basePlans;
    private final ComponentPlanFactory componentPlans;
    private final InstallPlan maintenancePlan;

    public InstallPlanAssembler(BaseInstallPlanFactory basePlans, ComponentPlanFactory componentPlans) {
        this.basePlans = basePlans;
        this.componentPlans = componentPlans;
        Path projectRoot = componentPlans.projectRoot();
        InstallStep etcdBackup = InstallStep.script(
                "44-setup-etcd-backup", "配置并验证 etcd 备份", "maintenance",
                "primary_control_plane",
                projectRoot.resolve("scripts/steps/phase3_ecosystem/44-setup-etcd-backup.sh"),
                "serial", 1, true, List.of(), List.of(), List.of(), "")
                .withVerification(projectRoot.resolve(
                        "scripts/verify/phase3_ecosystem/verify-44-setup-etcd-backup.sh"))
                .withType(InstallStep.StepType.MAINTENANCE)
                .withStage(InstallStage.ETCD_BACKUP, 1);
        this.maintenancePlan = new InstallPlan(List.of(etcdBackup));
    }

    public InstallPlan forNewCluster(InstallationSnapshotPayload snapshot) {
        InstallPlan components = componentPlans.create(snapshot);
        InstallStep helm = components.steps().stream()
                .filter(step -> "29-install-helm".equals(step.key())).findFirst().orElse(null);
        java.util.ArrayList<InstallStep> steps = new java.util.ArrayList<>();
        for (InstallStep step : basePlans.create().steps()) {
            steps.add(step);
            if ("16-install-containerd".equals(step.key()) && helm != null) steps.add(helm);
        }
        components.steps().stream().filter(step -> !"29-install-helm".equals(step.key()))
                .forEach(steps::add);
        steps.addAll(maintenancePlan.steps());
        return new InstallPlan(steps);
    }

    public InstallPlan forExistingCluster(InstallationSnapshotPayload snapshot, Set<String> groups) {
        return componentPlans.create(snapshot, groups);
    }
}
