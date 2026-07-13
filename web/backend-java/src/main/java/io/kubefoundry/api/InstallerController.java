package io.kubefoundry.api;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.kubefoundry.installer.InstallPlanFactory;
import io.kubefoundry.installer.InstallService;
import io.kubefoundry.installer.InstallStep;
import io.kubefoundry.installer.PrecheckService;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class InstallerController {

    private final InstallPlanFactory plans;
    private final PrecheckService prechecks;
    private final InstallService installs;

    public InstallerController(
            InstallPlanFactory plans, PrecheckService prechecks, InstallService installs) {
        this.plans = plans;
        this.prechecks = prechecks;
        this.installs = installs;
    }

    @GetMapping("/install-plan")
    public Items<PlanItem> plan() {
        List<InstallStep> steps = plans.create().steps();
        return new Items<>(java.util.stream.IntStream.range(0, steps.size())
                .mapToObj(index -> PlanItem.from(index + 1, steps.get(index))).toList());
    }

    @PostMapping("/clusters/{clusterId}/precheck")
    public ResponseEntity<JobAccepted> precheck(@PathVariable long clusterId) {
        return ResponseEntity.status(HttpStatus.ACCEPTED)
                .body(new JobAccepted(prechecks.start(clusterId), "pending"));
    }

    @PostMapping("/clusters/{clusterId}/install")
    public ResponseEntity<JobAccepted> install(
            @PathVariable long clusterId, @RequestBody(required = false) InstallRequest request) {
        List<String> selected = request == null || request.steps() == null
                ? List.of() : request.steps();
        return ResponseEntity.status(HttpStatus.ACCEPTED)
                .body(new JobAccepted(installs.start(clusterId, selected), "pending"));
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
            @JsonProperty("target_scope") String targetScope,
            String mode,
            @JsonProperty("max_workers") int maxWorkers,
            @JsonProperty("required_resources") List<String> requiredResources) {
        static PlanItem from(int order, InstallStep step) {
            return new PlanItem(order, step.key(), step.name(), step.phase(), step.targetScope(),
                    step.mode(), step.maxWorkers(), step.resources().stream()
                            .map(resource -> resource.pathKey() == null
                                    ? resource.artifactKey() : resource.pathKey())
                            .toList());
        }
    }
}
