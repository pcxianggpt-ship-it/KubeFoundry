package io.kubefoundry.api;

import io.kubefoundry.cluster.ClusterService.ResourceNotFoundException;
import io.kubefoundry.job.JobQueueFullException;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<Map<String, String>> notFound(ResourceNotFoundException exception) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("code", exception.code(), "message", exception.getMessage()));
    }

    @ExceptionHandler({IllegalArgumentException.class, HttpMessageNotReadableException.class})
    public ResponseEntity<Map<String, String>> validation(Exception exception) {
        String detail = exception instanceof IllegalArgumentException
                ? exception.getMessage() : "请求 JSON 格式无效";
        return ResponseEntity.badRequest().body(Map.of(
                "code", "VALIDATION_ERROR",
                "message", "节点配置校验失败：" + detail));
    }

    @ExceptionHandler(JobQueueFullException.class)
    public ResponseEntity<Map<String, String>> queueFull(JobQueueFullException exception) {
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS).body(Map.of(
                "code", "JOB_QUEUE_FULL",
                "message", exception.getMessage()));
    }
}
