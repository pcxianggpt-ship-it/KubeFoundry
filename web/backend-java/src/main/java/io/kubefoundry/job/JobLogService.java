package io.kubefoundry.job;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class JobLogService {

    private static final int MAX_LOG_BYTES = 2 * 1024 * 1024;
    private static final int MAX_LOG_LINES = 2_000;
    private static final Pattern SENSITIVE_ASSIGNMENT = Pattern.compile(
            "(?i)(password|passwd|passphrase|token|secret|credential|private[_ -]?key)"
                    + "([\\\"']?\\s*[:=]\\s*[\\\"']?)([^\\s,\\\"'}]+)");
    private static final Pattern SENSITIVE_ARGUMENT = Pattern.compile(
            "(?i)(--?(?:password|passwd|passphrase|token|secret|credential)\\s+)\\S+");

    private final JobService jobs;
    private final Path dataDirectory;

    public JobLogService(JobService jobs, @Value("${kubefoundry.data-dir:data}") String dataDirectory) {
        this.jobs = jobs;
        this.dataDirectory = Path.of(dataDirectory).toAbsolutePath().normalize();
    }

    public List<LogEntry> list(long jobId) {
        jobs.get(jobId);
        List<LogEntry> result = new ArrayList<>();
        for (JobStep step : jobs.listSteps(jobId)) {
            for (JobStepNode item : jobs.listStepNodes(step.getId())) {
                append(result, jobId, step, item);
            }
        }
        return result;
    }

    private void append(List<LogEntry> target, long jobId, JobStep step, JobStepNode item) {
        Path candidate = safeLogPath(jobId, item.getLogPath());
        List<String> lines = readLog(candidate);
        if (lines.isEmpty()) return;
        String createdAt = lastModified(candidate);
        for (int index = 0; index < lines.size(); index++) {
            String message = sanitize(lines.get(index));
            if (message.isBlank()) continue;
            target.add(new LogEntry(
                    item.getId() + "-" + (index + 1), step.getId(), step.getName(),
                    item.getNode().getId(), item.getNode().getHostname(), createdAt, message));
        }
    }

    private List<String> readLog(Path candidate) {
        if (candidate == null) return List.of();
        try {
            long size = Files.size(candidate);
            int readSize = (int) Math.min(size, MAX_LOG_BYTES);
            byte[] bytes;
            try (InputStream input = Files.newInputStream(candidate)) {
                if (size > readSize) input.skipNBytes(size - readSize);
                bytes = input.readNBytes(readSize);
            }
            String content = new String(bytes, StandardCharsets.UTF_8);
            if (size > readSize) {
                int firstNewline = content.indexOf('\n');
                content = firstNewline >= 0 ? content.substring(firstNewline + 1) : "";
            }
            List<String> lines = Arrays.asList(content.split("\\R", -1));
            int from = Math.max(0, lines.size() - MAX_LOG_LINES);
            return lines.subList(from, lines.size());
        } catch (IOException exception) {
            return List.of();
        }
    }

    private Path safeLogPath(long jobId, String storedPath) {
        if (storedPath == null || storedPath.isBlank()) return null;
        Path root = dataDirectory.resolve("jobs").resolve(Long.toString(jobId)).resolve("logs").normalize();
        Path candidate;
        try {
            candidate = Path.of(storedPath);
        } catch (RuntimeException exception) {
            return null;
        }
        if (!candidate.isAbsolute()) candidate = dataDirectory.resolve(candidate);
        candidate = candidate.toAbsolutePath().normalize();
        if (!candidate.startsWith(root)) return null;
        try {
            if (!Files.isRegularFile(candidate, LinkOption.NOFOLLOW_LINKS)) return null;
            Path realRoot = root.toRealPath();
            Path realCandidate = candidate.toRealPath(LinkOption.NOFOLLOW_LINKS);
            return realCandidate.startsWith(realRoot) ? realCandidate : null;
        } catch (IOException exception) {
            return null;
        }
    }

    private String lastModified(Path path) {
        try {
            return Files.getLastModifiedTime(path).toInstant().toString();
        } catch (IOException exception) {
            return Instant.EPOCH.toString();
        }
    }

    static String sanitize(String line) {
        if (line == null) return "";
        String upper = line.toUpperCase(Locale.ROOT);
        if (upper.contains("PRIVATE KEY")) return "[REDACTED]";
        String sanitized = SENSITIVE_ASSIGNMENT.matcher(line).replaceAll("$1$2[REDACTED]");
        return SENSITIVE_ARGUMENT.matcher(sanitized).replaceAll("$1[REDACTED]");
    }

    public record LogEntry(
            String id,
            @JsonProperty("stage_id") long stageId,
            @JsonProperty("stage_name") String stageName,
            @JsonProperty("node_id") long nodeId,
            String hostname,
            @JsonProperty("created_at") String createdAt,
            String message) {
    }
}
