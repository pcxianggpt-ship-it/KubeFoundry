package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.nio.file.Path;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/** Compatibility facade for the v0.2.1 base installation plan. */
@Component
public class InstallPlanFactory {
    private final BaseInstallPlanFactory basePlans;

    @Autowired
    public InstallPlanFactory(BaseInstallPlanFactory basePlans) {
        this.basePlans = basePlans;
    }

    public InstallPlanFactory(Path projectRoot) {
        this(new BaseInstallPlanFactory(projectRoot));
    }

    public InstallPlan create() {
        return basePlans.create();
    }

    /** Retained for compatibility; v0.3.0 installation no longer accepts client-selected steps. */
    public InstallPlan select(List<String> selectedKeys) {
        return basePlans.select(selectedKeys);
    }

    public List<Node> resolveTargets(InstallStep step, List<Node> configuredNodes) {
        return basePlans.resolveTargets(step, configuredNodes);
    }

    public List<Node> resolveTargets(InstallStep step, Cluster cluster, List<Node> configuredNodes) {
        return basePlans.resolveTargets(step, cluster, configuredNodes);
    }

    static Path discoverProjectRoot(Path start) {
        return BaseInstallPlanFactory.discoverProjectRoot(start);
    }
}
