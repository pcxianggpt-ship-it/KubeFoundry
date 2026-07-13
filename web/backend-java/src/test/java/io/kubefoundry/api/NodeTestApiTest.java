package io.kubefoundry.api;

import io.kubefoundry.ssh.NodeTestService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.Mockito.when;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(NodeController.class)
class NodeTestApiTest {

    @Autowired
    MockMvc mvc;

    @MockBean
    io.kubefoundry.cluster.ClusterService clusterService;

    @MockBean
    NodeTestService nodeTests;

    @Test
    void startsClusterAndSingleNodeTests() throws Exception {
        when(nodeTests.startClusterTest(9, false)).thenReturn(101L);
        when(nodeTests.startNodeTest(7)).thenReturn(102L);

        mvc.perform(post("/api/clusters/9/node-test"))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.job_id").value(101))
                .andExpect(jsonPath("$.status").value("pending"));
        mvc.perform(post("/api/nodes/7/node-test"))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.job_id").value(102));
    }

    @Test
    void forwardsFailedOnlyAndReturnsActiveJobConflict() throws Exception {
        when(nodeTests.startClusterTest(9, true)).thenReturn(103L);
        when(nodeTests.startClusterTest(10, false))
                .thenThrow(new NodeTestService.ActiveNodeTestException(88L));

        mvc.perform(post("/api/clusters/9/node-test").param("failed_only", "true"))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.job_id").value(103));
        verify(nodeTests).startClusterTest(9, true);

        mvc.perform(post("/api/clusters/10/node-test"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("NODE_TEST_ACTIVE"))
                .andExpect(jsonPath("$.job_id").value(88));
    }
}
