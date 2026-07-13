package io.kubefoundry.job;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
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
    JobService service;

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

    private JobService.JobDefinition definition(String name) {
        Cluster cluster = clusters.saveAndFlush(new Cluster("transaction-" + name + System.nanoTime()));
        Node node = new Node(cluster);
        node.update("node-" + name, "10.0.0.1", "", "worker", "root", 22);
        node = nodes.saveAndFlush(node);
        return new JobService.JobDefinition(cluster.getId(), "install", List.of(
                new JobService.StepDefinition("事务任务", 1, 1, true, List.of(
                        new JobService.NodeOperation(node.getId(), () -> { })) )));
    }
}
