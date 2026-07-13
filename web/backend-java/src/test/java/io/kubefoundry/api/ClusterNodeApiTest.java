package io.kubefoundry.api;

import io.kubefoundry.credential.AesGcmCredentialCipher;
import javax.crypto.spec.SecretKeySpec;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.containsString;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:cluster-api;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.jpa.hibernate.ddl-auto=validate"
})
@AutoConfigureMockMvc
@Import(ClusterNodeApiTest.TestCredentialConfiguration.class)
class ClusterNodeApiTest {

    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcTemplate jdbc;

    @BeforeEach
    void clearDatabase() {
        jdbc.update("delete from nodes");
        jdbc.update("delete from clusters");
    }

    @Test
    void createsReusesUpdatesListsAndDeletesCluster() throws Exception {
        long id = createCluster("production");

        mvc.perform(post("/api/clusters")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"production","description":"updated","k8s_version":"1.30.2"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(id))
                .andExpect(jsonPath("$.description").value("updated"));

        mvc.perform(get("/api/clusters"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1));

        mvc.perform(put("/api/clusters/{id}", id)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"description\":\"changed\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.description").value("changed"));

        mvc.perform(delete("/api/clusters/{id}", id))
                .andExpect(status().isNoContent());

        mvc.perform(get("/api/clusters/{id}", id))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("CLUSTER_NOT_FOUND"))
                .andExpect(jsonPath("$.message").value(containsString("集群")));
    }

    @Test
    void encryptsPasswordAndNeverReturnsCredentialMaterial() throws Exception {
        long clusterId = createCluster("credentials");

        mvc.perform(post("/api/clusters/{id}/nodes", clusterId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(nodeJson("node-1", "192.168.1.11", "Secret123")))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.has_password").value(true))
                .andExpect(jsonPath("$.is_draft").value(false))
                .andExpect(jsonPath("$.node_test_status").value("pending"))
                .andExpect(content().string(not(containsString("Secret123"))))
                .andExpect(content().string(not(containsString("ciphertext"))))
                .andExpect(content().string(not(containsString("password_iv"))));

        Map<String, Object> credential = jdbc.queryForMap(
                "select password_ciphertext, password_iv, password_version from nodes where cluster_id=?",
                clusterId);
        assertThat(credential.get("password_ciphertext")).isNotEqualTo("Secret123");
        assertThat(credential.get("password_iv")).isNotNull();
        assertThat(credential.get("password_version")).isEqualTo(1);
    }

    @Test
    void emptyPasswordUpdateKeepsCredentialAndMarksTestStale() throws Exception {
        long clusterId = createCluster("update-node");
        long nodeId = createNode(clusterId, "node-1", "192.168.1.11", "Secret123");

        mvc.perform(put("/api/nodes/{id}", nodeId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"hostname":"node-1","ip":"192.168.1.12","role":"worker",
                                 "ssh_user":"root","ssh_port":22,"password":""}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.has_password").value(true))
                .andExpect(jsonPath("$.ip").value("192.168.1.12"))
                .andExpect(jsonPath("$.node_test_status").value("stale"));
    }

    @Test
    void passwordUpdateMarksTestStaleButKeepsTrustedHostFingerprint() throws Exception {
        long clusterId = createCluster("fingerprint-on-password-update");
        long nodeId = createNode(clusterId, "node-1", "192.168.1.11", "Secret123");
        jdbc.update("update nodes set host_fingerprint=? where id=?", "SHA256:trusted", nodeId);

        mvc.perform(put("/api/nodes/{id}", nodeId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"password\":\"ChangedSecret456\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.node_test_status").value("stale"));

        assertThat(jdbc.queryForObject(
                "select host_fingerprint from nodes where id=?", String.class, nodeId))
                .isEqualTo("SHA256:trusted");
    }

    @Test
    void copiedNodeKeepsCredentialButResetsHostBindingAndBecomesFormalAfterEdit() throws Exception {
        long clusterId = createCluster("copy-node");
        long sourceId = createNode(clusterId, "node-1", "192.168.1.11", "Secret123");

        String body = mvc.perform(post("/api/clusters/{id}/nodes/copy", clusterId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"node_ids\":[" + sourceId + "]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].has_password").value(true))
                .andExpect(jsonPath("$.items[0].hostname").value(""))
                .andExpect(jsonPath("$.items[0].ip").value(""))
                .andExpect(jsonPath("$.items[0].is_draft").value(true))
                .andExpect(jsonPath("$.items[0].node_test_status").value("pending"))
                .andReturn().getResponse().getContentAsString();

        long copiedId = Long.parseLong(body.replaceAll(".*\\\"id\\\":(\\d+).*", "$1"));
        mvc.perform(put("/api/nodes/{id}", copiedId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"hostname":"node-2","ip":"192.168.1.12","role":"worker",
                                 "ssh_user":"root","ssh_port":22}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.is_draft").value(false))
                .andExpect(jsonPath("$.has_password").value(true));
    }

    @Test
    void validatesNodeFieldsAndMissingResourcesWithChineseMessages() throws Exception {
        long clusterId = createCluster("validation");

        mvc.perform(post("/api/clusters/{id}/nodes", clusterId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"hostname":"","ip":"bad","role":"invalid","ssh_user":"","ssh_port":70000}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.message").value(containsString("节点配置")));

        mvc.perform(delete("/api/nodes/999999"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NODE_NOT_FOUND"))
                .andExpect(jsonPath("$.message").value(containsString("节点")));
    }

    private long createCluster(String name) throws Exception {
        String body = mvc.perform(post("/api/clusters")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"k8s_version\":\"1.30.2\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return Long.parseLong(body.replaceAll(".*\\\"id\\\":(\\d+).*", "$1"));
    }

    private long createNode(long clusterId, String hostname, String ip, String password) throws Exception {
        String body = mvc.perform(post("/api/clusters/{id}/nodes", clusterId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(nodeJson(hostname, ip, password)))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return Long.parseLong(body.replaceAll(".*\\\"id\\\":(\\d+).*", "$1"));
    }

    private static String nodeJson(String hostname, String ip, String password) {
        return """
                {"hostname":"%s","ip":"%s","role":"worker","ssh_user":"root",
                 "ssh_port":22,"password":"%s"}
                """.formatted(hostname, ip, password);
    }

    @TestConfiguration
    static class TestCredentialConfiguration {
        @Bean
        @Primary
        AesGcmCredentialCipher testCredentialCipher() {
            return new AesGcmCredentialCipher(new SecretKeySpec(new byte[32], "AES"));
        }
    }
}
