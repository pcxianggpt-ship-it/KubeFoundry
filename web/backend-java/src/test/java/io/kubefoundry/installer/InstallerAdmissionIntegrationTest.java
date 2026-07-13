package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.JobExecutor;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:installer-admission;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate"
})
class InstallerAdmissionIntegrationTest {

    @Autowired
    ClusterRepository clusters;

    @Autowired
    NodeRepository nodes;

    @Autowired
    JobRepository jobs;

    @Autowired
    JobService jobService;

    @Autowired
    PlatformTransactionManager transactions;

    @MockBean
    JobExecutor executor;

    @AfterEach
    void cleanUp() {
        clusters.deleteAll();
    }

    @Test
    void independentAdmissionInstancesCreateOneActiveJobAndReturnItsIdToTheLoser() throws Exception {
        Cluster cluster = cluster("concurrent");
        InstallerAdmission first = admission();
        InstallerAdmission second = admission();
        CountDownLatch ready = new CountDownLatch(2);
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService callers = Executors.newFixedThreadPool(2);
        try {
            Future<AdmissionResult> one = callers.submit(() -> submit(first, cluster.getId(), ready, start));
            Future<AdmissionResult> two = callers.submit(() -> submit(second, cluster.getId(), ready, start));
            assertThat(ready.await(5, TimeUnit.SECONDS)).isTrue();
            start.countDown();

            AdmissionResult firstResult = one.get(5, TimeUnit.SECONDS);
            AdmissionResult secondResult = two.get(5, TimeUnit.SECONDS);
            long createdJobId = firstResult.created() ? firstResult.jobId() : secondResult.jobId();
            long rejectedJobId = firstResult.created() ? secondResult.jobId() : firstResult.jobId();

            assertThat(firstResult.created()).isNotEqualTo(secondResult.created());
            assertThat(rejectedJobId).isEqualTo(createdJobId);
            assertThat(jobs.findByClusterIdOrderByIdDesc(cluster.getId()))
                    .extracting(job -> job.getStatus())
                    .containsExactly("pending");
        } finally {
            callers.shutdownNow();
        }
    }

    @Test
    void failedSubmissionReleasesTheDatabaseLockForANewAdmissionInstance() {
        Cluster cluster = cluster("failure");
        InstallerAdmission first = admission();

        assertThatThrownBy(() -> first.submit(cluster.getId(), () -> {
            throw new IllegalStateException("提交失败");
        })).isInstanceOf(IllegalStateException.class);

        long jobId = admission().submit(cluster.getId(), () -> jobService.submit(definition(cluster)));

        assertThat(jobs.findById(jobId)).isPresent();
    }

    @Test
    void restartedAdmissionDoesNotTreatInterruptedJobsAsPermanentLocks() {
        Cluster cluster = cluster("restart");
        long interruptedJobId = admission().submit(
                cluster.getId(), () -> jobService.submit(definition(cluster)));
        io.kubefoundry.job.Job interrupted = jobs.findById(interruptedJobId).orElseThrow();
        interrupted.markRunning();
        jobs.saveAndFlush(interrupted);

        assertThat(jobService.recoverInterruptedJobs()).isEqualTo(1);
        long replacementJobId = admission().submit(
                cluster.getId(), () -> jobService.submit(definition(cluster)));

        assertThat(replacementJobId).isNotEqualTo(interruptedJobId);
    }

    private AdmissionResult submit(
            InstallerAdmission admission, long clusterId, CountDownLatch ready, CountDownLatch start)
            throws Exception {
        ready.countDown();
        assertThat(start.await(5, TimeUnit.SECONDS)).isTrue();
        try {
            return new AdmissionResult(true, admission.submit(clusterId, () -> jobService.submit(definition(clusterId))));
        } catch (ActiveInstallerJobException exception) {
            return new AdmissionResult(false, exception.jobId());
        }
    }

    private InstallerAdmission admission() {
        return new InstallerAdmission(clusters, jobs, new TransactionTemplate(transactions));
    }

    private Cluster cluster(String name) {
        Cluster cluster = clusters.saveAndFlush(new Cluster("admission-" + name + System.nanoTime()));
        Node node = new Node(cluster);
        node.update("node-" + name, "10.0.0.1", "", "worker", "root", 22);
        nodes.saveAndFlush(node);
        return cluster;
    }

    private JobService.JobDefinition definition(long clusterId) {
        Cluster cluster = clusters.findById(clusterId).orElseThrow();
        return definition(cluster);
    }

    private JobService.JobDefinition definition(Cluster cluster) {
        Node node = nodes.findByClusterIdOrderById(cluster.getId()).get(0);
        return new JobService.JobDefinition(cluster.getId(), "install", List.of(
                new JobService.StepDefinition("准入任务", 1, 1, true, List.of(
                        new JobService.NodeOperation(node.getId(), () -> { })) )));
    }

    private record AdmissionResult(boolean created, long jobId) {
    }
}
