package io.kubefoundry.api;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.EventService;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobEvent;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobStep;
import io.kubefoundry.job.JobStepNode;
import io.kubefoundry.job.JobStepNodeRepository;
import io.kubefoundry.job.JobStepRepository;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:job-events;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate",
        "kubefoundry.jobs.heartbeat-ms=20"
})
@AutoConfigureMockMvc
class JobEventApiTest {

    @Autowired
    MockMvc mvc;

    @Autowired
    ClusterRepository clusters;

    @Autowired
    JobRepository jobs;

    @Autowired
    EventService events;

    @Autowired
    NodeRepository nodes;

    @Autowired
    JobStepRepository steps;

    @Autowired
    JobStepNodeRepository stepNodes;

    @Test
    void replaysEventsInOrderAfterLastEventId() throws Exception {
        Job job = newJob("replay");
        JobEvent first = events.publish(job.getId(), "job.status", Map.of("status", "running"));
        JobEvent second = events.publish(job.getId(), "step.status", Map.of("status", "running"));
        JobEvent third = events.publish(job.getId(), "job.status", Map.of("status", "success"));

        MvcResult started = mvc.perform(get("/api/jobs/{jobId}/events", job.getId())
                        .header("Last-Event-ID", first.getId()))
                .andExpect(request().asyncStarted())
                .andReturn();
        MvcResult completed = mvc.perform(asyncDispatch(started))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith("text/event-stream"))
                .andReturn();

        String body = completed.getResponse().getContentAsString();
        assertThat(body).doesNotContain("id:" + first.getId());
        assertThat(body).contains("id:" + second.getId(), "id:" + third.getId());
        assertThat(body.indexOf("id:" + second.getId()))
                .isLessThan(body.indexOf("id:" + third.getId()));
    }

    @Test
    void sendsHeartbeatWhileWaitingForLiveTerminalEvent() throws Exception {
        Job job = newJob("heartbeat");
        MvcResult started = mvc.perform(get("/api/jobs/{jobId}/events", job.getId()))
                .andExpect(request().asyncStarted())
                .andReturn();

        Thread.sleep(80);
        events.publish(job.getId(), "job.status", Map.of("status", "success"));

        MvcResult completed = mvc.perform(asyncDispatch(started))
                .andExpect(status().isOk())
                .andReturn();
        assertThat(completed.getResponse().getContentAsString()).contains("heartbeat", "job.status");
    }

    @Test
    void returnsJobDtoWithOpenInViewDisabled() throws Exception {
        Job job = newJob("dto");
        job.markRunning();
        job.markSuccess();
        job = jobs.save(job);

        mvc.perform(get("/api/jobs/{jobId}", job.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(job.getId()))
                .andExpect(jsonPath("$.cluster_id").value(job.getCluster().getId()))
                .andExpect(jsonPath("$.job_type").value("node_test"))
                .andExpect(jsonPath("$.created_at").isNotEmpty())
                .andExpect(jsonPath("$.started_at").isNotEmpty())
                .andExpect(jsonPath("$.finished_at").isNotEmpty());
    }

    @Test
    void returnsStepNodeDtoWithOpenInViewDisabled() throws Exception {
        Job job = newJob("step-dto");
        Node node = new Node(job.getCluster());
        node.update("node-a", "10.0.0.1", "", "worker", "root", 22);
        node = nodes.save(node);
        JobStep step = steps.save(new JobStep(job, "节点测试", 1));
        step.markSkipped("COMPONENT_GROUP_PREVIOUS_STEP_FAILED");
        step = steps.save(step);
        stepNodes.save(new JobStepNode(step, node));

        mvc.perform(get("/api/jobs/{jobId}/steps", job.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].status_reason")
                        .value("COMPONENT_GROUP_PREVIOUS_STEP_FAILED"))
                .andExpect(jsonPath("$.items[0].nodes[0].hostname").value("node-a"));
    }

    @Test
    void rejectsJobLookupThroughAnotherCluster() throws Exception {
        Job job = newJob("scoped");
        Cluster other = clusters.save(new Cluster("event-other-" + System.nanoTime()));

        mvc.perform(get("/api/clusters/{clusterId}/jobs/{jobId}", other.getId(), job.getId()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("CLUSTER_JOB_NOT_FOUND"));

        mvc.perform(get("/api/clusters/{clusterId}/jobs/{jobId}", job.getCluster().getId(), job.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(job.getId()));
    }

    private Job newJob(String suffix) {
        Cluster cluster = clusters.save(new Cluster("event-" + suffix + "-" + System.nanoTime()));
        return jobs.save(new Job(cluster, "node_test"));
    }
}
