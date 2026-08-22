package io.kubefoundry.installer;

import io.kubefoundry.cluster.KubemateComponentCatalog;
import io.kubefoundry.job.JobService;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** 为任务快照生成稳定的步骤键和部署单元顺序。 */
public final class InstallStepMetadata {

    private InstallStepMetadata() {
    }

    public static Tracker tracker() {
        return new Tracker();
    }

    public static final class Tracker {
        private final Map<String, Integer> stageOrders = new LinkedHashMap<>();
        private final Map<String, Integer> stepOrders = new LinkedHashMap<>();

        JobService.StepDefinition definition(
                InstallStep step,
                int order,
                List<JobService.NodeOperation> operations) {
            Stage stage = next(step);
            return new JobService.StepDefinition(
                    step.name(), order, step.maxWorkers(), step.failFast(), operations,
                    step.componentGroupKey(), step.key(), stage.key(), stage.name(),
                    stage.order(), stage.stepOrder());
        }

        public Stage next(InstallStep step) {
            String stageKey = stageKey(step);
            int stageOrder = stageOrders.computeIfAbsent(stageKey, ignored -> stageOrders.size() + 1);
            int stepOrderInStage = stepOrders.merge(stageKey, 1, Integer::sum);
            return new Stage(stageKey, stageName(step, stageKey), stageOrder, stepOrderInStage);
        }

        private static String stageKey(InstallStep step) {
            if (step.componentGroupKey() != null) return step.componentGroupKey();
            return step.phase() == null || step.phase().isBlank() ? "default" : step.phase();
        }

        private static String stageName(InstallStep step, String stageKey) {
            if (step.componentGroupKey() != null) {
                KubemateComponentCatalog.Group group = KubemateComponentCatalog.find(stageKey);
                return group == null ? stageKey : group.name();
            }
            return switch (stageKey) {
                case "k8s_base" -> "Kubernetes 基础安装";
                case "reset" -> "重置集群";
                case "verify" -> "验证集群";
                default -> stageKey;
            };
        }
    }

    public record Stage(String key, String name, int order, int stepOrder) {
    }
}
