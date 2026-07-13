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
import java.util.Set;
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
    private final ClusterHealthRetryPolicy clusterHealthRetryPolicy;

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
        this(ssh, sessions, runtimeRenderer, dataDirectory, ClusterHealthRetryPolicy.defaults());
    }

    public RemoteStepRunner(
            SshService ssh,
            RemoteSessionProvider sessions,
            RuntimeEnvRenderer runtimeRenderer,
            Path dataDirectory,
            ClusterHealthRetryPolicy clusterHealthRetryPolicy) {
        this.ssh = ssh;
        this.sessions = sessions;
        this.runtimeRenderer = runtimeRenderer;
        this.dataDirectory = dataDirectory.toAbsolutePath().normalize();
        this.clusterHealthRetryPolicy = clusterHealthRetryPolicy == null
                ? ClusterHealthRetryPolicy.defaults() : clusterHealthRetryPolicy;
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
        return run(jobId, cluster, nodes, node, step, paths.toRuntimeSettings(cluster, node));
    }

    public JobService.NodeOutcome run(
            long jobId,
            Cluster cluster,
            List<Node> nodes,
            Node node,
            InstallStep step,
            RuntimeSettings settings) {
        List<Node> normalizedNodes = InstallationNodes.normalize(nodes);
        Path logPath = dataDirectory.resolve("jobs").resolve(Long.toString(jobId))
                .resolve("logs").resolve(step.key()).resolve(node.getHostname() + ".log");
        try {
            if ("cluster_health".equals(step.builtin())) {
                return runClusterHealth(jobId, cluster, normalizedNodes, node, step.key());
            }
            Files.createDirectories(logPath.getParent());
            ResourceResolution resources = resolveResources(jobId, step, settings);
            if (resources.error() != null) {
                writeLog(logPath, "", resources.error() + "\n");
                return new JobService.NodeOutcome(false, 2, resources.error(), logPath.toString());
            }

            Path workDirectory = dataDirectory.resolve("jobs").resolve(Long.toString(jobId))
                    .resolve("work").resolve(step.key()).resolve(node.getHostname());
            Files.createDirectories(workDirectory);
            Path runtimeFile = workDirectory.resolve("runtime.env");
            Path scriptFile = workDirectory.resolve("step.sh");
            Files.writeString(runtimeFile, runtimeRenderer.render(cluster, normalizedNodes, node, settings),
                    StandardCharsets.UTF_8);
            writeStepScript(scriptFile, cluster, normalizedNodes, step);
            String remoteDirectory = "/tmp/kubefoundry/" + jobId + "/";

            SshCommandResult result = sessions.withSession(cluster, node, session -> {
                createRemoteDirectories(session, remoteDirectory, resources.files());
                ssh.upload(session, runtimeFile, remoteDirectory + "runtime.env");
                ssh.upload(session, scriptFile, remoteDirectory + "step.sh");
                for (ResolvedResource resource : resources.files()) {
                    if ("directory".equals(resource.kind())) {
                        ssh.uploadDirectory(session, resource.localPath(), resource.remotePath());
                    } else {
                        ssh.upload(session, resource.localPath(), resource.remotePath());
                    }
                }
                SshCommandResult executed = ssh.execute(
                        session, buildExecutionCommand(
                                remoteDirectory, step, cluster, normalizedNodes, node),
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
        CommandOutcome result = runCommandCapture(jobId, cluster, node, stepKey, command, timeout);
        return new JobService.NodeOutcome(result.exitCode() == 0, result.exitCode(),
                result.exitCode() == 0 ? "执行成功" : "执行失败，退出码: " + result.exitCode(),
                result.logPath());
    }

    public CommandOutcome runCommandCapture(
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
            return new CommandOutcome(result.exitCode(), result.stdout(), result.stderr(), logPath.toString());
        } catch (Exception exception) {
            String message = stableMessage(exception);
            try {
                writeLog(logPath, "", message + "\n");
            } catch (IOException suppressed) {
                exception.addSuppressed(suppressed);
            }
            return new CommandOutcome(1, "", message, logPath.toString());
        }
    }

    private JobService.NodeOutcome runClusterHealth(
            long jobId, Cluster cluster, List<Node> nodes, Node node, String stepKey) {
        String command = "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes --no-headers "
                + "&& printf '\\n__KF_PODS__\\n' "
                + "&& KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A --no-headers";
        CommandOutcome last = null;
        String message = "集群健康检查失败";
        for (int attempt = 1; attempt <= clusterHealthRetryPolicy.attempts(); attempt++) {
            last = runCommandCapture(jobId, cluster, node, stepKey, command, Duration.ofSeconds(120));
            if (last.exitCode() == 0) {
                HealthResult health = evaluateClusterHealth(nodes, last.stdout());
                if (health.ok()) {
                    return new JobService.NodeOutcome(true, 0, health.message(), last.logPath());
                }
                message = health.message();
            } else {
                message = "集群健康检查命令失败，退出码: " + last.exitCode();
            }
            if (attempt < clusterHealthRetryPolicy.attempts()) {
                try {
                    clusterHealthRetryPolicy.waiter().waitFor(clusterHealthRetryPolicy.interval());
                } catch (InterruptedException exception) {
                    Thread.currentThread().interrupt();
                    return new JobService.NodeOutcome(false, 1, "集群健康检查已中断", last.logPath());
                }
            }
        }
        int exitCode = last != null && last.exitCode() != 0 ? last.exitCode() : 1;
        return new JobService.NodeOutcome(false, exitCode, message, last == null ? "" : last.logPath());
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
            long jobId, InstallStep step, RuntimeSettings paths) {
        List<ResolvedResource> resolved = new ArrayList<>();
        for (InstallStep.Resource resource : step.resources()) {
            Path local = resource.artifactKey() == null
                    ? paths.localPath(resource.pathKey())
                    : dataDirectory.resolve("jobs").resolve(Long.toString(jobId))
                            .resolve("artifacts").resolve(resource.artifactKey());
            String key = resource.artifactKey() == null ? resource.pathKey() : resource.artifactKey();
            if (local == null || !Files.exists(local)) {
                return new ResourceResolution(List.of(), "步骤资源不可用: " + key);
            }
            if ("directory".equals(resource.kind()) && !Files.isDirectory(local)) {
                return new ResourceResolution(List.of(), "步骤资源不是目录: " + key);
            }
            if (!"directory".equals(resource.kind()) && !Files.isRegularFile(local)) {
                return new ResourceResolution(List.of(), "步骤资源不是普通文件: " + key);
            }
            String remote = resource.remotePath().replace("{k8s_home}", paths.k8sHome());
            resolved.add(new ResolvedResource(local, remote, resource.kind()));
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
                .append("{\n  printf '%s\\n' '# >>>KubeFoundry>>>'\n");
        Map<String, java.util.LinkedHashSet<String>> aliases = new java.util.TreeMap<>();
        nodes.stream().sorted(java.util.Comparator.comparing(Node::getHostname,
                java.util.Comparator.nullsLast(String::compareTo))).forEach(item -> addHostAlias(
                aliases, item.getIp(), item.getHostname()));
        addHostAlias(aliases, cluster.getRegistryIp(), RuntimeEnvRenderer.registryHostname(cluster));
        aliases.forEach((ip, hostnames) -> script.append("  printf '%s\\n' ")
                .append(RuntimeEnvRenderer.shellQuote(ip + "    " + String.join(" ", hostnames)))
                .append('\n'));
        script.append("  printf '%s\\n' '# <<<KubeFoundry<<<'\n} >> /etc/hosts\n")
                .append("log_success \"主机名和 hosts 配置完成\"\n");
        return script.toString();
    }

    private static void addHostAlias(
            Map<String, java.util.LinkedHashSet<String>> aliases, String ip, String hostname) {
        if (ip == null || ip.isBlank() || hostname == null || hostname.isBlank()) return;
        aliases.computeIfAbsent(hostsToken(ip), ignored -> new java.util.LinkedHashSet<>())
                .add(hostsToken(hostname));
    }

    private static String hostsToken(String value) {
        return value.trim().replace("\r", "").replace("\n", "");
    }

    private static String resolveArgument(InstallStep.Argument argument, List<Node> nodes) {
        if (argument.literal() != null) return argument.literal();
        Node primary = PrimaryControlPlaneSelector.select(nodes);
        if (primary == null) return "";
        return switch (argument.contextKey()) {
            case "primary_control_ip" -> primary.getIp();
            case "primary_control_hostname" -> primary.getHostname();
            default -> "";
        };
    }

    private static String formatVerify(String command, Node node, List<Node> nodes) {
        Node primary = PrimaryControlPlaneSelector.select(nodes);
        if (primary == null) primary = node;
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

    private static HealthResult evaluateClusterHealth(List<Node> nodes, String output) {
        String[] sections = (output == null ? "" : output).split("(?m)^__KF_PODS__$", 2);
        Set<String> expected = nodes.stream()
                .filter(node -> Set.of("control_plane", "worker").contains(node.getRole()))
                .map(Node::getHostname)
                .filter(name -> name != null && !name.isBlank())
                .collect(java.util.stream.Collectors.toCollection(java.util.TreeSet::new));
        Set<String> ready = new java.util.TreeSet<>();
        Set<String> notReady = new java.util.TreeSet<>();
        for (String line : sections[0].split("\\R")) {
            String[] fields = line.trim().split("\\s+");
            if (fields.length < 2 || fields[0].isBlank()) continue;
            if ("Ready".equals(fields[1])) ready.add(fields[0]);
            else notReady.add(fields[0]);
        }
        Set<String> observed = new java.util.TreeSet<>(ready);
        observed.addAll(notReady);
        Set<String> missing = new java.util.TreeSet<>(expected);
        missing.removeAll(observed);
        List<String> failedPods = new ArrayList<>();
        int flannelReady = 0;
        if (sections.length > 1) {
            for (String line : sections[1].split("\\R")) {
                String[] fields = line.trim().split("\\s+");
                if (fields.length < 4) continue;
                String namespace = fields[0];
                String name = fields[1];
                String readyCount = fields[2];
                String status = fields[3];
                if (!Set.of("Running", "Completed", "Succeeded").contains(status)) {
                    failedPods.add(namespace + "/" + name + ":" + status);
                }
                if ("kube-flannel".equals(namespace) && "Running".equals(status)
                        && readyCountMatches(readyCount)) {
                    flannelReady++;
                }
            }
        }
        List<String> problems = new ArrayList<>();
        if (!notReady.isEmpty()) problems.add("NotReady nodes: " + String.join(", ", notReady));
        if (!missing.isEmpty()) problems.add("missing nodes: " + String.join(", ", missing));
        if (!failedPods.isEmpty()) problems.add("failed pods: " + String.join(", ", failedPods));
        if (flannelReady < expected.size()) {
            problems.add("flannel ready " + flannelReady + "/" + expected.size());
        }
        return problems.isEmpty()
                ? new HealthResult(true, "cluster health check passed")
                : new HealthResult(false, String.join("; ", problems));
    }

    private static boolean readyCountMatches(String value) {
        String[] parts = value.split("/", 2);
        if (parts.length != 2) return false;
        try {
            int ready = Integer.parseInt(parts[0]);
            int total = Integer.parseInt(parts[1]);
            return total > 0 && ready == total;
        } catch (NumberFormatException exception) {
            return false;
        }
    }

    private record ResolvedResource(Path localPath, String remotePath, String kind) {
    }

    private record ResourceResolution(List<ResolvedResource> files, String error) {
    }

    private record HealthResult(boolean ok, String message) {
    }

    public record CommandOutcome(int exitCode, String stdout, String stderr, String logPath) {
        public CommandOutcome {
            stdout = stdout == null ? "" : stdout;
            stderr = stderr == null ? "" : stderr;
            logPath = logPath == null ? "" : logPath;
        }
    }

    public record ClusterHealthRetryPolicy(int attempts, Duration interval, Waiter waiter) {
        public ClusterHealthRetryPolicy {
            attempts = Math.min(30, Math.max(1, attempts));
            interval = interval == null || interval.isNegative() ? Duration.ZERO : interval;
            waiter = waiter == null ? duration -> Thread.sleep(duration.toMillis()) : waiter;
        }

        static ClusterHealthRetryPolicy defaults() {
            return new ClusterHealthRetryPolicy(30, Duration.ofSeconds(10), null);
        }
    }

    @FunctionalInterface
    public interface Waiter {
        void waitFor(Duration duration) throws InterruptedException;
    }

    public static final class RuntimePaths {
        private final Map<String, Path> paths = new LinkedHashMap<>();

        public RuntimePaths with(String key, Path path) {
            paths.put(key, path);
            return this;
        }

        Path get(String key) { return paths.get(key); }

        RuntimeSettings toRuntimeSettings(Cluster cluster, Node node) {
            RuntimeSettings defaults = defaults(cluster, node).toRuntimeSettingsWithoutRecursing();
            Map<String, String> values = new LinkedHashMap<>(defaults.paths());
            paths.forEach((key, path) -> values.put(key, path.toString()));
            return new RuntimeSettings(values, defaults.env(), defaults.advanced());
        }

        private RuntimeSettings toRuntimeSettingsWithoutRecursing() {
            Map<String, String> values = new LinkedHashMap<>();
            paths.forEach((key, path) -> values.put(key, path.toString().replace('\\', '/')));
            String k8sHome = values.getOrDefault("k8s_home", "/data/k8s_install");
            return new RuntimeSettings(values, Map.of(
                    "kubelet_root", k8sHome + "/kubelet_root",
                    "containerd_root", k8sHome + "/containerd-data",
                    "etcd_data_dir", k8sHome + "/etcd_backup"),
                    Map.of("enable_ipv6_dual_stack", false));
        }

        static RuntimePaths defaults(Cluster cluster, Node node) {
            String media = "/root/kube-media";
            String k8sHome = "/data/k8s_install";
            String architecture = node.getArchitecture() == null || node.getArchitecture().isBlank()
                    ? "amd64" : node.getArchitecture();
            return new RuntimePaths()
                    .with("k8s_home", Path.of(k8sHome))
                    .with("install_media", Path.of(media))
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
