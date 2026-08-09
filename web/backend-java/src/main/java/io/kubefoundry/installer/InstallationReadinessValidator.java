package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.util.List;
import org.springframework.stereotype.Component;

/** Validates all local installation prerequisites before either precheck or installation starts. */
@Component
class InstallationReadinessValidator {
    private final InstallPlanFactory plans;
    private final InstallPlanAssembler assembler;
    private final InstallationSnapshotService snapshots;
    private final ComponentMediaService media;
    private final NfsTargetResolver nfsTargets;

    InstallationReadinessValidator(
            InstallPlanFactory plans,
            InstallPlanAssembler assembler,
            InstallationSnapshotService snapshots,
            ComponentMediaService media,
            NfsTargetResolver nfsTargets) {
        this.plans = plans;
        this.assembler = assembler;
        this.snapshots = snapshots;
        this.media = media;
        this.nfsTargets = nfsTargets;
    }

    InstallPlan validate(Cluster cluster, List<Node> configuredNodes) {
        try {
            List<Node> nodes = InstallationNodes.normalize(configuredNodes);
            ClusterTopologyValidator.requireValid(nodes, cluster.getImageRegistryType());
            InstallationGate.requireSuccessfulNodeTests(cluster, nodes);
            InstallPlan generated = assembler.forNewCluster(snapshots.previewPayload(cluster, nodes));
            for (InstallStep step : generated.steps()) {
                List<Node> targets = plans.resolveTargets(step, cluster, nodes);
                if (targets.isEmpty() && List.of("primary_control_plane", "registry", "nfs_server")
                        .contains(step.targetScope())) {
                    throw new InstallationReadinessException(missingTargetMessage(step, cluster, nodes));
                }
            }
            return media.verifyAndChecksum(generated);
        } catch (InstallationReadinessException exception) {
            throw exception;
        } catch (IllegalArgumentException exception) {
            throw new InstallationReadinessException("安装前置校验未通过：" + exception.getMessage());
        }
    }

    private String missingTargetMessage(InstallStep step, Cluster cluster, List<Node> nodes) {
        if ("nfs_server".equals(step.targetScope())) {
            return nfsTargets.missingTargetMessage(cluster, nodes);
        }
        return "安装步骤“" + step.name() + "”（" + step.key() + "）没有匹配的目标节点。"
                + "请检查节点角色和节点测试状态后重新执行预检查。";
    }
}
