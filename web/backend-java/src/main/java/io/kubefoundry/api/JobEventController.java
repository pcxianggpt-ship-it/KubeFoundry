package io.kubefoundry.api;

import io.kubefoundry.job.EventService;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
@RequestMapping("/api/jobs")
public class JobEventController {

    private final EventService events;

    public JobEventController(EventService events) {
        this.events = events;
    }

    @GetMapping(value = "/{jobId}/events", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter events(
            @PathVariable long jobId,
            @RequestHeader(name = "Last-Event-ID", required = false) Long lastEventId,
            @RequestParam(name = "last_id", required = false) Long queryLastId) {
        long afterId = lastEventId != null ? lastEventId : queryLastId == null ? 0 : queryLastId;
        return events.subscribe(jobId, afterId);
    }
}
