package io.kubefoundry.job;

import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JobExecutorTest {

    @Test
    void limitsNodeConcurrencyAndAggregatesSuccess() {
        AtomicInteger active = new AtomicInteger();
        AtomicInteger maximum = new AtomicInteger();
        try (JobExecutor executor = new JobExecutor(2, 10)) {
            List<JobExecutor.NodeWork> work = List.of(
                    nodeWork(1, active, maximum, false),
                    nodeWork(2, active, maximum, false),
                    nodeWork(3, active, maximum, false),
                    nodeWork(4, active, maximum, false));

            JobExecutor.ExecutionSummary summary = executor.executeNodes(work);

            assertThat(maximum).hasValue(2);
            assertThat(summary.status()).isEqualTo("success");
            assertThat(summary.results()).allMatch(result -> "success".equals(result.status()));
        }
    }

    @Test
    void reportsPartialNodeFailureWithoutCancelingSiblings() {
        AtomicInteger completed = new AtomicInteger();
        try (JobExecutor executor = new JobExecutor(3, 10)) {
            JobExecutor.ExecutionSummary summary = executor.executeNodes(List.of(
                    new JobExecutor.NodeWork(1, completed::incrementAndGet),
                    new JobExecutor.NodeWork(2, () -> { throw new IllegalStateException("节点命令失败"); }),
                    new JobExecutor.NodeWork(3, completed::incrementAndGet)));

            assertThat(summary.status()).isEqualTo("failed");
            assertThat(summary.results()).extracting(JobExecutor.NodeResult::status)
                    .containsExactly("success", "failed", "success");
            assertThat(summary.results().get(1).message()).contains("节点命令失败");
            assertThat(completed).hasValue(2);
        }
    }

    @Test
    void rejectsWhenJobQueueIsFull() throws Exception {
        CountDownLatch release = new CountDownLatch(1);
        try (JobExecutor executor = new JobExecutor(1, 1)) {
            executor.submit(() -> await(release));
            executor.submit(() -> await(release));

            assertThatThrownBy(() -> executor.submit(() -> { }))
                    .isInstanceOf(JobQueueFullException.class)
                    .hasMessage("任务队列已满，请稍后重试");
            release.countDown();
            assertThat(executor.awaitIdle(3, TimeUnit.SECONDS)).isTrue();
        }
    }

    private static JobExecutor.NodeWork nodeWork(
            long nodeId, AtomicInteger active, AtomicInteger maximum, boolean fail) {
        return new JobExecutor.NodeWork(nodeId, () -> {
            int current = active.incrementAndGet();
            maximum.accumulateAndGet(current, Math::max);
            try {
                Thread.sleep(40);
                if (fail) throw new IllegalStateException("failed");
            } finally {
                active.decrementAndGet();
            }
        });
    }

    private static void await(CountDownLatch latch) {
        try {
            latch.await();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
        }
    }
}
