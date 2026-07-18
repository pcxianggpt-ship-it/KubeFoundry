package io.kubefoundry.api;

import io.kubefoundry.cluster.ClusterService;
import io.kubefoundry.cluster.ClusterService.ClusterRequest;
import io.kubefoundry.cluster.ClusterService.ClusterResponse;
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

    public ClusterController(ClusterService service) { this.service = service; }

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
    public ClusterResponse reset(@PathVariable long id) {
        return service.resetCluster(id);
    }
}
