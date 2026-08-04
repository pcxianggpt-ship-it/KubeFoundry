package io.kubefoundry.api;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
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
                        .content("{\"enabled\":true,\"groups\":[{\"key\":\"traefik\",\"enabled\":true,\"config\":{}}]}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("INSTALLER_JOB_ACTIVE"));
    }

    @Test
    void listsFixedGroupsAndKubemateSwitch() throws Exception {
        long clusterId = createCluster("components-default");
        mvc.perform(get("/api/clusters/{id}/components", clusterId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.enabled").value(false))
                .andExpect(jsonPath("$.groups.length()").value(6))
                .andExpect(jsonPath("$.groups[0].key").value("nfs"))
                .andExpect(jsonPath("$.groups[3].components[0]").value("openebs"))
                .andExpect(jsonPath("$.groups[5].available").value(false));
    }

    @Test
    void rejectsUnavailableUnknownDuplicateAndInvalidNfsGroups() throws Exception {
        long clusterId = createCluster("components-validation");
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":true,\"groups\":[{\"key\":\"redis_sentinel\",\"enabled\":true,\"config\":{}}]}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("COMPONENT_GROUP_UNAVAILABLE"));
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":true,\"groups\":[{\"key\":\"unknown\",\"enabled\":true,\"config\":{}}]}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("COMPONENT_GROUP_UNKNOWN"));
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":true,\"groups\":[{\"key\":\"traefik\",\"enabled\":false,\"config\":{}},{\"key\":\"traefik\",\"enabled\":false,\"config\":{}}]}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("COMPONENT_CONFIG_INVALID"));
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":true,\"groups\":[{\"key\":\"nfs\",\"enabled\":true,\"config\":{\"server_address\":\"not-ip\"}}]}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("COMPONENT_CONFIG_INVALID"));
    }

    @Test
    void savesComponentGroupsAndNfsConfiguration() throws Exception {
        long clusterId = createCluster("components-save");
        String nfs = "{\"server_address\":\"10.0.0.10\",\"share_path\":\"/exports/k8s\",\"worker_mount_path\":\"/data/k8s/nfs\",\"storage_class\":\"nfs-storage\",\"exports_mode\":\"external\"}";
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":true,\"groups\":[{\"key\":\"nfs\",\"enabled\":true,\"config\":" + nfs + "},{\"key\":\"traefik\",\"enabled\":true,\"config\":{}}]}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.enabled").value(true))
                .andExpect(jsonPath("$.configurationVersion").value(1))
                .andExpect(jsonPath("$.precheckStatus").value("stale"))
                .andExpect(jsonPath("$.groups[0].enabled").value(true))
                .andExpect(jsonPath("$.groups[0].config.server_address").value("10.0.0.10"))
                .andExpect(jsonPath("$.groups[2].enabled").value(true));
    }

    @Test
    void onlyInvalidatesComponentPrechecksWhenTheSavedConfigurationChanges() throws Exception {
        long clusterId = createCluster("components-version");
        String body = "{\"enabled\":true,\"groups\":[{\"key\":\"traefik\",\"enabled\":true,\"config\":{}}]}";

        mvc.perform(put("/api/clusters/{id}/components", clusterId)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.configurationVersion").value(1));
        mvc.perform(put("/api/clusters/{id}/components", clusterId)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.configurationVersion").value(1));

        Integer nodeConfigVersion = jdbc.queryForObject(
                "select node_config_version from clusters where id = ?", Integer.class, clusterId);
        Integer componentConfigVersion = jdbc.queryForObject(
                "select component_config_version from clusters where id = ?", Integer.class, clusterId);
        assertThat(nodeConfigVersion).isZero();
        assertThat(componentConfigVersion).isEqualTo(1);
    }

    @Test
    void allowsChangingUninstalledGroupsAfterBaseInstallationButKeepsInstalledGroupsReadOnly() throws Exception {
        long clusterId = createCluster("components-installed");
        jdbc.update("update clusters set installation_locked = true, status = 'installed' where id = ?", clusterId);

        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":true,\"groups\":[{\"key\":\"traefik\",\"enabled\":true,\"config\":{}}]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.groups[2].enabled").value(true));

        jdbc.update("update cluster_component_states set status = 'installed' where cluster_id = ? and component_key = 'traefik'", clusterId);
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":true,\"groups\":[{\"key\":\"traefik\",\"enabled\":false,\"config\":{}}]}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("COMPONENT_GROUP_READ_ONLY"));

        jdbc.update("update cluster_component_states set status = 'installing' where cluster_id = ? and component_key = 'traefik'", clusterId);
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":true,\"groups\":[{\"key\":\"traefik\",\"enabled\":false,\"config\":{}}]}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("COMPONENT_GROUP_READ_ONLY"));
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
