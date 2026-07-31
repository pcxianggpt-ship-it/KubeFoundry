package io.kubefoundry.api;

import io.kubefoundry.cluster.ClusterComponentService;
import io.kubefoundry.cluster.ClusterComponentService.ComponentRequest;
import io.kubefoundry.cluster.ClusterComponentService.ComponentResponse;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/clusters/{clusterId}/components")
public class ClusterComponentController {
    private final ClusterComponentService service;
    public ClusterComponentController(ClusterComponentService service) { this.service = service; }

    @GetMapping
    public Items<ComponentResponse> list(@PathVariable long clusterId) {
        return new Items<>(service.list(clusterId));
    }

    @PutMapping
    public Items<ComponentResponse> replace(
            @PathVariable long clusterId, @RequestBody(required = false) Items<ComponentRequest> request) {
        return new Items<>(service.replace(clusterId, request == null ? List.of() : request.items()));
    }

    public record Items<T>(List<T> items) { }
}
