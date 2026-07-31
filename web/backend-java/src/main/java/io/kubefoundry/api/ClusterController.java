package io.kubefoundry.api;

import io.kubefoundry.cluster.ClusterService;
import io.kubefoundry.cluster.ClusterService.ClusterRequest;
import io.kubefoundry.cluster.ClusterService.ClusterResponse;
import io.kubefoundry.installer.ClusterResetService;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/clusters")
public class ClusterController {

    private final ClusterService service;
    private final ClusterResetService resets;

    public ClusterController(ClusterService service, ClusterResetService resets) {
        this.service = service;
        this.resets = resets;
    }

    @GetMapping
    public Map<String, List<ClusterResponse>> list() {
        return Map.of("items", service.listClusters());
    }

    @PostMapping
    public ResponseEntity<ClusterResponse> create(@RequestBody ClusterRequest request) {
        var result = service.upsertCluster(request);
        return ResponseEntity.status(result.created() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(result.cluster());
    }

    @GetMapping("/{id}")
    public ClusterResponse get(@PathVariable long id) { return service.getCluster(id); }

    @PutMapping("/{id}")
    public ClusterResponse update(@PathVariable long id, @RequestBody ClusterRequest request) {
        return service.updateCluster(id, request);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable long id) {
        service.deleteCluster(id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/{id}/reset")
    public ResponseEntity<ResetAccepted> reset(
            @PathVariable long id, @RequestBody(required = false) ResetRequest request) {
        return ResponseEntity.accepted().body(new ResetAccepted(
                resets.start(id, request != null && request.acknowledged(),
                        request == null ? null : request.confirmationPhrase()), "pending"));
    }

    public record ResetRequest(boolean acknowledged,
            @com.fasterxml.jackson.annotation.JsonProperty("confirmation_phrase") String confirmationPhrase) { }
    public record ResetAccepted(@com.fasterxml.jackson.annotation.JsonProperty("job_id") long jobId,
            String status) { }
}
