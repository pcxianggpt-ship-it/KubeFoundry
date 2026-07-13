package io.kubefoundry.job;

import jakarta.annotation.PreDestroy;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Future;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class JobExecutor implements AutoCloseable {

    private final ThreadPoolExecutor jobPool;
    private final ThreadPoolExecutor nodePool;
    private final AtomicInteger unfinishedJobs = new AtomicInteger();

    public JobExecutor(
            @Value("${kubefoundry.jobs.workers:5}") int workers,
            @Value("${kubefoundry.jobs.queue-capacity:100}") int queueCapacity) {
        if (workers < 1) throw new IllegalArgumentException("任务工作线程数必须大于 0");
        if (queueCapacity < 1) throw new IllegalArgumentException("任务队列容量必须大于 0");
        jobPool = newPool(workers, queueCapacity, "kf-job-");
        nodePool = newPool(workers, queueCapacity, "kf-node-");
    }

    public void submit(Runnable task) {
        if (task == null) throw new IllegalArgumentException("任务不能为空");
        unfinishedJobs.incrementAndGet();
        try {
            jobPool.execute(() -> {
                try {
                    task.run();
                } finally {
                    unfinishedJobs.decrementAndGet();
                }
            });
        } catch (java.util.concurrent.RejectedExecutionException exception) {
            unfinishedJobs.decrementAndGet();
            throw new JobQueueFullException();
        }
    }

    public ExecutionSummary executeNodes(List<NodeWork> workItems) {
        return executeNodes(workItems, Integer.MAX_VALUE, false);
    }

    public ExecutionSummary executeNodes(
            List<NodeWork> workItems, int maxWorkers, boolean failFast) {
        if (workItems == null || workItems.isEmpty()) {
            return new ExecutionSummary("success", List.of());
        }
        if (maxWorkers < 1) throw new IllegalArgumentException("节点并发数必须大于 0");
        List<NodeResult> results = new ArrayList<>(workItems.size());
        int offset = 0;
        while (offset < workItems.size()) {
            int end = Math.min(workItems.size(), offset + maxWorkers);
            List<Future<NodeResult>> futures = new ArrayList<>(end - offset);
            try {
                for (NodeWork item : workItems.subList(offset, end)) {
                    futures.add(nodePool.submit(() -> execute(item)));
                }
            } catch (java.util.concurrent.RejectedExecutionException exception) {
                futures.forEach(future -> future.cancel(true));
                throw new JobQueueFullException();
            }
            for (Future<NodeResult> future : futures) {
                try {
                    results.add(future.get());
                } catch (InterruptedException exception) {
                    Thread.currentThread().interrupt();
                    throw new IllegalStateException("等待节点任务时被中断", exception);
                } catch (ExecutionException exception) {
                    throw new IllegalStateException("节点任务执行器异常", exception.getCause());
                }
            }
            if (failFast && results.stream().anyMatch(result -> "failed".equals(result.status()))) break;
            offset = end;
        }
        String status = results.stream().allMatch(result -> "success".equals(result.status()))
                ? "success"
                : "failed";
        return new ExecutionSummary(status, List.copyOf(results));
    }

    public boolean awaitIdle(long timeout, TimeUnit unit) throws InterruptedException {
        long deadline = System.nanoTime() + unit.toNanos(timeout);
        while (System.nanoTime() < deadline) {
            if (unfinishedJobs.get() == 0
                    && jobPool.getActiveCount() == 0 && jobPool.getQueue().isEmpty()
                    && nodePool.getActiveCount() == 0 && nodePool.getQueue().isEmpty()) {
                return true;
            }
            Thread.sleep(10);
        }
        return false;
    }

    private static NodeResult execute(NodeWork item) {
        try {
            item.action().run();
            return new NodeResult(item.nodeId(), "success", "");
        } catch (Exception exception) {
            String message = exception.getMessage();
            return new NodeResult(item.nodeId(), "failed",
                    message == null || message.isBlank() ? exception.getClass().getSimpleName() : message);
        }
    }

    private static ThreadPoolExecutor newPool(
            int workers, int queueCapacity, String threadPrefix) {
        AtomicThreadFactory threadFactory = new AtomicThreadFactory(threadPrefix);
        return new ThreadPoolExecutor(
                workers,
                workers,
                0L,
                TimeUnit.MILLISECONDS,
                new ArrayBlockingQueue<>(queueCapacity),
                threadFactory,
                new ThreadPoolExecutor.AbortPolicy());
    }

    @Override
    @PreDestroy
    public void close() {
        jobPool.shutdownNow();
        nodePool.shutdownNow();
    }

    @FunctionalInterface
    public interface CheckedRunnable {
        void run() throws Exception;
    }

    public record NodeWork(long nodeId, CheckedRunnable action) {
        public NodeWork {
            if (action == null) throw new IllegalArgumentException("节点任务不能为空");
        }
    }

    public record NodeResult(long nodeId, String status, String message) {
    }

    public record ExecutionSummary(String status, List<NodeResult> results) {
    }

    private static final class AtomicThreadFactory implements ThreadFactory {
        private final String prefix;
        private final java.util.concurrent.atomic.AtomicInteger sequence =
                new java.util.concurrent.atomic.AtomicInteger();

        private AtomicThreadFactory(String prefix) {
            this.prefix = prefix;
        }

        @Override
        public Thread newThread(Runnable runnable) {
            Thread thread = new Thread(runnable, prefix + sequence.incrementAndGet());
            thread.setDaemon(true);
            return thread;
        }
    }
}
