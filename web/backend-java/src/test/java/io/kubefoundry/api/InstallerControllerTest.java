package io.kubefoundry.api;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.installer.PrecheckResult;
import io.kubefoundry.installer.PrecheckResultRepository;
import io.kubefoundry.installer.RemoteStepRunner;
import io.kubefoundry.installer.RuntimeSettings;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobExecutor;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import java.util.concurrent.TimeUnit;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:installer-controller;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate"
})
@AutoConfigureMockMvc
class InstallerControllerTest {

    @Autowired
    MockMvc mvc;

    @Autowired
    ClusterRepository clusters;

    @Autowired
    NodeRepository nodes;

    @Autowired
    JobRepository jobs;

    @Autowired
    PrecheckResultRepository precheckResults;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    JobExecutor executor;

    @MockBean
    RemoteStepRunner runner;

    Cluster cluster;
    Node node;

    @BeforeEach
    void setUp() {
        jdbc.update("delete from events");
        jdbc.update("delete from precheck_results");
        jdbc.update("delete from job_step_nodes");
        jdbc.update("delete from job_steps");
        jdbc.update("delete from jobs");
        jdbc.update("delete from cluster_settings");
        jdbc.update("delete from nodes");
        jdbc.update("delete from clusters");

        cluster = new Cluster("api-installer");
        cluster.update(null, null, "1.30.2", "10.244.0.0/16", "10.96.0.0/12",
                "registry", "10.0.0.9", 5000, null);
        cluster.markNodeTestStatus("success");
        cluster = clusters.saveAndFlush(cluster);
        node = new Node(cluster);
        node.update("cp-a", "10.0.0.1", "", "control_plane", "root", 22);
        node.completeNodeTest("kylin", "V10", "amd64");
        node = nodes.saveAndFlush(node);

        when(runner.run(anyLong(), any(), any(), any(), any(), any(RuntimeSettings.class)))
                .thenAnswer(invocation -> JobService.NodeOutcome.successful());
        when(runner.runCommandCapture(anyLong(), any(), any(), any(), any(), any()))
                .thenReturn(new RemoteStepRunner.CommandOutcome(
                        0, "__KF__USER=0\n__KF__CPU=4\n__KF__MEM=8192\n__KF__DISK=20480\n"
                                + "__KF__SWAP=0\n__KF__ARCH=x86_64\n__KF__BASH=present\n"
                                + "__KF__SYSTEMD=present\n__KF__HOSTNAME=cp-a\n"
                                + "__KF__PORT_6443=free\n__KF__PORT_2379=free\n"
                                + "__KF__PORT_2380=free\n__KF__PORT_10250=free\n"
                                + "__KF__PORT_10257=free\n__KF__PORT_10259=free\n",
                        "", "logs/cp-a.log"));
    }

    @Test
    void exposesPlanSettingsPrecheckResultsAndAcceptedInstallContracts() throws Exception {
        mvc.perform(get("/api/install-plan"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(14))
                .andExpect(jsonPath("$.items[13].key").value("web-verify-cluster-health"))
                .andExpect(jsonPath("$.items[13].target_scope").value("primary_control_plane"));

        mvc.perform(get("/api/settings"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.paths.k8s_home").value("/data/k8s_install"))
                .andExpect(jsonPath("$.env.containerd_root")
                        .value("/data/k8s_install/containerd-data"));

        mvc.perform(put("/api/settings")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"paths\":{\"k8s_home\":\"/srv/k8s\"}}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.paths.k8s_home").value("/srv/k8s"));
        mvc.perform(get("/api/settings"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.paths.k8s_home").value("/srv/k8s"));

        mvc.perform(put("/api/clusters/{id}/settings", cluster.getId())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"paths":{"k8s_home":"/opt/k8s"},
                                 "advanced":{"enable_ipv6_dual_stack":true}}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.paths.k8s_home").value("/opt/k8s"))
                .andExpect(jsonPath("$.advanced.enable_ipv6_dual_stack").value(true));

        Job job = new Job(cluster, "precheck");
        job.markSuccess();
        job = jobs.save(job);
        precheckResults.save(new PrecheckResult(cluster, job, node, "cpu", "CPU",
                "error", "pass", "CPU 核数: 4", ""));
        mvc.perform(get("/api/jobs/{jobId}/precheck-results", job.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].check_key").value("cpu"))
                .andExpect(jsonPath("$.items[0].hostname").value("cp-a"));

        mvc.perform(post("/api/clusters/{id}/install", cluster.getId())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"steps\":[\"13-install-k8s-deps\"]}"))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.job_id").isNumber())
                .andExpect(jsonPath("$.status").value("pending"));
        org.assertj.core.api.Assertions.assertThat(executor.awaitIdle(5, TimeUnit.SECONDS)).isTrue();
    }

    @Test
    void reportsUnknownStepUnknownClusterAndActiveJobWithStableErrorCodes() throws Exception {
        mvc.perform(post("/api/clusters/999999/install")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("CLUSTER_NOT_FOUND"));

        mvc.perform(post("/api/clusters/{id}/install", cluster.getId())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"steps\":[\"does-not-exist\"]}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.message").value(containsString("does-not-exist")));

        Job active = new Job(cluster, "install");
        active.markRunning();
        active = jobs.saveAndFlush(active);
        mvc.perform(post("/api/clusters/{id}/precheck", cluster.getId()))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("INSTALLER_JOB_ACTIVE"))
                .andExpect(jsonPath("$.job_id").value(active.getId()));
    }
}
