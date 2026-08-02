package io.kubefoundry.api;

import io.kubefoundry.cluster.ClusterComponentService;
import io.kubefoundry.cluster.ClusterComponentService.ComponentsRequest;
import io.kubefoundry.cluster.ClusterComponentService.ComponentsResponse;
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
    public ComponentsResponse list(@PathVariable long clusterId) { return service.list(clusterId); }

    @PutMapping
    public ComponentsResponse replace(@PathVariable long clusterId, @RequestBody ComponentsRequest request) {
        return service.replace(clusterId, request);
    }
}
