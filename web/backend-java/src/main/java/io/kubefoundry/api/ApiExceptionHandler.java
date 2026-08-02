package io.kubefoundry.api;

import io.kubefoundry.cluster.ClusterService.ResourceNotFoundException;
import io.kubefoundry.cluster.ClusterService.ClusterConfigurationLockedException;
import io.kubefoundry.job.JobQueueFullException;
import io.kubefoundry.job.JobNotFoundException;
import io.kubefoundry.installer.ActiveInstallerJobException;
import io.kubefoundry.installer.ResetConfirmationMismatchException;
import io.kubefoundry.ssh.NodeTestService.ActiveNodeTestException;
import io.kubefoundry.cluster.ClusterComponentService.ComponentConfigurationException;
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

    @ExceptionHandler(JobNotFoundException.class)
    public ResponseEntity<Map<String, String>> jobNotFound(JobNotFoundException exception) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("code", "JOB_NOT_FOUND", "message", exception.getMessage()));
    }

    @ExceptionHandler({IllegalArgumentException.class, HttpMessageNotReadableException.class})
    public ResponseEntity<Map<String, String>> validation(Exception exception) {
        if (exception instanceof ComponentConfigurationException component) {
            return ResponseEntity.badRequest().body(Map.of(
                    "code", component.code(), "message", component.getMessage()));
        }
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

    @ExceptionHandler(ActiveNodeTestException.class)
    public ResponseEntity<Map<String, Object>> activeNodeTest(ActiveNodeTestException exception) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of(
                "code", "NODE_TEST_ACTIVE",
                "message", exception.getMessage(),
                "job_id", exception.jobId()));
    }

    @ExceptionHandler(ActiveInstallerJobException.class)
    public ResponseEntity<Map<String, Object>> activeInstallerJob(
            ActiveInstallerJobException exception) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of(
                "code", "INSTALLER_JOB_ACTIVE",
                "message", exception.getMessage(),
                "job_id", exception.jobId()));
    }

    @ExceptionHandler(ResetConfirmationMismatchException.class)
    public ResponseEntity<Map<String, String>> resetConfirmation(
            ResetConfirmationMismatchException exception) {
        return ResponseEntity.badRequest().body(Map.of(
                "code", "RESET_CONFIRMATION_MISMATCH",
                "message", exception.getMessage()));
    }

    @ExceptionHandler(ClusterConfigurationLockedException.class)
    public ResponseEntity<Map<String, String>> configurationLocked(
            ClusterConfigurationLockedException exception) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of(
                "code", "CLUSTER_CONFIGURATION_LOCKED",
                "message", exception.getMessage()));
    }
}
