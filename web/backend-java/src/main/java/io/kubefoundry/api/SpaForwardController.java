package io.kubefoundry.api;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class SpaForwardController {

    @GetMapping({
        "/cluster-config",
        "/cluster-config/{clusterId}/{stage}",
        "/cluster-install",
        "/cluster-install/{clusterId}/{stage}",
        "/clusters/{clusterId}",
        "/clusters/{clusterId}/{stage}",
        "/clusters/{clusterId}/install/confirm",
        "/jobs/{jobId}/execution"
    })
    public String frontendRoute() {
        return "forward:/index.html";
    }
}
