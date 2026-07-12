package io.kubefoundry.job;

import jakarta.annotation.PreDestroy;
import java.io.IOException;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@Service
public class EventService implements AutoCloseable {

    private static final Set<String> TERMINAL_STATUSES =
            Set.of("success", "failed", "interrupted", "canceled");

    private final JobRepository jobs;
    private final JobEventRepository events;
    private final Map<Long, CopyOnWriteArrayList<SseEmitter>> subscribers = new ConcurrentHashMap<>();
    private final Map<Long, Object> jobLocks = new ConcurrentHashMap<>();
    private final ScheduledExecutorService heartbeatScheduler;

    public EventService(
            JobRepository jobs,
            JobEventRepository events,
            @Value("${kubefoundry.jobs.heartbeat-ms:15000}") long heartbeatMilliseconds) {
        if (heartbeatMilliseconds < 1) throw new IllegalArgumentException("SSE 心跳间隔必须大于 0");
        this.jobs = jobs;
        this.events = events;
        ThreadFactory factory = runnable -> {
            Thread thread = new Thread(runnable, "kf-sse-heartbeat");
            thread.setDaemon(true);
            return thread;
        };
        heartbeatScheduler = Executors.newSingleThreadScheduledExecutor(factory);
        heartbeatScheduler.scheduleAtFixedRate(
                this::sendHeartbeats,
                heartbeatMilliseconds,
                heartbeatMilliseconds,
                TimeUnit.MILLISECONDS);
    }

    public JobEvent publish(long jobId, String eventType, Map<String, Object> payload) {
        if (eventType == null || eventType.isBlank()) throw new IllegalArgumentException("事件类型不能为空");
        if (payload == null) throw new IllegalArgumentException("事件内容不能为空");
        synchronized (lockFor(jobId)) {
            Job job = requireJob(jobId);
            JobEvent event = events.saveAndFlush(new JobEvent(job, eventType, payload));
            boolean terminal = isTerminal(event);
            for (SseEmitter emitter : subscribers.getOrDefault(jobId, new CopyOnWriteArrayList<>())) {
                if (send(emitter, event) && terminal) emitter.complete();
            }
            if (terminal) subscribers.remove(jobId);
            return event;
        }
    }

    public List<JobEvent> eventsAfter(long jobId, long afterId) {
        requireJob(jobId);
        return events.findTop100ByJobIdAndIdGreaterThanOrderById(jobId, afterId);
    }

    public SseEmitter subscribe(long jobId, long afterId) {
        if (afterId < 0) throw new IllegalArgumentException("最后事件 ID 不能小于 0");
        SseEmitter emitter = new SseEmitter(0L);
        synchronized (lockFor(jobId)) {
            List<JobEvent> replay = eventsAfter(jobId, afterId);
            boolean terminal = false;
            for (JobEvent event : replay) {
                if (!send(emitter, event)) return emitter;
                terminal = terminal || isTerminal(event);
            }
            if (terminal) {
                emitter.complete();
                return emitter;
            }
            CopyOnWriteArrayList<SseEmitter> jobSubscribers =
                    subscribers.computeIfAbsent(jobId, ignored -> new CopyOnWriteArrayList<>());
            jobSubscribers.add(emitter);
            Runnable cleanup = () -> removeSubscriber(jobId, emitter);
            emitter.onCompletion(cleanup);
            emitter.onTimeout(cleanup);
            emitter.onError(ignored -> cleanup.run());
            return emitter;
        }
    }

    private void sendHeartbeats() {
        subscribers.forEach((jobId, emitters) -> emitters.forEach(emitter -> {
            try {
                emitter.send(SseEmitter.event().comment("heartbeat"));
            } catch (IOException | RuntimeException exception) {
                removeSubscriber(jobId, emitter);
            }
        }));
    }

    private boolean send(SseEmitter emitter, JobEvent event) {
        try {
            emitter.send(SseEmitter.event()
                    .id(Long.toString(event.getId()))
                    .name(event.getType())
                    .data(EventEnvelope.from(event)));
            return true;
        } catch (IOException | RuntimeException exception) {
            emitter.completeWithError(exception);
            return false;
        }
    }

    private void removeSubscriber(long jobId, SseEmitter emitter) {
        CopyOnWriteArrayList<SseEmitter> emitters = subscribers.get(jobId);
        if (emitters == null) return;
        emitters.remove(emitter);
        if (emitters.isEmpty()) subscribers.remove(jobId, emitters);
    }

    private Job requireJob(long jobId) {
        return jobs.findById(jobId)
                .orElseThrow(() -> new IllegalArgumentException("任务不存在: " + jobId));
    }

    private Object lockFor(long jobId) {
        return jobLocks.computeIfAbsent(jobId, ignored -> new Object());
    }

    private static boolean isTerminal(JobEvent event) {
        Object status = event.getPayload().get("status");
        return "job.status".equals(event.getType())
                && status instanceof String value
                && TERMINAL_STATUSES.contains(value);
    }

    @Override
    @PreDestroy
    public void close() {
        heartbeatScheduler.shutdownNow();
        subscribers.values().forEach(emitters -> emitters.forEach(SseEmitter::complete));
        subscribers.clear();
        jobLocks.clear();
    }

    public record EventEnvelope(
            long id,
            long jobId,
            String eventType,
            Map<String, Object> payload,
            LocalDateTime createdAt) {
        static EventEnvelope from(JobEvent event) {
            return new EventEnvelope(event.getId(), event.getJob().getId(), event.getType(),
                    event.getPayload(), event.getCreatedAt());
        }
    }
}
