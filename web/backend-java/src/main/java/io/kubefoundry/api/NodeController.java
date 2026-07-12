package io.kubefoundry.api;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.kubefoundry.cluster.ClusterService;
import io.kubefoundry.cluster.ClusterService.NodeRequest;
import io.kubefoundry.cluster.ClusterService.NodeResponse;
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
@RequestMapping("/api")
public class NodeController {

    private final ClusterService service;

    public NodeController(ClusterService service) { this.service = service; }

    @GetMapping("/clusters/{clusterId}/nodes")
    public Map<String, List<NodeResponse>> list(@PathVariable long clusterId) {
        return Map.of("items", service.listNodes(clusterId));
    }

    @PostMapping("/clusters/{clusterId}/nodes")
    public ResponseEntity<NodeResponse> create(
            @PathVariable long clusterId, @RequestBody NodeRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(service.createNode(clusterId, request));
    }

    @PutMapping("/nodes/{id}")
    public NodeResponse update(@PathVariable long id, @RequestBody NodeRequest request) {
        return service.updateNode(id, request);
    }

    @DeleteMapping("/nodes/{id}")
    public ResponseEntity<Void> delete(@PathVariable long id) {
        service.deleteNode(id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/clusters/{clusterId}/nodes/copy")
    public Map<String, List<NodeResponse>> copy(
            @PathVariable long clusterId, @RequestBody CopyNodesRequest request) {
        return Map.of("items", service.copyNodes(clusterId, request.nodeIds()));
    }

    public record CopyNodesRequest(@JsonProperty("node_ids") List<Long> nodeIds) {}
}
