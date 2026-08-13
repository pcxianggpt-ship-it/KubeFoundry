package io.kubefoundry.api;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.forwardedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class SpaForwardControllerTest {

    private final MockMvc mvc = MockMvcBuilders.standaloneSetup(new SpaForwardController()).build();

    @ParameterizedTest
    @ValueSource(strings = {
        "/cluster-config",
        "/cluster-config/1/nodes",
        "/cluster-install",
        "/cluster-install/1",
        "/cluster-install/1/overview",
        "/cluster-install/1/confirm",
        "/cluster-install/1/jobs/9",
        "/clusters/1",
        "/clusters/1/nodes",
        "/clusters/1/install",
        "/clusters/1/install/confirm",
        "/jobs/9/execution"
    })
    void forwardsBrowserRoutesToFrontendEntry(String path) throws Exception {
        mvc.perform(get(path))
                .andExpect(status().isOk())
                .andExpect(forwardedUrl("/index.html"));
    }
}
