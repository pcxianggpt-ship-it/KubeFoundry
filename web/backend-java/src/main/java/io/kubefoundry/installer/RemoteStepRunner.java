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
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermission;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.EnumSet;
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
    private static final Duration VERIFICATION_TIMEOUT = Duration.ofMinutes(2);

    private final SshService ssh;
    private final RemoteSessionProvider sessions;
    private final RuntimeEnvRenderer runtimeRenderer;
    private final Path dataDirectory;
    private final ClusterHealthRetryPolicy clusterHealthRetryPolicy;
    private final NfsTargetResolver nfsTargets;

    @Autowired
    public RemoteStepRunner(
            SshService ssh,
            RemoteSessionProvider sessions,
            RuntimeEnvRenderer runtimeRenderer,
            @Value("${kubefoundry.data-dir:data}") String dataDirectory,
            NfsTargetResolver nfsTargets) {
        this(ssh, sessions, runtimeRenderer, Path.of(dataDirectory),
                ClusterHealthRetryPolicy.defaults(), nfsTargets);
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
        this(ssh, sessions, runtimeRenderer, dataDirectory, clusterHealthRetryPolicy, null);
    }

    private RemoteStepRunner(
            SshService ssh,
            RemoteSessionProvider sessions,
            RuntimeEnvRenderer runtimeRenderer,
            Path dataDirectory,
            ClusterHealthRetryPolicy clusterHealthRetryPolicy,
            NfsTargetResolver nfsTargets) {
        this.ssh = ssh;
        this.sessions = sessions;
        this.runtimeRenderer = runtimeRenderer;
        this.dataDirectory = dataDirectory.toAbsolutePath().normalize();
        this.clusterHealthRetryPolicy = clusterHealthRetryPolicy == null
                ? ClusterHealthRetryPolicy.defaults() : clusterHealthRetryPolicy;
        this.nfsTargets = nfsTargets;
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
        java.util.concurrent.atomic.AtomicReference<String> activeVerificationPhase =
                new java.util.concurrent.atomic.AtomicReference<>();
        try {
            if ("cluster_health".equals(step.builtin())) {
                return runClusterHealth(jobId, cluster, normalizedNodes, node, step.key());
            }
            Files.createDirectories(logPath.getParent());
            Path workDirectory = dataDirectory.resolve("jobs").resolve(Long.toString(jobId))
                    .resolve("work").resolve(step.key()).resolve(node.getHostname());
            Files.createDirectories(workDirectory);
            Path runtimeFile = workDirectory.resolve("runtime.env");
            Path scriptFile = workDirectory.resolve("step.sh");
            Path verifyFile = workDirectory.resolve("verify.sh");
            Path recoveryFile = workDirectory.resolve("recovery.sh");
            Path phase3Library = workDirectory.resolve("phase3.sh");
            Files.writeString(runtimeFile, runtimeRenderer.render(cluster, normalizedNodes, node, settings,
                    runtimeEnvironment(jobId, cluster, step, List.of())),
                    StandardCharsets.UTF_8);
            writePhase3Library(phase3Library, step);
            String remoteDirectory = remoteStepDirectory(jobId, step, node);

            if (usesStrictVerification(step)) {
                writeVerifyScript(verifyFile, step);
                writeRecoveryScript(recoveryFile, step);
                createEvidenceSnapshot(jobId, step, node, workDirectory, List.of());
                activeVerificationPhase.set("before");
                SshCommandResult before = sessions.withSession(cluster, node, session -> {
                    createRemoteDirectories(session, remoteDirectory, List.of());
                    ssh.upload(session, runtimeFile, remoteDirectory + "runtime.env");
                    ssh.upload(session, verifyFile, remoteDirectory + "verify.sh");
                    restrictRemoteJobDirectory(session, jobId);
                    return ssh.execute(session, buildVerificationCommand(remoteDirectory),
                            VERIFICATION_TIMEOUT);
                });
                activeVerificationPhase.set(null);
                writeVerificationEvidence(jobId, step, node, "before", before);
                if (before.exitCode() == 0) {
                    if (step.recoveryScript() != null && !step.outputs().isEmpty()) {
                        activeVerificationPhase.set("before");
                        SshCommandResult recovered = sessions.withSession(cluster, node, session -> {
                            ssh.upload(session, recoveryFile, remoteDirectory + "recovery.sh");
                            restrictRemoteJobDirectory(session, jobId);
                            SshCommandResult recoveryResult = ssh.execute(
                                    session, buildRecoveryCommand(remoteDirectory), VERIFICATION_TIMEOUT);
                            if (recoveryResult.exitCode() == 0) collectOutputs(session, jobId, step);
                            return recoveryResult;
                        });
                        activeVerificationPhase.set(null);
                        writeRecoveryEvidence(jobId, step, node, recovered);
                        if (recovered.exitCode() != 0) {
                            String message = "OUTPUT_RECOVERY_FAILED/exit_code=" + recovered.exitCode();
                            writeLog(logPath, recovered.stdout(), recovered.stderr());
                            writeEvidenceOutcome(jobId, step.key(), node, logPath,
                                    false, recovered.exitCode(), message);
                            return new JobService.NodeOutcome(false, recovered.exitCode(), message,
                                    logPath.toString(), "failed", "before");
                        }
                        captureOutputEvidence(jobId, step, node);
                    }
                    writeLog(logPath, before.stdout(), before.stderr());
                    writeEvidenceOutcome(jobId, step.key(), node, logPath,
                            true, 0, "PREVERIFY_SATISFIED");
                    return JobService.NodeOutcome.preverified(logPath.toString());
                }
                if (before.exitCode() != 10) {
                    String message = verificationFailure("PREVERIFY", before.exitCode());
                    writeLog(logPath, before.stdout(), before.stderr());
                    writeEvidenceOutcome(jobId, step.key(), node, logPath,
                            false, before.exitCode(), message);
                    return new JobService.NodeOutcome(false, before.exitCode(), message,
                            logPath.toString(), "failed", "before");
                }
            }

            ResourceResolution resources = resolveResources(jobId, step, settings);
            if (resources.error() != null) {
                writeLog(logPath, "", resources.error() + "\n");
                writeEvidenceOutcome(jobId, step.key(), node, logPath,
                        false, 2, resources.error());
                return new JobService.NodeOutcome(false, 2, resources.error(), logPath.toString());
            }
            Files.writeString(runtimeFile, runtimeRenderer.render(cluster, normalizedNodes, node, settings,
                    runtimeEnvironment(jobId, cluster, step, resources.files())),
                    StandardCharsets.UTF_8);
            writeStepScript(scriptFile, cluster, normalizedNodes, step);
            createEvidenceSnapshot(jobId, step, node, workDirectory, resources.files());

            java.util.concurrent.atomic.AtomicBoolean postVerification =
                    new java.util.concurrent.atomic.AtomicBoolean(false);
            java.util.concurrent.atomic.AtomicReference<SshCommandResult> afterResult =
                    new java.util.concurrent.atomic.AtomicReference<>();
            SshCommandResult result = sessions.withSession(cluster, node, session -> {
                createRemoteDirectories(session, remoteDirectory, resources.files());
                ssh.upload(session, runtimeFile, remoteDirectory + "runtime.env");
                ssh.upload(session, scriptFile, remoteDirectory + "step.sh");
                if (Files.exists(verifyFile)) {
                    ssh.upload(session, verifyFile, remoteDirectory + "verify.sh");
                }
                if (Files.exists(phase3Library)) {
                    ssh.upload(session, phase3Library, remoteDirectory + "phase3.sh");
                }
                for (ResolvedResource resource : resources.files()) {
                    if ("directory".equals(resource.kind())) {
                        ssh.uploadDirectory(session, resource.localPath(), resource.remotePath());
                    } else {
                        ssh.upload(session, resource.localPath(), resource.remotePath());
                    }
                }
                restrictRemoteJobDirectory(session, jobId);
                SshCommandResult executed = ssh.execute(
                        session, buildExecutionCommand(
                                remoteDirectory, step, cluster, normalizedNodes, node),
                        STEP_TIMEOUT);
                if (executed.exitCode() != 0 || !usesStrictVerification(step)) {
                    if (executed.exitCode() == 0) collectOutputs(session, jobId, step);
                    return executed;
                }
                postVerification.set(true);
                activeVerificationPhase.set("after");
                SshCommandResult verified = ssh.execute(
                        session, buildVerificationCommand(remoteDirectory), VERIFICATION_TIMEOUT);
                activeVerificationPhase.set(null);
                afterResult.set(verified);
                if (verified.exitCode() == 0) collectOutputs(session, jobId, step);
                return new SshCommandResult(verified.exitCode(),
                        textOrEmpty(executed.stdout()) + textOrEmpty(verified.stdout()),
                        textOrEmpty(executed.stderr()) + textOrEmpty(verified.stderr()));
            });
            if (afterResult.get() != null) {
                writeVerificationEvidence(jobId, step, node, "after", afterResult.get());
            }
            writeLog(logPath, result.stdout(), result.stderr());
            boolean success = result.exitCode() == 0;
            String message = success ? "执行成功" : postVerification.get()
                    ? verificationFailure("POSTVERIFY", result.exitCode())
                    : "执行失败，退出码: " + result.exitCode();
            writeEvidenceOutcome(jobId, step.key(), node, logPath, success, result.exitCode(), message);
            if (success) captureOutputEvidence(jobId, step, node);
            return new JobService.NodeOutcome(
                    success, result.exitCode(), message, logPath.toString(),
                    success ? "success" : "failed", postVerification.get() ? "after" : null);
        } catch (Exception exception) {
            String verificationPhase = activeVerificationPhase.get();
            String message = verificationPhase == null ? stableMessage(exception)
                    : verificationException(verificationPhase, exception);
            try {
                writeLog(logPath, "", message + "\n");
                writeEvidenceOutcome(jobId, step.key(), node, logPath, false, 1, message);
            } catch (IOException suppressed) {
                exception.addSuppressed(suppressed);
            }
            return new JobService.NodeOutcome(false, 1, message, logPath.toString(), "failed",
                    verificationPhase);
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
            writeCommandEvidence(jobId, stepKey, node, command);
            SshCommandResult result = sessions.withSession(cluster, node,
                    session -> ssh.execute(session,
                            "bash -lc " + RuntimeEnvRenderer.shellQuote(command), timeout));
            writeLog(logPath, result.stdout(), result.stderr());
            writeEvidenceOutcome(jobId, stepKey, node, logPath, result.exitCode() == 0,
                    result.exitCode(), result.exitCode() == 0
                            ? "执行成功" : "执行失败，退出码: " + result.exitCode());
            return new CommandOutcome(result.exitCode(), result.stdout(), result.stderr(), logPath.toString());
        } catch (Exception exception) {
            String message = stableMessage(exception);
            try {
                writeLog(logPath, "", message + "\n");
                writeEvidenceOutcome(jobId, stepKey, node, logPath, false, 1, message);
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
        String mkdir = "umask 077 && mkdir -p " + directories.stream().distinct()
                .map(RuntimeEnvRenderer::shellQuote)
                .collect(java.util.stream.Collectors.joining(" "));
        SshCommandResult result = ssh.execute(
                session, "bash -lc " + RuntimeEnvRenderer.shellQuote(mkdir), DIRECTORY_TIMEOUT);
        if (result.exitCode() != 0) {
            throw new IOException("创建远端目录失败，退出码: " + result.exitCode());
        }
    }

    private void restrictRemoteJobDirectory(SshSession session, long jobId) throws IOException {
        String directory = "/tmp/kubefoundry/jobs/" + jobId;
        SshCommandResult result = ssh.execute(session,
                "bash -lc " + RuntimeEnvRenderer.shellQuote("chmod -R go-rwx -- "
                        + RuntimeEnvRenderer.shellQuote(directory)), DIRECTORY_TIMEOUT);
        if (result.exitCode() != 0) {
            throw new IOException("设置远程任务留痕目录权限失败，退出码: " + result.exitCode());
        }
    }

    private static String remoteStepDirectory(long jobId, InstallStep step, Node node) throws IOException {
        return "/tmp/kubefoundry/jobs/" + jobId + "/steps/"
                + safeEvidenceSegment(step.key(), "步骤键") + "/"
                + safeEvidenceSegment(node.getHostname(), "节点主机名") + "/";
    }

    private String buildExecutionCommand(
            String remoteDirectory,
            InstallStep step,
            Cluster cluster,
            List<Node> nodes,
            Node node) {
        StringBuilder inner = new StringBuilder("cd ")
                .append(RuntimeEnvRenderer.shellQuote(remoteDirectory))
                .append(" && chmod +x ./step.sh && source ./runtime.env")
                .append("kubemate_component".equals(step.phase()) ? " && source ./phase3.sh" : "")
                .append(" && bash ./step.sh");
        for (InstallStep.Argument argument : step.arguments()) {
            inner.append(' ').append(RuntimeEnvRenderer.shellQuote(resolveArgument(argument, nodes)));
        }
        if (!usesStrictVerification(step) && !step.verifyCommand().isBlank()) {
            inner.append(" && { ").append(formatVerify(step.verifyCommand(), node, nodes)).append("; }");
        }
        return "bash -lc " + RuntimeEnvRenderer.shellQuote(inner.toString());
    }

    private static String buildVerificationCommand(String remoteDirectory) {
        String inner = "cd " + RuntimeEnvRenderer.shellQuote(remoteDirectory)
                + " && chmod +x ./verify.sh && source ./runtime.env"
                + " && bash ./verify.sh";
        return "bash -lc " + RuntimeEnvRenderer.shellQuote(inner);
    }

    private static String buildRecoveryCommand(String remoteDirectory) {
        String inner = "cd " + RuntimeEnvRenderer.shellQuote(remoteDirectory)
                + " && chmod +x ./recovery.sh && source ./runtime.env && bash ./recovery.sh";
        return "bash -lc " + RuntimeEnvRenderer.shellQuote(inner);
    }

    private static boolean usesStrictVerification(InstallStep step) {
        return step.type() == InstallStep.StepType.INSTALL && step.verifyScript() != null;
    }

    private static String verificationFailure(String phase, int exitCode) {
        String category = switch (exitCode) {
            case 20 -> "CONFIGURATION_ERROR";
            case 21 -> "VERIFICATION_TIMEOUT";
            default -> "VERIFICATION_ERROR";
        };
        return phase + "_FAILED/" + category + "/exit_code=" + exitCode;
    }

    private static String verificationException(String phase, Exception exception) {
        String normalizedPhase = "after".equals(phase) ? "POSTVERIFY" : "PREVERIFY";
        String detail = stableMessage(exception);
        String normalizedDetail = detail.toLowerCase(java.util.Locale.ROOT);
        String category = normalizedDetail.contains("timeout") || normalizedDetail.contains("超时")
                ? "VERIFICATION_TIMEOUT" : "VERIFICATION_EXCEPTION";
        return normalizedPhase + "_FAILED/" + category;
    }

    private static String textOrEmpty(String value) {
        return value == null ? "" : value;
    }

    private ResourceResolution resolveResources(
            long jobId, InstallStep step, RuntimeSettings paths) {
        List<ResolvedResource> resolved = new ArrayList<>();
        for (InstallStep.Resource resource : step.resources()) {
            Path local = resource.localPath() != null ? resource.localPath()
                    : resource.artifactKey() == null
                            ? paths.localPath(resource.pathKey())
                            : dataDirectory.resolve("jobs").resolve(Long.toString(jobId))
                                    .resolve("artifacts").resolve(resource.artifactKey());
            String key = resource.localPath() != null ? resource.localPath().toString()
                    : resource.artifactKey() == null ? resource.pathKey() : resource.artifactKey();
            if (local == null || !Files.exists(local)) {
                return new ResourceResolution(List.of(), "步骤资源不可用: " + key);
            }
            if ("directory".equals(resource.kind()) && !Files.isDirectory(local)) {
                return new ResourceResolution(List.of(), "步骤资源不是目录: " + key);
            }
            if (!"directory".equals(resource.kind()) && !Files.isRegularFile(local)) {
                return new ResourceResolution(List.of(), "步骤资源不是普通文件: " + key);
            }
            if (resource.checksum() != null) {
                try {
                    if (!resource.checksum().equals(sha256(local))) {
                        return new ResourceResolution(List.of(), "步骤资源校验和不匹配: " + key);
                    }
                } catch (IOException exception) {
                    return new ResourceResolution(List.of(), "步骤资源校验失败: " + key);
                }
            }
            String remote = resource.remotePath().replace("{k8s_home}", paths.k8sHome())
                    .replace("{job_id}", Long.toString(jobId));
            resolved.add(new ResolvedResource(local, remote, resource.kind(), resource.checksum()));
        }
        return new ResourceResolution(List.copyOf(resolved), null);
    }

    private Map<String, String> runtimeEnvironment(
            long jobId, Cluster cluster, InstallStep step, List<ResolvedResource> resources) {
        String group = step.componentGroupKey() == null ? "shared" : step.componentGroupKey();
        Map<String, String> values = new LinkedHashMap<>();
        values.put("KF_STEP_KEY", step.key());
        values.put("KF_VERIFY_COMMAND_TIMEOUT", "30s");
        values.put("KF_VERIFY_ROLLOUT_TIMEOUT", "180s");
        String resourceDirectory = "/tmp/kubefoundry/jobs/" + jobId + "/resources/" + group;
        if (!resources.isEmpty()) {
            ResolvedResource first = resources.get(0);
            resourceDirectory = "directory".equals(first.kind())
                    ? first.remotePath() : remoteParent(first.remotePath());
        }
        values.put("KF_COMPONENT_RESOURCE_DIR", resourceDirectory);
        if ("29-install-helm".equals(step.key()) && !resources.isEmpty()
                && resources.get(0).checksum() != null) {
            values.put("KF_HELM_SHA256", resources.get(0).checksum());
        }
        if ("kubemate_component".equals(step.phase()) && !resources.isEmpty()
                && resources.get(0).checksum() != null) {
            values.put("KF_COMPONENT_MEDIA_SHA256", resources.get(0).checksum());
        }
        if ("nfs".equals(step.componentGroupKey()) && nfsTargets != null) {
            values.putAll(nfsTargets.runtimeValues(cluster));
        }
        return values;
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

    private static void writeVerifyScript(Path target, InstallStep step) throws IOException {
        if (step.verifyScript() == null || !Files.isRegularFile(step.verifyScript())) {
            throw new IOException("验证脚本不存在: " + step.verifyScript());
        }
        if (Files.isSymbolicLink(step.verifyScript())) {
            throw new IOException("验证脚本不能是符号链接: " + step.verifyScript());
        }
        Files.copy(step.verifyScript(), target, StandardCopyOption.REPLACE_EXISTING);
    }

    private static void writeRecoveryScript(Path target, InstallStep step) throws IOException {
        if (step.recoveryScript() == null) return;
        if (!Files.isRegularFile(step.recoveryScript()) || Files.isSymbolicLink(step.recoveryScript())) {
            throw new IOException("产物恢复脚本不可用: " + step.recoveryScript());
        }
        Files.copy(step.recoveryScript(), target, StandardCopyOption.REPLACE_EXISTING);
    }

    private static void writePhase3Library(Path target, InstallStep step) throws IOException {
        if (!"kubemate_component".equals(step.phase())) return;
        Path script = step.script();
        Path root = script == null ? null : script.getParent().getParent().getParent().getParent();
        Path library = root == null ? null : root.resolve("scripts/lib/phase3.sh");
        if (library == null || !Files.isRegularFile(library)) {
            throw new IOException("phase3 公共函数库不存在: " + library);
        }
        Files.copy(library, target, StandardCopyOption.REPLACE_EXISTING);
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
        Node registry = RegistryNodeSelector.select(nodes);
        if (registry != null) {
            addHostAlias(aliases, registry.getIp(), registry.getHostname());
            addHostAlias(aliases, registry.getIp(), "registry");
        }
        else addHostAlias(aliases, cluster.getRegistryIp(), RuntimeEnvRenderer.registryHostname(cluster));
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

    private static String sha256(Path source) throws IOException {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            if (Files.isDirectory(source)) {
                try (var paths = Files.walk(source)) {
                    for (Path path : paths.sorted().toList()) {
                        if (Files.isDirectory(path)) continue;
                        digest.update(source.relativize(path).toString().replace('\\', '/')
                                .getBytes(StandardCharsets.UTF_8));
                        digest.update((byte) 0);
                        try (var input = Files.newInputStream(path)) {
                            input.transferTo(new java.io.OutputStream() {
                                @Override public void write(int value) { digest.update((byte) value); }
                                @Override public void write(byte[] data, int offset, int length) {
                                    digest.update(data, offset, length);
                                }
                            });
                        }
                    }
                }
            } else {
                try (var input = Files.newInputStream(source)) {
                    input.transferTo(new java.io.OutputStream() {
                        @Override public void write(int value) { digest.update((byte) value); }
                        @Override public void write(byte[] data, int offset, int length) {
                            digest.update(data, offset, length);
                        }
                    });
                }
            }
            return java.util.HexFormat.of().formatHex(digest.digest());
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private static void writeLog(Path path, String stdout, String stderr) throws IOException {
        Files.createDirectories(path.getParent());
        Files.writeString(path, (stdout == null ? "" : stdout) + (stderr == null ? "" : stderr),
                StandardCharsets.UTF_8);
    }

    private void createEvidenceSnapshot(
            long jobId,
            InstallStep step,
            Node node,
            Path workDirectory,
            List<ResolvedResource> resources) throws IOException {
        Path evidence = evidenceDirectory(jobId, step, node);
        Files.createDirectories(evidence);
        copyIfPresent(workDirectory.resolve("runtime.env"), evidence.resolve("runtime.env"));
        copyIfPresent(workDirectory.resolve("step.sh"), evidence.resolve("step.sh"));
        copyIfPresent(workDirectory.resolve("verify.sh"), evidence.resolve("verify.sh"));
        copyIfPresent(workDirectory.resolve("recovery.sh"), evidence.resolve("recovery.sh"));
        copyIfPresent(workDirectory.resolve("phase3.sh"), evidence.resolve("phase3.sh"));
        Path resourceRoot = evidence.resolve("resources");
        Files.createDirectories(resourceRoot);
        for (int index = 0; index < resources.size(); index++) {
            ResolvedResource resource = resources.get(index);
            String name = resource.localPath().getFileName() == null
                    ? "resource" : resource.localPath().getFileName().toString();
            copyEvidenceTree(resource.localPath(), resourceRoot.resolve(
                    String.format("%02d-%s", index + 1, safeEvidenceSegment(name, "资源名称"))));
        }
        writeEvidenceChecksums(evidence);
        restrictLocalEvidencePermissions(evidence);
    }

    private void writeVerificationEvidence(
            long jobId,
            InstallStep step,
            Node node,
            String phase,
            SshCommandResult result) throws IOException {
        Path evidence = evidenceDirectory(jobId, step, node);
        Files.createDirectories(evidence);
        String contents = (result.stdout() == null ? "" : result.stdout())
                + (result.stderr() == null ? "" : result.stderr());
        Files.writeString(evidence.resolve("verification-" + phase + ".log"), contents,
                StandardCharsets.UTF_8);
        Files.writeString(evidence.resolve("verification-" + phase + ".properties"),
                "phase=" + phase + "\nexit_code=" + result.exitCode() + "\n",
                StandardCharsets.UTF_8);
        writeEvidenceChecksums(evidence);
        restrictLocalEvidencePermissions(evidence);
    }

    private void writeRecoveryEvidence(
            long jobId, InstallStep step, Node node, SshCommandResult result) throws IOException {
        Path evidence = evidenceDirectory(jobId, step, node);
        Files.createDirectories(evidence);
        Files.writeString(evidence.resolve("recovery.log"),
                textOrEmpty(result.stdout()) + textOrEmpty(result.stderr()), StandardCharsets.UTF_8);
        Files.writeString(evidence.resolve("recovery.properties"),
                "exit_code=" + result.exitCode() + "\n", StandardCharsets.UTF_8);
        writeEvidenceChecksums(evidence);
        restrictLocalEvidencePermissions(evidence);
    }

    private void captureOutputEvidence(long jobId, InstallStep step, Node node) throws IOException {
        if (step.outputs().isEmpty()) return;
        Path evidence = evidenceDirectory(jobId, step, node);
        Path outputDirectory = evidence.resolve("outputs");
        Files.createDirectories(outputDirectory);
        for (InstallStep.Output output : step.outputs()) {
            Path source = dataDirectory.resolve("jobs").resolve(Long.toString(jobId))
                    .resolve("artifacts").resolve(output.key());
            copyIfPresent(source, outputDirectory.resolve(safeEvidenceSegment(output.key(), "产物键")));
        }
        writeEvidenceChecksums(evidence);
        restrictLocalEvidencePermissions(evidence);
    }

    private void writeCommandEvidence(long jobId, String stepKey, Node node, String command) throws IOException {
        Path evidence = evidenceDirectory(jobId, stepKey, node);
        Files.createDirectories(evidence);
        Files.writeString(evidence.resolve("command.sh"), "#!/bin/bash\n" + command + "\n",
                StandardCharsets.UTF_8);
        restrictLocalEvidencePermissions(evidence);
    }

    private void writeEvidenceOutcome(
            long jobId,
            String stepKey,
            Node node,
            Path logPath,
            boolean success,
            int exitCode,
            String message) throws IOException {
        Path evidence = evidenceDirectory(jobId, stepKey, node);
        Files.createDirectories(evidence);
        copyIfPresent(logPath, evidence.resolve("execution.log"));
        String result = "job_id=" + jobId + "\n"
                + "step_key=" + escapeEvidenceValue(stepKey) + "\n"
                + "node=" + escapeEvidenceValue(node.getHostname()) + "\n"
                + "success=" + success + "\n"
                + "exit_code=" + exitCode + "\n"
                + "message=" + escapeEvidenceValue(message) + "\n"
                + "completed_at=" + Instant.now() + "\n"
                + "log_path=" + escapeEvidenceValue(logPath.toString()) + "\n";
        Files.writeString(evidence.resolve("result.properties"), result, StandardCharsets.UTF_8);
        writeEvidenceChecksums(evidence);
        restrictLocalEvidencePermissions(evidence);
    }

    private Path evidenceDirectory(long jobId, InstallStep step, Node node) throws IOException {
        return evidenceDirectory(jobId, step.key(), node);
    }

    private Path evidenceDirectory(long jobId, String stepKey, Node node) throws IOException {
        Path root = dataDirectory.resolve("jobs").resolve(Long.toString(jobId)).resolve("evidence")
                .toAbsolutePath().normalize();
        Path evidence = root.resolve(safeEvidenceSegment(stepKey, "步骤键"))
                .resolve(safeEvidenceSegment(node.getHostname(), "节点主机名")).normalize();
        if (!evidence.startsWith(root)) throw new IOException("任务留痕目录越界");
        return evidence;
    }

    private static String safeEvidenceSegment(String value, String field) throws IOException {
        if (value == null || !value.matches("[A-Za-z0-9._-]+") || value.contains("..")) {
            throw new IOException(field + "不适合作为留痕目录名称");
        }
        return value;
    }

    private static String remoteParent(String path) {
        int separator = path.lastIndexOf('/');
        return separator > 0 ? path.substring(0, separator) : path;
    }

    private static void copyIfPresent(Path source, Path target) throws IOException {
        if (Files.isRegularFile(source, LinkOption.NOFOLLOW_LINKS)) {
            Files.copy(source, target, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private static void copyEvidenceTree(Path source, Path target) throws IOException {
        if (Files.isSymbolicLink(source)) throw new IOException("留痕资源不能是符号链接: " + source);
        if (Files.isRegularFile(source, LinkOption.NOFOLLOW_LINKS)) {
            Files.createDirectories(target.getParent());
            Files.copy(source, target, StandardCopyOption.REPLACE_EXISTING);
            return;
        }
        try (var paths = Files.walk(source)) {
            for (Path path : paths.sorted().toList()) {
                if (Files.isSymbolicLink(path)) throw new IOException("留痕资源不能包含符号链接: " + path);
                Path destination = target.resolve(source.relativize(path).toString());
                if (Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)) Files.createDirectories(destination);
                else Files.copy(path, destination, StandardCopyOption.REPLACE_EXISTING);
            }
        }
    }

    private static void writeEvidenceChecksums(Path evidence) throws IOException {
        Path checksumFile = evidence.resolve("checksums.sha256");
        StringBuilder contents = new StringBuilder();
        try (var paths = Files.walk(evidence)) {
            for (Path path : paths.filter(item -> Files.isRegularFile(item, LinkOption.NOFOLLOW_LINKS))
                    .filter(item -> !item.equals(checksumFile)).sorted().toList()) {
                contents.append(sha256(path)).append("  ")
                        .append(evidence.relativize(path).toString().replace('\\', '/')).append('\n');
            }
        }
        Files.writeString(checksumFile, contents, StandardCharsets.UTF_8);
    }

    private static void restrictLocalEvidencePermissions(Path evidence) throws IOException {
        if (!evidence.getFileSystem().supportedFileAttributeViews().contains("posix")) return;
        try (var paths = Files.walk(evidence)) {
            for (Path path : paths.toList()) {
                Files.setPosixFilePermissions(path, Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                        ? EnumSet.of(PosixFilePermission.OWNER_READ, PosixFilePermission.OWNER_WRITE,
                                PosixFilePermission.OWNER_EXECUTE)
                        : EnumSet.of(PosixFilePermission.OWNER_READ, PosixFilePermission.OWNER_WRITE));
            }
        }
    }

    private static String escapeEvidenceValue(String value) {
        return (value == null ? "" : value).replace("\\", "\\\\")
                .replace("\r", "\\r").replace("\n", "\\n");
    }

    private static String stableMessage(Exception exception) {
        return exception.getMessage() == null || exception.getMessage().isBlank()
                ? exception.getClass().getSimpleName() : exception.getMessage();
    }

    private static HealthResult evaluateClusterHealth(List<Node> nodes, String output) {
        String[] sections = (output == null ? "" : output).split("(?m)^__KF_PODS__$", 2);
        Set<String> expected = nodes.stream()
                .filter(node -> node.hasRole("control_plane") || node.hasRole("worker")
                        || Set.of("control_plane", "worker").contains(node.getRole()))
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

    private record ResolvedResource(Path localPath, String remotePath, String kind, String checksum) {
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
                    "containerd_root", k8sHome + "/containerd_root",
                    "etcd_data_dir", k8sHome + "/etcd_root"),
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
