package io.kubefoundry.api;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:component-api;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.jpa.hibernate.ddl-auto=validate"
})
@AutoConfigureMockMvc
class ClusterComponentApiTest {

    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcTemplate jdbc;

    @BeforeEach
    void clearDatabase() {
        jdbc.update("delete from jobs");
        jdbc.update("delete from clusters");
    }

    @Test
    void rejectsComponentWritesWhileInstallerJobIsActive() throws Exception {
        long clusterId = createCluster("components-active");
        jdbc.update("insert into jobs (cluster_id, job_type, status) values (?, ?, ?)",
                clusterId, "install", "running");

        mvc.perform(put("/api/clusters/{id}/components", clusterId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"items\":[{\"key\":\"loki\",\"enabled\":true}]}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("INSTALLER_JOB_ACTIVE"));
    }

    private long createCluster(String name) throws Exception {
        String body = mvc.perform(post("/api/clusters")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"k8s_version\":\"1.30.14\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return Long.parseLong(body.replaceAll(".*\\\"id\\\":(\\d+).*", "$1"));
    }
}
