package io.kubefoundry.api;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import io.kubefoundry.job.JobStep;
import io.kubefoundry.job.JobStepNode;
import io.kubefoundry.job.JobStepNodeRepository;
import io.kubefoundry.job.JobStepRepository;
import io.kubefoundry.installer.ComponentInstallService;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.mockito.Mockito.when;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:api-contract;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate",
        "kubefoundry.data-dir=target/api-contract-data"
})
@AutoConfigureMockMvc
class ApiContractTest {

    @Autowired MockMvc mvc;
    @Autowired JdbcTemplate jdbc;
    @Autowired ClusterRepository clusters;
    @Autowired NodeRepository nodes;
    @Autowired JobRepository jobs;
    @Autowired JobStepRepository steps;
    @Autowired JobStepNodeRepository stepNodes;
    @MockBean ComponentInstallService componentInstalls;

    private final Path dataDirectory = Path.of("target/api-contract-data").toAbsolutePath();
    private Cluster cluster;
    private Job job;

    @BeforeEach
    void setUp() throws Exception {
        jdbc.update("delete from events");
        jdbc.update("delete from precheck_results");
        jdbc.update("delete from job_step_nodes");
        jdbc.update("delete from job_steps");
        jdbc.update("delete from jobs");
        jdbc.update("delete from cluster_settings");
        jdbc.update("delete from nodes");
        jdbc.update("delete from clusters");

        cluster = new Cluster("contract-cluster");
        cluster.update("API contract", null, "1.30.14", "10.244.0.0/16", "10.96.0.0/16",
                "registry", "10.0.0.9", 5000, null);
        cluster = clusters.saveAndFlush(cluster);
        when(componentInstalls.start(cluster.getId())).thenReturn(55L);

        Node node = new Node(cluster);
        node.update("cp-1", "10.0.0.1", "", null, "root", 22);
        node.replaceRoles(java.util.Set.of("control_plane", "registry"));
        node = nodes.saveAndFlush(node);

        job = new Job(cluster, "install");
        job.markRunning();
        job = jobs.saveAndFlush(job);
        JobStep step = steps.saveAndFlush(new JobStep(job, "安装 containerd", 1));

        Path log = dataDirectory.resolve("jobs").resolve(job.getId().toString())
                .resolve("logs").resolve("install-containerd").resolve("cp-1.log");
        Files.createDirectories(log.getParent());
        Files.writeString(log, "正常输出\npassword=HiddenValue\n", StandardCharsets.UTF_8);
        JobStepNode item = new JobStepNode(step, node);
        item.complete(new JobService.NodeOutcome(true, 0, "执行成功", log.toString()));
        stepNodes.saveAndFlush(item);
    }

    @Test
    void exposesHealthClusterNodeSettingsInstallerAndJobContracts() throws Exception {
        mvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("ok"))
                .andExpect(jsonPath("$.version").value("0.3.0"));
        mvc.perform(get("/api/clusters"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(cluster.getId()))
                .andExpect(jsonPath("$.items[0].kubernetes_work_dir").isString())
                .andExpect(content().string(not(containsString("pod_subnet"))))
                .andExpect(content().string(not(containsString("service_subnet"))))
                .andExpect(content().string(not(containsString("registry_hostname"))))
                .andExpect(content().string(not(containsString("registry_ip"))))
                .andExpect(content().string(not(containsString("registry_port"))));
        mvc.perform(get("/api/clusters/{id}/nodes", cluster.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].hostname").value("cp-1"))
                .andExpect(jsonPath("$.items[0].roles.length()").value(2))
                .andExpect(jsonPath("$.items[0].roles[0]").value("control_plane"))
                .andExpect(content().string(not(containsString("\"role\":"))))
                .andExpect(content().string(not(containsString("password_ciphertext"))));
        mvc.perform(get("/api/settings"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.paths.install_media").isString());
        mvc.perform(get("/api/clusters/{id}/settings", cluster.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.env.containerd_root").isString());
        mvc.perform(get("/api/clusters/{id}/install-plan", cluster.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(15));
        mvc.perform(get("/api/jobs").param("cluster_id", cluster.getId().toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].job_type").value("install"));
        mvc.perform(get("/api/jobs/{id}", job.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.cluster_id").value(cluster.getId()));
        mvc.perform(get("/api/jobs/{id}/steps", job.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].nodes[0].hostname").value("cp-1"));

        mvc.perform(post("/api/clusters/{id}/precheck", cluster.getId()))
                .andExpect(status().isBadRequest());
        mvc.perform(post("/api/clusters/{id}/install", cluster.getId())
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isBadRequest());
        mvc.perform(post("/api/clusters/{id}/components/install", cluster.getId()))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.job_id").value(55));
    }

    @Test
    void returnsStructuredRedactedLogsAndRejectsUnknownJob() throws Exception {
        mvc.perform(get("/api/jobs/{id}/logs", job.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].stage_name").value("安装 containerd"))
                .andExpect(jsonPath("$.items[0].hostname").value("cp-1"))
                .andExpect(jsonPath("$.items[0].message").value("正常输出"))
                .andExpect(jsonPath("$.items[1].message").value(containsString("[REDACTED]")))
                .andExpect(content().string(not(containsString("HiddenValue"))));

        mvc.perform(get("/api/jobs/999999/logs"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("JOB_NOT_FOUND"));
    }
}
