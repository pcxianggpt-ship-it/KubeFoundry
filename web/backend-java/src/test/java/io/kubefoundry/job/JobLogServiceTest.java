package io.kubefoundry.job;

import io.kubefoundry.cluster.Node;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class JobLogServiceTest {

    @TempDir
    Path tempDirectory;

    @Test
    void readsOnlyJobLogFilesAndRedactsSensitiveValues() throws Exception {
        long jobId = 5L;
        Path log = tempDirectory.resolve("jobs/5/logs/install/cp-1.log");
        Files.createDirectories(log.getParent());
        Files.writeString(log, "ready\ntoken: abc123\n--password value\n", StandardCharsets.UTF_8);

        JobLogService service = service(jobId, log);
        List<JobLogService.LogEntry> entries = service.list(jobId);

        assertThat(entries).extracting(JobLogService.LogEntry::message)
                .containsExactly("ready", "token: [REDACTED]", "--password [REDACTED]")
                .doesNotContain("abc123", "value");
    }

    @Test
    void ignoresPersistedPathsOutsideTheJobLogDirectory() throws Exception {
        Path outside = tempDirectory.resolve("outside.log");
        Files.writeString(outside, "must-not-leak", StandardCharsets.UTF_8);

        assertThat(service(6L, outside).list(6L)).isEmpty();
    }

    @Test
    void removesPrivateKeyMarkersAndJsonSecrets() {
        assertThat(JobLogService.sanitize("-----BEGIN PRIVATE KEY-----")).isEqualTo("[REDACTED]");
        assertThat(JobLogService.sanitize("{\"password\":\"secret-value\"}"))
                .doesNotContain("secret-value")
                .contains("[REDACTED]");
    }

    private JobLogService service(long jobId, Path logPath) {
        JobService jobs = mock(JobService.class);
        JobStep step = mock(JobStep.class);
        JobStepNode item = mock(JobStepNode.class);
        Node node = mock(Node.class);
        when(jobs.get(jobId)).thenReturn(mock(Job.class));
        when(jobs.listSteps(jobId)).thenReturn(List.of(step));
        when(step.getId()).thenReturn(12L);
        when(step.getName()).thenReturn("安装 containerd");
        when(jobs.listStepNodes(12L)).thenReturn(List.of(item));
        when(item.getId()).thenReturn(20L);
        when(item.getLogPath()).thenReturn(logPath.toString());
        when(item.getNode()).thenReturn(node);
        when(node.getId()).thenReturn(30L);
        when(node.getHostname()).thenReturn("cp-1");
        return new JobLogService(jobs, tempDirectory.toString());
    }
}
