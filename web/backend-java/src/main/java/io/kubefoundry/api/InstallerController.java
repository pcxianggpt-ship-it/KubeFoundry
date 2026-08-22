package io.kubefoundry.api;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.kubefoundry.installer.ClusterSettingsService;
import io.kubefoundry.installer.ComponentInstallService;
import io.kubefoundry.installer.InstallService;
import io.kubefoundry.installer.InstallStep;
import io.kubefoundry.installer.InstallStepMetadata;
import io.kubefoundry.installer.PrecheckService;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class InstallerController {

    private final PrecheckService prechecks;
    private final InstallService installs;
    private final ClusterSettingsService settings;
    private final ComponentInstallService componentInstalls;

    public InstallerController(
            PrecheckService prechecks,
            InstallService installs,
            ClusterSettingsService settings,
            ComponentInstallService componentInstalls) {
        this.prechecks = prechecks;
        this.installs = installs;
        this.settings = settings;
        this.componentInstalls = componentInstalls;
    }

    @GetMapping("/settings")
    public Map<String, Object> settings() {
        return settings.getGlobalSettings();
    }

    @PutMapping("/settings")
    public Map<String, Object> updateSettings(@RequestBody(required = false) Map<String, Object> request) {
        return request == null ? settings.getGlobalSettings() : settings.updateGlobalSettings(request);
    }

    @GetMapping("/clusters/{clusterId}/settings")
    public Map<String, Object> clusterSettings(@PathVariable long clusterId) {
        return settings.getClusterSettings(clusterId);
    }

    @PutMapping("/clusters/{clusterId}/settings")
    public Map<String, Object> updateClusterSettings(
            @PathVariable long clusterId, @RequestBody(required = false) Map<String, Object> request) {
        return settings.updateClusterSettings(clusterId, request == null ? Map.of() : request);
    }

    @GetMapping("/clusters/{clusterId}/install-plan")
    public Items<PlanItem> plan(@PathVariable long clusterId) {
        List<InstallStep> steps = installs.preview(clusterId).steps();
        InstallStepMetadata.Tracker metadata = InstallStepMetadata.tracker();
        return new Items<>(java.util.stream.IntStream.range(0, steps.size())
                .mapToObj(index -> {
                    InstallStep step = steps.get(index);
                    return PlanItem.from(index + 1, step, metadata.next(step));
                }).toList());
    }

    @PostMapping("/clusters/{clusterId}/precheck")
    public ResponseEntity<JobAccepted> precheck(@PathVariable long clusterId) {
        return ResponseEntity.status(HttpStatus.ACCEPTED)
                .body(new JobAccepted(prechecks.start(clusterId), "pending"));
    }

    @PostMapping("/clusters/{clusterId}/install")
    public ResponseEntity<JobAccepted> install(
            @PathVariable long clusterId, @RequestBody(required = false) InstallRequest request) {
        if (request != null && request.steps() != null && !request.steps().isEmpty()) {
            throw new IllegalArgumentException("安装步骤由服务端计划决定，不能由客户端选择");
        }
        return ResponseEntity.status(HttpStatus.ACCEPTED)
                .body(new JobAccepted(installs.start(clusterId), "pending"));
    }

    @PostMapping("/clusters/{clusterId}/components/install")
    public ResponseEntity<JobAccepted> installComponents(@PathVariable long clusterId) {
        return ResponseEntity.status(HttpStatus.ACCEPTED)
                .body(new JobAccepted(componentInstalls.start(clusterId), "pending"));
    }

    public record Items<T>(List<T> items) {
    }

    public record InstallRequest(List<String> steps) {
    }

    public record JobAccepted(@JsonProperty("job_id") long jobId, String status) {
    }

    public record PlanItem(
            int order,
            String key,
            String name,
            String phase,
            @JsonProperty("stage_key") String stageKey,
            @JsonProperty("stage_name") String stageName,
            @JsonProperty("stage_order") int stageOrder,
            @JsonProperty("step_order_in_stage") int stepOrderInStage,
            @JsonProperty("step_type") String stepType,
            @JsonProperty("has_strict_verification") boolean hasStrictVerification,
            @JsonProperty("target_scope") String targetScope,
            String mode,
            @JsonProperty("max_workers") int maxWorkers,
            @JsonProperty("required_resources") List<String> requiredResources) {
        static PlanItem from(int order, InstallStep step, InstallStepMetadata.Stage stage) {
            return new PlanItem(order, step.key(), step.name(), step.phase(),
                    stage.key(), stage.name(), stage.order(), stage.stepOrder(),
                    step.type().name(), step.verifyScript() != null, step.targetScope(),
                    step.mode(), step.maxWorkers(), step.resources().stream()
                            .map(resource -> resource.pathKey() == null
                                    ? resource.artifactKey() : resource.pathKey())
                            .toList());
        }
    }
}
