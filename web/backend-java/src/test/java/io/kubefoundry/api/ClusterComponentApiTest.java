package io.kubefoundry.api;

import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.contains;
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

    @Autowired
    ClusterRepository clusters;

    @Autowired
    NodeRepository nodes;

    @Test
    void storesRedisPasswordEncryptedAndRejectsBlankInputWithoutOverwritingIt() throws Exception {
        long clusterId = createCluster("components-redis-password");
        String password = "test-only-redis-value";
        String body = "{\"groups\":[{\"key\":\"redis_sentinel\",\"enabled\":true,"
                + "\"config\":{\"password\":\"" + password + "\"}}]}";
        String response = mvc.perform(put("/api/clusters/{id}/components", clusterId)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.groups[5].config.has_password").value(true))
                .andExpect(jsonPath("$.groups[5].config.password").doesNotExist())
                .andExpect(jsonPath("$.groups[5].config.password_credential").doesNotExist())
                .andExpect(jsonPath("$.configurationVersion").value(1))
                .andReturn().getResponse().getContentAsString();
        assertThat(response).doesNotContain(password);
        String stored = jdbc.queryForObject("select config_json from cluster_components "
                + "where cluster_id = ? and component_key = 'redis_sentinel'", String.class, clusterId);
        assertThat(stored).contains("password_credential").doesNotContain(password);
        // 重复输入和未传新密码保留原密文；显式空密码必须拒绝。
        mvc.perform(put("/api/clusters/{id}/components", clusterId)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk()).andExpect(jsonPath("$.configurationVersion").value(1));
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"redis_sentinel\",\"enabled\":true,"
                                + "\"config\":{\"password\":\"\",\"has_password\":true}}]}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("COMPONENT_CONFIG_INVALID"));
        mvc.perform(put("/api/clusters/{id}/components", clusterId)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"groups\":[]}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.configurationVersion").value(1));
        assertThat(jdbc.queryForObject("select config_json from cluster_components "
                + "where cluster_id = ? and component_key = 'redis_sentinel'", String.class, clusterId))
                .isEqualTo(stored);
        mvc.perform(get("/api/clusters/{id}/components", clusterId))
                .andExpect(status().isOk()).andExpect(jsonPath("$.groups[5].config.has_password").value(true))
                .andExpect(jsonPath("$.groups[5].config.password_credential").doesNotExist());
        jdbc.update("update cluster_component_states set status='installed' "
                + "where cluster_id=? and component_key='redis_sentinel'", clusterId);
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content(body.replace(password, "changed-test-only-value")))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("COMPONENT_GROUP_READ_ONLY"));
    }

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
                        .content("{\"groups\":[{\"key\":\"traefik\",\"enabled\":true,\"config\":{}}]}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("INSTALLER_JOB_ACTIVE"));
    }

    @Test
    void listsFixedComponentGroupsWithoutKubemateSwitch() throws Exception {
        long clusterId = createCluster("components-default");
        mvc.perform(get("/api/clusters/{id}/components", clusterId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.enabled").doesNotExist())
                .andExpect(jsonPath("$.groups.length()").value(6))
                .andExpect(jsonPath("$.groups[0].key").value("nfs"))
                .andExpect(jsonPath("$.groups[3].components.length()").value(3))
                .andExpect(jsonPath("$.groups[3].components[0]").value("minio"))
                .andExpect(jsonPath("$.groups[3].components[1]").value("loki"))
                .andExpect(jsonPath("$.groups[3].components[2]").value("alloy"))
                .andExpect(jsonPath("$.groups[5].available").value(true));
    }

    @Test
    void acceptsRedisAndRejectsUnknownDuplicateAndInvalidNfsGroups() throws Exception {
        long clusterId = createCluster("components-validation");
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"redis_sentinel\",\"enabled\":true,"
                                + "\"config\":{\"password\":\"test-only-required-value\"}}]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.groups[5].enabled").value(true));
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"unknown\",\"enabled\":true,\"config\":{}}]}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("COMPONENT_GROUP_UNKNOWN"));
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"traefik\",\"enabled\":false,\"config\":{}},{\"key\":\"traefik\",\"enabled\":false,\"config\":{}}]}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("COMPONENT_CONFIG_INVALID"));
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"nfs\",\"enabled\":true,\"config\":{\"server_address\":\"not-ip\"}}]}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("COMPONENT_CONFIG_INVALID"));
    }

    @Test
    void rejectsEnabledRedisWithoutPasswordIncludingForgedStatusAndAllowsDisabledRedis() throws Exception {
        long clusterId = createCluster("components-redis-required");
        for (String config : List.of("{}", "{\"has_password\":true}", "{\"password\":\"\"}", "{\"password\":\"   \"}")) {
            mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                            .content("{\"groups\":[{\"key\":\"redis_sentinel\",\"enabled\":true,\"config\":" + config + "}]}"))
                    .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("COMPONENT_CONFIG_INVALID"));
        }
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"redis_sentinel\",\"enabled\":false,\"config\":{}}]}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.groups[5].enabled").value(false));
    }

    @Test
    void savesComponentGroupsAndNfsConfiguration() throws Exception {
        long clusterId = createCluster("components-save");
        String nfs = "{\"server_address\":\"10.0.0.10\",\"share_path\":\"/exports/k8s\",\"worker_mount_path\":\"/data/k8s/nfs\",\"storage_class\":\"nfs-storage\",\"exports_mode\":\"external\"}";
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"nfs\",\"enabled\":true,\"config\":" + nfs + "},{\"key\":\"traefik\",\"enabled\":true,\"config\":{}}]}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.enabled").doesNotExist())
                .andExpect(jsonPath("$.configurationVersion").value(1))
                .andExpect(jsonPath("$.precheckStatus").value("stale"))
                .andExpect(jsonPath("$.groups[0].enabled").value(true))
                .andExpect(jsonPath("$.groups[0].config.server_address").value("10.0.0.10"))
                .andExpect(jsonPath("$.groups[2].enabled").value(true));
    }

    @Test
    void suppliesAndValidatesStrongMinioResourceConfiguration() throws Exception {
        long clusterId = createCluster("components-minio");
        mvc.perform(get("/api/clusters/{id}/components", clusterId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.groups[3].config.minio_pvc_size").value("10Gi"))
                .andExpect(jsonPath("$.groups[3].config.minio_cpu_request").value("250m"))
                .andExpect(jsonPath("$.groups[3].config.minio_memory_limit").value("4Gi"));

        String valid = "{\"minio_pvc_size\":\"20Gi\",\"minio_cpu_request\":\"500m\","
                + "\"minio_cpu_limit\":\"2\",\"minio_memory_request\":\"1Gi\","
                + "\"minio_memory_limit\":\"4Gi\"}";
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"storage_observability\",\"enabled\":true,\"config\":" + valid + "}]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.groups[3].config.minio_pvc_size").value("20Gi"));

        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"storage_observability\",\"enabled\":true,\"config\":{\"unknown\":\"1\"}}]}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("COMPONENT_CONFIG_INVALID"));
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"storage_observability\",\"enabled\":true,\"config\":{\"minio_cpu_request\":\"3\",\"minio_cpu_limit\":\"2\"}}]}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("MinIO CPU request 不能大于 limit"));
    }

    @Test
    void onlyInvalidatesComponentPrechecksWhenTheSavedConfigurationChanges() throws Exception {
        long clusterId = createCluster("components-version");
        String body = "{\"groups\":[{\"key\":\"traefik\",\"enabled\":true,\"config\":{}}]}";

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
                        .content("{\"groups\":[{\"key\":\"traefik\",\"enabled\":true,\"config\":{}}]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.groups[2].enabled").value(true));

        jdbc.update("update cluster_component_states set status = 'installed' where cluster_id = ? and component_key = 'traefik'", clusterId);
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"traefik\",\"enabled\":false,\"config\":{}}]}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("COMPONENT_GROUP_READ_ONLY"));

        jdbc.update("update cluster_component_states set status = 'installing' where cluster_id = ? and component_key = 'traefik'", clusterId);
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"groups\":[{\"key\":\"traefik\",\"enabled\":false,\"config\":{}}]}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("COMPONENT_GROUP_READ_ONLY"));
    }

    @Test
    void assignsMovesAndRemovesNfsRoleFromSavedConfigurationWithoutChangingBaseRoles() throws Exception {
        long clusterId = createCluster("nfs-role-assignment");
        addNode(clusterId, "master", "10.0.0.1", false, "control_plane", "registry");
        addNode(clusterId, "worker", "10.0.0.2", false, "worker");

        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content(nfsRequest("managed", "10.0.0.1", true)))
                .andExpect(status().isOk());
        mvc.perform(get("/api/clusters/{id}/nodes", clusterId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].roles").value(contains("control_plane", "registry", "nfs_server")))
                .andExpect(jsonPath("$.items[1].roles").value(contains("worker")));

        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content(nfsRequest("managed", "10.0.0.2", true)))
                .andExpect(status().isOk());
        mvc.perform(get("/api/clusters/{id}/nodes", clusterId))
                .andExpect(jsonPath("$.items[0].roles").value(contains("control_plane", "registry")))
                .andExpect(jsonPath("$.items[1].roles").value(contains("worker", "nfs_server")));

        // 外部 IP 即使与集群节点相同，也不应保留 NFS 角色。
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content(nfsRequest("external", "10.0.0.2", true)))
                .andExpect(status().isOk());
        assertBaseRolesOnly(clusterId);

        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content(nfsRequest("managed", "10.0.0.2", true)))
                .andExpect(status().isOk());
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content(nfsRequest("managed", "10.0.0.2", false)))
                .andExpect(status().isOk());
        assertBaseRolesOnly(clusterId);
        assertThat(jdbc.queryForObject("select count(*) from node_roles where role = 'nfs_server'", Integer.class)).isZero();
        assertThat(jdbc.queryForObject("select node_config_version from clusters where id = ?", Integer.class, clusterId)).isZero();
    }

    @Test
    void rejectsNonMemberAndDraftNfsServersAndPreservesExistingAssignmentOnRejectedSaves() throws Exception {
        long clusterId = createCluster("nfs-membership");
        addNode(clusterId, "worker", "10.0.0.1", false, "worker");
        addNode(clusterId, "draft", "10.0.0.3", true, "worker");
        long otherCluster = createCluster("nfs-other-cluster");
        addNode(otherCluster, "other", "10.0.0.2", false, "worker");
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content(nfsRequest("managed", "10.0.0.1", true)))
                .andExpect(status().isOk());

        for (String invalidAddress : List.of("10.0.0.2", "10.0.0.3", "10.0.0.99")) {
            mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                            .content(nfsRequest("managed", invalidAddress, true)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.code").value("COMPONENT_CONFIG_INVALID"));
        }
        jdbc.update("update cluster_component_states set status = 'installed' where cluster_id = ? and component_key = 'nfs'", clusterId);
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content(nfsRequest("external", "10.0.0.99", true)))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("COMPONENT_GROUP_READ_ONLY"));
        mvc.perform(get("/api/clusters/{id}/nodes", clusterId))
                .andExpect(jsonPath("$.items[0].roles").value(contains("worker", "nfs_server")))
                .andExpect(jsonPath("$.items[1].roles").value(contains("worker")));
        mvc.perform(get("/api/clusters/{id}/components", clusterId))
                .andExpect(jsonPath("$.groups[0].config.server_address").value("10.0.0.1"))
                .andExpect(jsonPath("$.configurationVersion").value(1));
    }

    @Test
    void nodeEditingPreservesConfiguredNfsAssignmentAndCopiesDoNotInheritIt() throws Exception {
        long clusterId = createCluster("nfs-edit-and-copy");
        long nodeId = addNode(clusterId, "worker", "10.0.0.1", false, "worker");
        mvc.perform(put("/api/clusters/{id}/components", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content(nfsRequest("managed", "10.0.0.1", true)))
                .andExpect(status().isOk());
        mvc.perform(put("/api/nodes/{id}", nodeId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"roles\":[\"worker\",\"registry\"]}"))
                .andExpect(status().isOk());
        mvc.perform(post("/api/clusters/{id}/nodes/copy", clusterId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"node_ids\":[" + nodeId + "]}"))
                .andExpect(status().isOk());
        mvc.perform(get("/api/clusters/{id}/nodes", clusterId))
                .andExpect(jsonPath("$.items[0].roles").value(contains("registry", "worker", "nfs_server")))
                .andExpect(jsonPath("$.items[1].roles").value(contains("registry", "worker")))
                .andExpect(jsonPath("$.items[1].is_draft").value(true));
    }

    private void assertBaseRolesOnly(long clusterId) throws Exception {
        mvc.perform(get("/api/clusters/{id}/nodes", clusterId))
                .andExpect(jsonPath("$.items[0].roles").value(contains("control_plane", "registry")))
                .andExpect(jsonPath("$.items[1].roles").value(contains("worker")));
    }

    private long addNode(long clusterId, String hostname, String ip, boolean draft, String... roles) {
        Node node = new Node(clusters.findById(clusterId).orElseThrow());
        node.update(hostname, ip, "", null, "root", 22);
        node.updateNormalizedIdentity(hostname, ip);
        node.replaceRoles(List.of(roles));
        node.markDraft(draft);
        return nodes.saveAndFlush(node).getId();
    }

    private static String nfsRequest(String mode, String ip, boolean enabled) {
        return """
                {"groups":[{"key":"nfs","enabled":%s,"config":{
                  "server_address":"%s","exports_mode":"%s","share_path":"/exports/k8s",
                  "worker_mount_path":"/data/k8s/nfs","storage_class":"nfs-storage"}}]}
                """.formatted(enabled, ip, mode);
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
