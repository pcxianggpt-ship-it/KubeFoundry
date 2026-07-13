package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.job.JobService;
import io.kubefoundry.ssh.SshCommandResult;
import io.kubefoundry.ssh.SshService;
import io.kubefoundry.ssh.SshSession;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class RemoteStepRunner {

    private static final Duration DIRECTORY_TIMEOUT = Duration.ofSeconds(60);
    private static final Duration STEP_TIMEOUT = Duration.ofHours(1);

    private final SshService ssh;
    private final RemoteSessionProvider sessions;
    private final RuntimeEnvRenderer runtimeRenderer;
    private final Path dataDirectory;

    @Autowired
    public RemoteStepRunner(
            SshService ssh,
            RemoteSessionProvider sessions,
            RuntimeEnvRenderer runtimeRenderer,
            @Value("${kubefoundry.data-dir:data}") String dataDirectory) {
        this(ssh, sessions, runtimeRenderer, Path.of(dataDirectory));
    }

    public RemoteStepRunner(
            SshService ssh,
            RemoteSessionProvider sessions,
            RuntimeEnvRenderer runtimeRenderer,
            Path dataDirectory) {
        this.ssh = ssh;
        this.sessions = sessions;
        this.runtimeRenderer = runtimeRenderer;
        this.dataDirectory = dataDirectory.toAbsolutePath().normalize();
    }

    public JobService.NodeOutcome run(
            long jobId,
            Cluster cluster,
            List<Node> nodes,
            Node node,
            InstallStep step) {
        return run(jobId, cluster, nodes, node, step, RuntimePaths.defaults(cluster, node));
    }

    public JobService.NodeOutcome run(
            long jobId,
            Cluster cluster,
            List<Node> nodes,
            Node node,
            InstallStep step,
            RuntimePaths paths) {
        Path logPath = dataDirectory.resolve("jobs").resolve(Long.toString(jobId))
                .resolve("logs").resolve(step.key()).resolve(node.getHostname() + ".log");
        try {
            Files.createDirectories(logPath.getParent());
            ResourceResolution resources = resolveResources(jobId, cluster, step, paths);
            if (resources.error() != null) {
                writeLog(logPath, "", resources.error() + "\n");
                return new JobService.NodeOutcome(false, 2, resources.error(), logPath.toString());
            }

            Path workDirectory = dataDirectory.resolve("jobs").resolve(Long.toString(jobId))
                    .resolve("work").resolve(step.key()).resolve(node.getHostname());
            Files.createDirectories(workDirectory);
            Path runtimeFile = workDirectory.resolve("runtime.env");
            Path scriptFile = workDirectory.resolve("step.sh");
            Files.writeString(runtimeFile, runtimeRenderer.render(cluster, nodes, node),
                    StandardCharsets.UTF_8);
            writeStepScript(scriptFile, cluster, nodes, step);
            String remoteDirectory = "/tmp/kubefoundry/" + jobId + "/";

            SshCommandResult result = sessions.withSession(cluster, node, session -> {
                createRemoteDirectories(session, remoteDirectory, resources.files());
                ssh.upload(session, runtimeFile, remoteDirectory + "runtime.env");
                ssh.upload(session, scriptFile, remoteDirectory + "step.sh");
                for (ResolvedResource resource : resources.files()) {
                    ssh.upload(session, resource.localPath(), resource.remotePath());
                }
                SshCommandResult executed = ssh.execute(
                        session, buildExecutionCommand(remoteDirectory, step, cluster, nodes, node),
                        STEP_TIMEOUT);
                if (executed.exitCode() == 0) collectOutputs(session, jobId, step);
                return executed;
            });
            writeLog(logPath, result.stdout(), result.stderr());
            boolean success = result.exitCode() == 0;
            String message = success ? "执行成功" : "执行失败，退出码: " + result.exitCode();
            return new JobService.NodeOutcome(
                    success, result.exitCode(), message, logPath.toString());
        } catch (Exception exception) {
            String message = stableMessage(exception);
            try {
                writeLog(logPath, "", message + "\n");
            } catch (IOException suppressed) {
                exception.addSuppressed(suppressed);
            }
            return new JobService.NodeOutcome(false, 1, message, logPath.toString());
        }
    }

    public JobService.NodeOutcome runCommand(
            long jobId,
            Cluster cluster,
            Node node,
            String stepKey,
            String command,
            Duration timeout) {
        Path logPath = dataDirectory.resolve("jobs").resolve(Long.toString(jobId))
                .resolve("logs").resolve(stepKey).resolve(node.getHostname() + ".log");
        try {
            SshCommandResult result = sessions.withSession(cluster, node,
                    session -> ssh.execute(session,
                            "bash -lc " + RuntimeEnvRenderer.shellQuote(command), timeout));
            writeLog(logPath, result.stdout(), result.stderr());
            return new JobService.NodeOutcome(result.exitCode() == 0, result.exitCode(),
                    result.exitCode() == 0 ? "执行成功" : "执行失败，退出码: " + result.exitCode(),
                    logPath.toString());
        } catch (Exception exception) {
            String message = stableMessage(exception);
            try {
                writeLog(logPath, "", message + "\n");
            } catch (IOException suppressed) {
                exception.addSuppressed(suppressed);
            }
            return new JobService.NodeOutcome(false, 1, message, logPath.toString());
        }
    }

    private void createRemoteDirectories(
            SshSession session, String remoteDirectory, List<ResolvedResource> resources)
            throws IOException {
        List<String> directories = new ArrayList<>();
        directories.add(remoteDirectory);
        for (ResolvedResource resource : resources) {
            int separator = resource.remotePath().lastIndexOf('/');
            if (separator > 0) directories.add(resource.remotePath().substring(0, separator));
        }
        String mkdir = "mkdir -p " + directories.stream().distinct()
                .map(RuntimeEnvRenderer::shellQuote)
                .collect(java.util.stream.Collectors.joining(" "));
        SshCommandResult result = ssh.execute(
                session, "bash -lc " + RuntimeEnvRenderer.shellQuote(mkdir), DIRECTORY_TIMEOUT);
        if (result.exitCode() != 0) {
            throw new IOException("创建远端目录失败，退出码: " + result.exitCode());
        }
    }

    private String buildExecutionCommand(
            String remoteDirectory,
            InstallStep step,
            Cluster cluster,
            List<Node> nodes,
            Node node) {
        StringBuilder inner = new StringBuilder("cd ")
                .append(RuntimeEnvRenderer.shellQuote(remoteDirectory))
                .append(" && chmod +x ./step.sh && source ./runtime.env && bash ./step.sh");
        for (InstallStep.Argument argument : step.arguments()) {
            inner.append(' ').append(RuntimeEnvRenderer.shellQuote(resolveArgument(argument, nodes)));
        }
        if (!step.verifyCommand().isBlank()) {
            inner.append(" && { ").append(formatVerify(step.verifyCommand(), node, nodes)).append("; }");
        }
        return "bash -lc " + RuntimeEnvRenderer.shellQuote(inner.toString());
    }

    private ResourceResolution resolveResources(
            long jobId, Cluster cluster, InstallStep step, RuntimePaths paths) {
        List<ResolvedResource> resolved = new ArrayList<>();
        for (InstallStep.Resource resource : step.resources()) {
            Path local = resource.artifactKey() == null
                    ? paths.get(resource.pathKey())
                    : dataDirectory.resolve("jobs").resolve(Long.toString(jobId))
                            .resolve("artifacts").resolve(resource.artifactKey());
            String key = resource.artifactKey() == null ? resource.pathKey() : resource.artifactKey();
            if (local == null || !Files.exists(local)) {
                return new ResourceResolution(List.of(), "步骤资源不可用: " + key);
            }
            if ("directory".equals(resource.kind()) || Files.isDirectory(local)) {
                return new ResourceResolution(List.of(), "当前最小闭环不支持目录 SFTP: " + key);
            }
            String remote = resource.remotePath().replace("{k8s_home}", "/data/k8s_install");
            resolved.add(new ResolvedResource(local, remote));
        }
        return new ResourceResolution(List.copyOf(resolved), null);
    }

    private void collectOutputs(SshSession session, long jobId, InstallStep step) throws IOException {
        for (InstallStep.Output output : step.outputs()) {
            Path local = dataDirectory.resolve("jobs").resolve(Long.toString(jobId))
                    .resolve("artifacts").resolve(output.key());
            ssh.download(session, output.remotePath(), local);
            if (Files.size(local) == 0) throw new IOException("步骤产物为空: " + output.key());
        }
    }

    private static void writeStepScript(
            Path target, Cluster cluster, List<Node> nodes, InstallStep step) throws IOException {
        if ("setup_hostname".equals(step.builtin())) {
            Files.writeString(target, renderHostnameScript(cluster, nodes), StandardCharsets.UTF_8);
            return;
        }
        if (step.script() == null || !Files.isRegularFile(step.script())) {
            throw new IOException("安装脚本不存在: " + step.script());
        }
        Files.copy(step.script(), target, StandardCopyOption.REPLACE_EXISTING);
    }

    private static String renderHostnameScript(Cluster cluster, List<Node> nodes) {
        StringBuilder script = new StringBuilder("#!/bin/bash\nset -e\n")
                .append("hostnamectl set-hostname \"$KF_NODE_HOSTNAME\"\n")
                .append("sed -i '/^# >>>KubeFoundry>>>$/,/^# <<<KubeFoundry<<</d' /etc/hosts\n")
                .append("cat >> /etc/hosts <<'KF_HOSTS_EOF'\n# >>>KubeFoundry>>>\n");
        nodes.stream().sorted(java.util.Comparator.comparing(Node::getHostname)).forEach(item ->
                script.append(item.getIp()).append("    ").append(item.getHostname()).append('\n'));
        script.append("# <<<KubeFoundry<<<\nKF_HOSTS_EOF\n")
                .append("log_success \"主机名和 hosts 配置完成\"\n");
        return script.toString();
    }

    private static String resolveArgument(InstallStep.Argument argument, List<Node> nodes) {
        if (argument.literal() != null) return argument.literal();
        Node primary = nodes.stream().filter(item -> "control_plane".equals(item.getRole()))
                .sorted(java.util.Comparator.comparing(Node::getHostname)).findFirst().orElse(null);
        if (primary == null) return "";
        return switch (argument.contextKey()) {
            case "primary_control_ip" -> primary.getIp();
            case "primary_control_hostname" -> primary.getHostname();
            default -> "";
        };
    }

    private static String formatVerify(String command, Node node, List<Node> nodes) {
        Node primary = nodes.stream().filter(item -> "control_plane".equals(item.getRole()))
                .sorted(java.util.Comparator.comparing(Node::getHostname)).findFirst().orElse(node);
        return command
                .replace("{node_hostname}", RuntimeEnvRenderer.shellQuote(node.getHostname()))
                .replace("{node_ip}", RuntimeEnvRenderer.shellQuote(node.getIp()))
                .replace("{primary_control_ip}", RuntimeEnvRenderer.shellQuote(primary.getIp()))
                .replace("{primary_control_hostname}", RuntimeEnvRenderer.shellQuote(primary.getHostname()));
    }

    private static void writeLog(Path path, String stdout, String stderr) throws IOException {
        Files.createDirectories(path.getParent());
        Files.writeString(path, (stdout == null ? "" : stdout) + (stderr == null ? "" : stderr),
                StandardCharsets.UTF_8);
    }

    private static String stableMessage(Exception exception) {
        return exception.getMessage() == null || exception.getMessage().isBlank()
                ? exception.getClass().getSimpleName() : exception.getMessage();
    }

    private record ResolvedResource(Path localPath, String remotePath) {
    }

    private record ResourceResolution(List<ResolvedResource> files, String error) {
    }

    public static final class RuntimePaths {
        private final Map<String, Path> paths = new LinkedHashMap<>();

        public RuntimePaths with(String key, Path path) {
            paths.put(key, path);
            return this;
        }

        Path get(String key) { return paths.get(key); }

        static RuntimePaths defaults(Cluster cluster, Node node) {
            String media = "/root/kube-media";
            String architecture = node.getArchitecture() == null || node.getArchitecture().isBlank()
                    ? "amd64" : node.getArchitecture();
            return new RuntimePaths()
                    .with("repo_source", Path.of(media, "01.rpm_package",
                            "k8srepo_kylinos_sp3_" + architecture + ".tar.gz"))
                    .with("kubeadm_100y", Path.of(media, "01.rpm_package",
                            "kubeadm-v" + cluster.getKubernetesVersion() + "-100y-" + architecture))
                    .with("container_runtime", Path.of(media, "02.container_runtime"))
                    .with("registry_install", Path.of(media, "04.registry"))
                    .with("flannel_config", Path.of(media, "03.setup_file", "kube-flannel.yml"));
        }
    }
}
