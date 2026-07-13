package io.kubefoundry.job;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.installer.InstallerAdmission;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:job-submission-transaction;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate"
})
class JobSubmissionTransactionTest {

    @Autowired
    ClusterRepository clusters;

    @Autowired
    NodeRepository nodes;

    @Autowired
    JobRepository jobs;

    @Autowired
    JobStepRepository steps;

    @Autowired
    JobStepNodeRepository stepNodes;

    @Autowired
    JobService service;

    @Autowired
    InstallerAdmission admission;

    @Autowired
    PlatformTransactionManager transactions;

    @MockBean
    JobExecutor executor;

    @AfterEach
    void cleanUp() {
        clusters.deleteAll();
    }

    @Test
    void queuesJobOnlyAfterTheOuterTransactionCommits() {
        JobService.JobDefinition definition = definition("commit");

        new TransactionTemplate(transactions).executeWithoutResult(status -> {
            service.submit(definition);
            verifyNoInteractions(executor);
        });

        verify(executor).submit(any());
    }

    @Test
    void rollbackDoesNotQueueOrPersistTheJob() {
        JobService.JobDefinition definition = definition("rollback");

        new TransactionTemplate(transactions).executeWithoutResult(status -> {
            service.submit(definition);
            status.setRollbackOnly();
        });

        verifyNoInteractions(executor);
        assertThat(jobs.count()).isZero();
    }

    @Test
    void afterCommitRejectionTerminatesPendingJobAndDoesNotBlockNewAdmission() {
        JobService.JobDefinition definition = definition("rejected");
        AtomicLong rejectedJobId = new AtomicLong();
        doThrow(new IllegalStateException("executor rejected password=must-not-persist"))
                .when(executor).submit(any());

        assertThatThrownBy(() -> new TransactionTemplate(transactions).executeWithoutResult(status ->
                rejectedJobId.set(service.submit(definition))))
                .isInstanceOf(IllegalStateException.class);

        Job rejected = jobs.findById(rejectedJobId.get()).orElseThrow();
        assertThat(rejected.getStatus()).isEqualTo("interrupted");
        JobStep rejectedStep = steps.findByJobIdOrderByOrder(rejected.getId()).get(0);
        assertThat(rejectedStep.getStatus()).isEqualTo("failed");
        assertThat(stepNodes.findByStepIdOrderById(rejectedStep.getId()))
                .singleElement()
                .satisfies(item -> {
                    assertThat(item.getStatus()).isEqualTo("failed");
                    assertThat(item.getMessage())
                            .isEqualTo("任务未进入执行队列")
                            .doesNotContain("password", "must-not-persist");
                });

        reset(executor);
        long replacementId = admission.submit(definition.clusterId(), () ->
                service.submit(definitionForCluster(definition.clusterId())));

        assertThat(replacementId).isNotEqualTo(rejectedJobId.get());
        assertThat(jobs.findById(replacementId).orElseThrow().getStatus()).isEqualTo("pending");
    }

    private JobService.JobDefinition definition(String name) {
        Cluster cluster = clusters.saveAndFlush(new Cluster("transaction-" + name + System.nanoTime()));
        Node node = new Node(cluster);
        node.update("node-" + name, "10.0.0.1", "", "worker", "root", 22);
        nodes.saveAndFlush(node);
        return definitionForCluster(cluster.getId());
    }

    private JobService.JobDefinition definitionForCluster(long clusterId) {
        Node node = nodes.findByClusterIdOrderById(clusterId).get(0);
        return new JobService.JobDefinition(clusterId, "install", List.of(
                new JobService.StepDefinition("事务任务", 1, 1, true, List.of(
                        new JobService.NodeOperation(node.getId(), () -> { })) )));
    }
}
