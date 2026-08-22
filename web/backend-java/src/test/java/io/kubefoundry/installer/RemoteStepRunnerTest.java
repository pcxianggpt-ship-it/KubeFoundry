package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.job.JobService;
import io.kubefoundry.ssh.SshClientFactory;
import io.kubefoundry.ssh.SshConnectionSpec;
import io.kubefoundry.ssh.SshService;
import io.kubefoundry.ssh.SshSession;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.spec.ECGenParameterSpec;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ConcurrentHashMap;
import org.junit.jupiter.api.Assumptions;
import org.apache.sshd.common.file.virtualfs.VirtualFileSystemFactory;
import org.apache.sshd.common.keyprovider.KeyPairProvider;
import org.apache.sshd.server.SshServer;
import org.apache.sshd.server.command.AbstractCommandSupport;
import org.apache.sshd.server.keyprovider.SimpleGeneratorHostKeyProvider;
import org.apache.sshd.sftp.server.SftpSubsystemFactory;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;

class RemoteStepRunnerTest {

    @TempDir
    Path temporaryDirectory;

    SshServer server;
    SshClientFactory clients;
    Path remoteRoot;
    List<String> commands;
    Map<String, AtomicInteger> verificationCalls;
    KeyPair clientKey;
    Cluster cluster;
    Node node;

    @BeforeEach
    void startServer() throws Exception {
        remoteRoot = Files.createDirectory(temporaryDirectory.resolve("remote"));
        commands = new CopyOnWriteArrayList<>();
        verificationCalls = new ConcurrentHashMap<>();
        server = SshServer.setUpDefaultServer();
        server.setPort(0);
        KeyPairProvider hostKeys = new SimpleGeneratorHostKeyProvider(
                temporaryDirectory.resolve("host-key.ser"));
        server.setKeyPairProvider(hostKeys);
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        clientKey = generator.generateKeyPair();
        server.setPublickeyAuthenticator((username, key, session) -> true);
        server.setCommandFactory((channel, command) -> new TestCommand(command));
        server.setSubsystemFactories(List.of(new SftpSubsystemFactory.Builder().build()));
        server.setFileSystemFactory(new VirtualFileSystemFactory(remoteRoot));
        server.start();
        clients = new SshClientFactory((session, address, key) -> true);

        cluster = new Cluster("runner-test");
        cluster.update(null, null, "1.29.3", "10.244.0.0/16", "10.96.0.0/12",
                "registry", "10.0.0.9", 5000, null);
        node = RuntimeEnvRendererTest.node(
                cluster, "cp-a", "127.0.0.1", "control_plane", "amd64");
        node.update(null, null, null, null, "root", server.getPort());
    }

    @AfterEach
    void stopServer() throws IOException {
        if (clients != null) clients.close();
        if (server != null) server.stop(true);
    }

    @Test
    void createsRemoteDirectoryThenUploadsRuntimeAndScriptAndCapturesOutput() throws Exception {
        Path script = temporaryDirectory.resolve("step.sh");
        Files.writeString(script, "#!/bin/bash\nprintf 'script must not run locally\\n'\n",
                StandardCharsets.UTF_8);
        InstallStep step = InstallStep.script(
                "test-step", "测试步骤", "test", "primary_control_plane", script,
                "serial", 1, true, List.of(), List.of(), List.of(), "printf verified");
        RemoteStepRunner runner = runner();

        JobService.NodeOutcome outcome = runner.run(
                42L, cluster, List.of(node), node, step);

        assertThat(outcome.success()).isTrue();
        assertThat(outcome.exitCode()).isZero();
        assertThat(outcome.message()).isEqualTo("执行成功");
        assertThat(outcome.logPath()).isEqualTo(temporaryDirectory.resolve(
                "data/jobs/42/logs/test-step/cp-a.log").toAbsolutePath().normalize().toString());
        assertThat(Path.of(outcome.logPath())).hasContent("stdout\nstderr\n");
        assertThat(commands).hasSize(3);
        assertThat(commands.get(0)).startsWith("bash -lc ").contains("mkdir -p");
        assertThat(commands.get(1)).contains("chmod -R go-rwx --", "/tmp/kubefoundry/jobs/42");
        assertThat(commands.get(2)).startsWith("bash -lc ")
                .contains("/tmp/kubefoundry/jobs/42/steps/test-step/cp-a/")
                .contains("source ./runtime.env")
                .contains("bash ./step.sh")
                .contains("printf verified");
        Path remoteStep = remoteRoot.resolve("tmp/kubefoundry/jobs/42/steps/test-step/cp-a");
        assertThat(remoteStep.resolve("runtime.env")).isRegularFile();
        assertThat(remoteStep.resolve("step.sh")).hasSameTextualContentAs(script);
        Path evidence = temporaryDirectory.resolve("data/jobs/42/evidence/test-step/cp-a");
        assertThat(evidence.resolve("runtime.env")).isRegularFile();
        assertThat(evidence.resolve("step.sh")).hasSameTextualContentAs(script);
        assertThat(evidence.resolve("execution.log")).hasContent("stdout\nstderr\n");
        assertThat(Files.readString(evidence.resolve("result.properties")))
                .contains("success=true", "exit_code=0", "step_key=test-step");
        assertThat(Files.readString(evidence.resolve("checksums.sha256")))
                .contains("runtime.env", "step.sh", "execution.log", "result.properties");
    }

    @Test
    void skipsSatisfiedStepBeforeResolvingOrUploadingInstallResources() throws Exception {
        Path script = temporaryDirectory.resolve("pre-satisfied-step.sh");
        Path verify = temporaryDirectory.resolve("pre-satisfied-verify.sh");
        Path missingResource = temporaryDirectory.resolve("must-not-be-resolved.tgz");
        Files.writeString(script, "#!/bin/bash\n", StandardCharsets.UTF_8);
        Files.writeString(verify, "#!/bin/bash\nexit 0\n", StandardCharsets.UTF_8);
        InstallStep step = InstallStep.script(
                "pre-satisfied", "已安装步骤", "test", "primary_control_plane", script,
                "serial", 1, true,
                List.of(InstallStep.Resource.local(missingResource, "file", "/tmp/missing.tgz")),
                List.of(), List.of(), "").withVerification(verify);

        JobService.NodeOutcome outcome = runner().run(42L, cluster, List.of(node), node, step);

        assertThat(outcome.success()).isTrue();
        assertThat(outcome.status()).isEqualTo("skipped");
        assertThat(outcome.message()).isEqualTo("PREVERIFY_SATISFIED");
        assertThat(outcome.verificationPhase()).isEqualTo("before");
        assertThat(commands).noneMatch(command -> command.contains("bash ./step.sh"));
        Path remoteStep = remoteRoot.resolve("tmp/kubefoundry/jobs/42/steps/pre-satisfied/cp-a");
        assertThat(remoteStep.resolve("verify.sh")).isRegularFile();
        assertThat(remoteStep.resolve("step.sh")).doesNotExist();
        Path evidence = temporaryDirectory.resolve("data/jobs/42/evidence/pre-satisfied/cp-a");
        assertThat(evidence.resolve("verification-before.properties"))
                .hasContent("phase=before\nexit_code=0\n");
    }

    @Test
    void recoversRequiredOutputsWhenInitializationIsPreverified() throws Exception {
        Path script = temporaryDirectory.resolve("recover-init-step.sh");
        Path verify = temporaryDirectory.resolve("recover-init-verify.sh");
        Path recovery = temporaryDirectory.resolve("recover-init-outputs.sh");
        Files.writeString(script, "#!/bin/bash\n", StandardCharsets.UTF_8);
        Files.writeString(verify, "#!/bin/bash\nexit 0\n", StandardCharsets.UTF_8);
        Files.writeString(recovery, "#!/bin/bash\nexit 0\n", StandardCharsets.UTF_8);
        InstallStep step = InstallStep.script(
                "recover-init", "恢复 Join 产物", "test", "primary_control_plane", script,
                "serial", 1, true, List.of(), List.of(),
                List.of(new InstallStep.Output("control_join", "/tmp/k8s/kube_join_master"),
                        new InstallStep.Output("worker_join", "/tmp/k8s/kube_join_nodes")), "")
                .withVerificationAndRecovery(verify, recovery);

        JobService.NodeOutcome outcome = runner().run(42L, cluster, List.of(node), node, step);

        assertThat(outcome.status()).isEqualTo("skipped");
        assertThat(commands).anyMatch(command -> command.contains("bash ./recovery.sh"));
        assertThat(commands).noneMatch(command -> command.contains("bash ./step.sh"));
        Path artifacts = temporaryDirectory.resolve("data/jobs/42/artifacts");
        assertThat(artifacts.resolve("control_join")).hasContent("control-command");
        assertThat(artifacts.resolve("worker_join")).hasContent("worker-command");
        Path evidence = temporaryDirectory.resolve("data/jobs/42/evidence/recover-init/cp-a");
        assertThat(evidence.resolve("recovery.properties")).hasContent("exit_code=0\n");
        assertThat(evidence.resolve("outputs/control_join")).hasContent("control-command");
        assertThat(evidence.resolve("outputs/worker_join")).hasContent("worker-command");
    }

    @Test
    void installsOnlyAfterExitTenAndRequiresSuccessfulPostVerification() throws Exception {
        Path script = temporaryDirectory.resolve("strict-install-step.sh");
        Path verify = temporaryDirectory.resolve("strict-install-verify.sh");
        Path resource = temporaryDirectory.resolve("strict-install-resource.tgz");
        Files.writeString(script, "#!/bin/bash\n", StandardCharsets.UTF_8);
        Files.writeString(verify, "#!/bin/bash\nexit 10\n", StandardCharsets.UTF_8);
        Files.writeString(resource, "payload", StandardCharsets.UTF_8);
        InstallStep step = InstallStep.script(
                "strict-install", "严格验证安装", "test", "primary_control_plane", script,
                "serial", 1, true,
                List.of(InstallStep.Resource.local(resource, "file", "/tmp/strict-install.tgz")),
                List.of(), List.of(), "").withVerification(verify);

        JobService.NodeOutcome outcome = runner().run(42L, cluster, List.of(node), node, step);

        assertThat(outcome.success()).isTrue();
        assertThat(outcome.status()).isEqualTo("success");
        assertThat(outcome.verificationPhase()).isEqualTo("after");
        assertThat(commands.stream().filter(command -> command.contains("bash ./verify.sh"))).hasSize(2);
        assertThat(commands.stream().filter(command -> command.contains("bash ./step.sh"))).hasSize(1);
        assertThat(remoteRoot.resolve("tmp/strict-install.tgz")).hasContent("payload");
        Path evidence = temporaryDirectory.resolve("data/jobs/42/evidence/strict-install/cp-a");
        assertThat(evidence.resolve("verification-before.properties"))
                .hasContent("phase=before\nexit_code=10\n");
        assertThat(evidence.resolve("verification-after.properties"))
                .hasContent("phase=after\nexit_code=0\n");
    }

    @Test
    void rejectsVerificationConfigurationErrorWithoutRunningInstall() throws Exception {
        Path script = temporaryDirectory.resolve("strict-error-step.sh");
        Path verify = temporaryDirectory.resolve("strict-error-verify.sh");
        Files.writeString(script, "#!/bin/bash\n", StandardCharsets.UTF_8);
        Files.writeString(verify, "#!/bin/bash\nexit 20\n", StandardCharsets.UTF_8);
        InstallStep step = InstallStep.script(
                "strict-error", "验证配置错误", "test", "primary_control_plane", script,
                "serial", 1, true, List.of(), List.of(), List.of(), "").withVerification(verify);

        JobService.NodeOutcome outcome = runner().run(42L, cluster, List.of(node), node, step);

        assertThat(outcome.success()).isFalse();
        assertThat(outcome.message()).isEqualTo("PREVERIFY_FAILED/CONFIGURATION_ERROR/exit_code=20");
        assertThat(outcome.verificationPhase()).isEqualTo("before");
        assertThat(commands).noneMatch(command -> command.contains("bash ./step.sh"));
    }

    @Test
    void distinguishesVerificationTimeoutAndUnknownExitCodes() throws Exception {
        JobService.NodeOutcome timeout = runner().run(
                42L, cluster, List.of(node), node, strictStep("strict-timeout"));
        JobService.NodeOutcome unknown = runner().run(
                42L, cluster, List.of(node), node, strictStep("strict-unknown"));

        assertThat(timeout.success()).isFalse();
        assertThat(timeout.message()).isEqualTo("PREVERIFY_FAILED/VERIFICATION_TIMEOUT/exit_code=21");
        assertThat(unknown.success()).isFalse();
        assertThat(unknown.message()).isEqualTo("PREVERIFY_FAILED/VERIFICATION_ERROR/exit_code=37");
    }

    @Test
    void failsStepWhenPostVerificationDoesNotPass() throws Exception {
        JobService.NodeOutcome outcome = runner().run(
                42L, cluster, List.of(node), node, strictStep("strict-post-fail"));

        assertThat(outcome.success()).isFalse();
        assertThat(outcome.message()).isEqualTo("POSTVERIFY_FAILED/CONFIGURATION_ERROR/exit_code=20");
        assertThat(outcome.verificationPhase()).isEqualTo("after");
        assertThat(commands.stream().filter(command -> command.contains("bash ./step.sh"))).hasSize(1);
    }

    @Test
    void ordersRuntimeScriptSafeArgumentsAndVerifyWithoutExecutingTheUploadedScript() throws Exception {
        Path script = temporaryDirectory.resolve("syntax-only-step.sh");
        Files.writeString(script, "#!/bin/bash\nexit 47\n", StandardCharsets.UTF_8);
        String maliciousArgument = "value'; touch /tmp/kubefoundry-command-injection; #";
        InstallStep step = InstallStep.script(
                "syntax-only", "命令链", "test", "primary_control_plane", script,
                "serial", 1, true, List.of(),
                List.of(new InstallStep.Argument(maliciousArgument, null)), List.of(),
                "test {node_hostname} = {node_hostname}");

        JobService.NodeOutcome outcome = runner().run(42L, cluster, List.of(node), node, step);

        assertThat(outcome.success()).isTrue();
        String command = unquoteBashLoginCommand(commands.get(commands.size() - 1));
        assertThat(command)
                .containsSubsequence(
                        "source ./runtime.env",
                        "bash ./step.sh 'value'\"'\"'; touch /tmp/kubefoundry-command-injection; #'",
                        "test 'cp-a' = 'cp-a'");
        assertThat(command).doesNotContain("bash ./step.sh value'; touch");

        Path compatibilityDirectory = Files.createDirectory(temporaryDirectory.resolve("bash-compatibility"));
        Path runtime = compatibilityDirectory.resolve("runtime.env");
        Path uploadedScript = compatibilityDirectory.resolve("step.sh");
        Files.copy(remoteRoot.resolve("tmp/kubefoundry/jobs/42/steps/syntax-only/cp-a/runtime.env"), runtime);
        Files.copy(remoteRoot.resolve("tmp/kubefoundry/jobs/42/steps/syntax-only/cp-a/step.sh"), uploadedScript);
        String bash = availableBash();
        Assumptions.assumeTrue(bash != null, "当前环境未提供 Bash，跳过语法兼容检查");
        assertThat(runBash(bash, "-n", runtime.toString())).isZero();
        assertThat(runBash(bash, "-n", uploadedScript.toString())).isZero();
        assertThat(runBash(bash, "-c", "set -e; source \"$1\"", "bash", runtime.toString())).isZero();
    }

    @Test
    void returnsStableFailureSummaryAndExitCode() throws Exception {
        Path script = temporaryDirectory.resolve("fail-step.sh");
        Files.writeString(script, "#!/bin/bash\nexit 7\n", StandardCharsets.UTF_8);
        InstallStep step = InstallStep.script(
                "fail-step", "失败步骤", "test", "primary_control_plane", script,
                "serial", 1, true, List.of(), List.of(), List.of(), "");

        JobService.NodeOutcome outcome = runner().run(
                7L, cluster, List.of(node), node, step);

        assertThat(outcome.success()).isFalse();
        assertThat(outcome.exitCode()).isEqualTo(7);
        assertThat(outcome.message()).isEqualTo("执行失败，退出码: 7");
        assertThat(Path.of(outcome.logPath())).hasContent("failed\n");
        Path evidence = temporaryDirectory.resolve("data/jobs/7/evidence/fail-step/cp-a");
        assertThat(Files.readString(evidence.resolve("result.properties")))
                .contains("success=false", "exit_code=7");
        assertThat(evidence.resolve("execution.log")).hasContent("failed\n");
    }

    @Test
    void retainsCommandLogResultAndChecksumEvidence() throws Exception {
        RemoteStepRunner.CommandOutcome outcome = runner().runCommandCapture(
                9L, cluster, node, "inspect-state", "printf state", Duration.ofSeconds(10));

        assertThat(outcome.exitCode()).isZero();
        Path evidence = temporaryDirectory.resolve("data/jobs/9/evidence/inspect-state/cp-a");
        assertThat(evidence.resolve("command.sh")).hasContent("#!/bin/bash\nprintf state\n");
        assertThat(evidence.resolve("execution.log")).hasContent("stdout\nstderr\n");
        assertThat(Files.readString(evidence.resolve("result.properties")))
                .contains("success=true", "exit_code=0");
        assertThat(Files.readString(evidence.resolve("checksums.sha256")))
                .contains("command.sh", "execution.log", "result.properties");
    }

    @Test
    void uploadsDirectoryResourceTreeAndThenExecutesStep() throws Exception {
        Path directory = Files.createDirectory(temporaryDirectory.resolve("payload"));
        Files.createDirectories(directory.resolve("bin/tools"));
        Files.writeString(directory.resolve("bin/tools/containerd"), "binary", StandardCharsets.UTF_8);
        Files.writeString(directory.resolve("tenant.env"), "plain-text-secret", StandardCharsets.UTF_8);
        Path script = temporaryDirectory.resolve("directory-step.sh");
        Files.writeString(script, "#!/bin/bash\n", StandardCharsets.UTF_8);
        InstallStep step = InstallStep.script(
                "directory-step", "目录资源", "test", "primary_control_plane", script,
                "serial", 1, true,
                List.of(InstallStep.Resource.local(directory, "directory",
                        "/tmp/kubefoundry/jobs/{job_id}/resources/shared")),
                List.of(), List.of(), "");

        JobService.NodeOutcome outcome = runner().run(
                8L, cluster, List.of(node), node, step,
                new RemoteStepRunner.RuntimePaths());

        assertThat(outcome.success()).isTrue();
        assertThat(remoteRoot.resolve("tmp/kubefoundry/jobs/8/resources/shared/bin/tools/containerd"))
                .hasContent("binary");
        assertThat(remoteRoot.resolve("tmp/kubefoundry/jobs/8/resources/shared/tenant.env"))
                .hasContent("plain-text-secret");
        assertThat(commands).noneMatch(command -> command.contains("rm -rf --"));
        Path evidence = temporaryDirectory.resolve(
                "data/jobs/8/evidence/directory-step/cp-a/resources/01-payload");
        assertThat(evidence.resolve("bin/tools/containerd")).hasContent("binary");
        assertThat(evidence.resolve("tenant.env")).hasContent("plain-text-secret");
    }

    @Test
    void usesTheSamePrimaryControlPlaneByIdForArgumentsAndVerifyPlaceholders() throws Exception {
        ReflectionTestUtils.setField(node, "id", 20L);
        node.update("a-control", null, null, null, null, null);
        Node primary = RuntimeEnvRendererTest.node(
                cluster, "z-control", "10.0.0.10", "control_plane", "amd64");
        ReflectionTestUtils.setField(primary, "id", 10L);
        Path script = temporaryDirectory.resolve("primary.sh");
        Files.writeString(script, "#!/bin/bash\n", StandardCharsets.UTF_8);
        InstallStep step = InstallStep.script("primary", "主控参数", "test", "control_plane", script,
                "serial", 1, true, List.of(),
                List.of(new InstallStep.Argument(null, "primary_control_ip")), List.of(),
                "test {primary_control_ip} = {primary_control_ip}");

        JobService.NodeOutcome outcome = runner().run(42L, cluster, List.of(node, primary), node, step);

        assertThat(outcome.success()).isTrue();
        assertThat(commands.get(commands.size() - 1)).contains("10.0.0.10").doesNotContain("10.0.0.20");
    }

    @Test
    void normalizesDuplicateIpsForRuntimeArgumentsAndVerifyPlaceholders() throws Exception {
        ReflectionTestUtils.setField(node, "id", 10L);
        node.update("worker-a", null, null, "worker", null, null);
        Node duplicateControl = RuntimeEnvRendererTest.node(
                cluster, "duplicate-control", "127.0.0.1", "control_plane", "amd64");
        Node canonicalControl = RuntimeEnvRendererTest.node(
                cluster, "cp-primary", "10.0.0.30", "control_plane", "amd64");
        ReflectionTestUtils.setField(duplicateControl, "id", 20L);
        ReflectionTestUtils.setField(canonicalControl, "id", 30L);
        Path script = temporaryDirectory.resolve("normalized-primary.sh");
        Files.writeString(script, "#!/bin/bash\n", StandardCharsets.UTF_8);
        InstallStep step = InstallStep.script(
                "normalized-primary", "规范化主控", "test", "all_nodes", script,
                "serial", 1, true, List.of(),
                List.of(new InstallStep.Argument(null, "primary_control_ip")), List.of(),
                "test {primary_control_hostname} = {primary_control_hostname}");

        JobService.NodeOutcome outcome = runner().run(42L, cluster,
                List.of(duplicateControl, canonicalControl, node), node, step);

        assertThat(outcome.success()).isTrue();
        assertThat(commands.get(commands.size() - 1))
                .contains("10.0.0.30", "cp-primary")
                .doesNotContain("duplicate-control");
        assertThat(Files.readString(remoteRoot.resolve(
                "tmp/kubefoundry/jobs/42/steps/normalized-primary/worker-a/runtime.env")))
                .contains("export KF_PRIMARY_CONTROL_IP='10.0.0.30'");
    }

    @Test
    void retriesTransientClusterHealthFailuresWithoutWaitingInTests() {
        AtomicInteger attempts = new AtomicInteger();
        RemoteStepRunner runner = healthRunner(attempts, List.of(
                new RemoteStepRunner.CommandOutcome(1, "", "temporary", "health.log"),
                healthyHealthOutput()));
        InstallStep step = InstallStep.builtin("health", "健康", "verify", "primary_control_plane",
                "cluster_health", "serial", 1, true, "");

        JobService.NodeOutcome outcome = runner.run(1L, cluster, List.of(node), node, step);

        assertThat(outcome.success()).isTrue();
        assertThat(attempts).hasValue(2);
    }

    @Test
    void failsClusterHealthAfterTheConfiguredFinalAttempt() {
        AtomicInteger attempts = new AtomicInteger();
        RemoteStepRunner runner = healthRunner(attempts, List.of(
                new RemoteStepRunner.CommandOutcome(0,
                        "cp-a NotReady\n__KF_PODS__\nkube-flannel flannel 0/1 Pending\n", "", "health.log")));
        InstallStep step = InstallStep.builtin("health", "健康", "verify", "primary_control_plane",
                "cluster_health", "serial", 1, true, "");

        JobService.NodeOutcome outcome = runner.run(1L, cluster, List.of(node), node, step);

        assertThat(outcome.success()).isFalse();
        assertThat(attempts).hasValue(3);
    }

    @Test
    void writesRegistryAliasForExternalRegistryWithSafelyQuotedHostsLines() throws Exception {
        cluster.update(null, null, null, null, null,
                "registry'; touch /tmp/pwn; #", "10.0.0.9", null, null);
        InstallStep step = InstallStep.builtin("hostname", "主机名", "k8s_base", "all_nodes",
                "setup_hostname", "serial", 1, true, "");

        JobService.NodeOutcome outcome = runner().run(42L, cluster, List.of(node), node, step);

        assertThat(outcome.success()).isTrue();
        String script = Files.readString(remoteRoot.resolve(
                "tmp/kubefoundry/jobs/42/steps/hostname/cp-a/step.sh"));
        assertThat(script).contains("registry'\"'\"'; touch /tmp/pwn; #");
        assertThat(script).contains("printf '%s\\n'");
        assertThat(script).doesNotContain("cat >> /etc/hosts <<");
    }

    @Test
    void writesNodeAndRegistryNamesWhenTheyShareTheSameIp() throws Exception {
        cluster.update(null, null, null, null, null, "registry-alias", "127.0.0.1", null, null);
        node.replaceRoles(List.of("control_plane", "registry"));
        InstallStep step = InstallStep.builtin("hostname", "主机名", "k8s_base", "all_nodes",
                "setup_hostname", "serial", 1, true, "");

        JobService.NodeOutcome outcome = runner().run(42L, cluster, List.of(node), node, step);

        assertThat(outcome.success()).isTrue();
        assertThat(Files.readString(remoteRoot.resolve(
                "tmp/kubefoundry/jobs/42/steps/hostname/cp-a/step.sh")))
                .contains("'127.0.0.1    cp-a registry'");
    }

    @Test
    void usesRuntimeRegistryFallbackForHostsAliasWhenHostnameIsBlank() throws Exception {
        cluster.update(null, null, null, null, null, "   ", "127.0.0.1", null, null);
        InstallStep step = InstallStep.builtin("hostname", "主机名", "k8s_base", "all_nodes",
                "setup_hostname", "serial", 1, true, "");

        JobService.NodeOutcome outcome = runner().run(42L, cluster, List.of(node), node, step);

        assertThat(outcome.success()).isTrue();
        assertThat(Files.readString(remoteRoot.resolve(
                "tmp/kubefoundry/jobs/42/steps/hostname/cp-a/step.sh")))
                .contains("'127.0.0.1    cp-a registry'");
        assertThat(Files.readString(remoteRoot.resolve(
                "tmp/kubefoundry/jobs/42/steps/hostname/cp-a/runtime.env")))
                .contains("export KF_REGISTRY_HOSTNAME='registry'");
    }

    private RemoteStepRunner healthRunner(
            AtomicInteger attempts, List<RemoteStepRunner.CommandOutcome> outcomes) {
        return new RemoteStepRunner(null, null, new RuntimeEnvRenderer(), temporaryDirectory.resolve("data"),
                new RemoteStepRunner.ClusterHealthRetryPolicy(3, Duration.ofSeconds(10), duration -> { })) {
            @Override
            public CommandOutcome runCommandCapture(
                    long jobId, Cluster targetCluster, Node target, String stepKey, String command,
                    Duration timeout) {
                int index = attempts.getAndIncrement();
                return outcomes.get(Math.min(index, outcomes.size() - 1));
            }
        };
    }

    private static RemoteStepRunner.CommandOutcome healthyHealthOutput() {
        return new RemoteStepRunner.CommandOutcome(0,
                "cp-a Ready\n__KF_PODS__\nkube-flannel flannel 1/1 Running\n", "", "health.log");
    }

    private RemoteStepRunner runner() {
        return new RemoteStepRunner(
                new SshService(),
                (targetCluster, target, work) -> {
                    SshConnectionSpec spec = new SshConnectionSpec(
                            target.getIp(), target.getSshPort(), target.getSshUser(),
                            Duration.ofSeconds(3), Duration.ofSeconds(3));
                    try (SshSession session = clients.connectWithKey(spec, clientKey)) {
                        return work.apply(session);
                    }
                },
                new RuntimeEnvRenderer(),
                temporaryDirectory.resolve("data"));
    }

    private InstallStep strictStep(String key) throws IOException {
        Path script = temporaryDirectory.resolve(key + "-step.sh");
        Path verify = temporaryDirectory.resolve(key + "-verify.sh");
        Files.writeString(script, "#!/bin/bash\n", StandardCharsets.UTF_8);
        Files.writeString(verify, "#!/bin/bash\n", StandardCharsets.UTF_8);
        return InstallStep.script(key, key, "test", "primary_control_plane", script,
                "serial", 1, true, List.of(), List.of(), List.of(), "")
                .withVerification(verify);
    }

    private static String availableBash() {
        List<String> candidates = System.getProperty("os.name").startsWith("Windows")
                ? List.of("C:/Program Files/Git/bin/bash.exe", "bash")
                : List.of("bash");
        for (String candidate : candidates) {
            try {
                if (new ProcessBuilder(candidate, "--version").start().waitFor() == 0) return candidate;
            } catch (IOException | InterruptedException exception) {
                if (exception instanceof InterruptedException) Thread.currentThread().interrupt();
            }
        }
        return null;
    }

    private static int runBash(String bash, String... arguments) throws Exception {
        String[] command = new String[arguments.length + 1];
        command[0] = bash;
        System.arraycopy(arguments, 0, command, 1, arguments.length);
        return new ProcessBuilder(command).start().waitFor();
    }

    private static String unquoteBashLoginCommand(String command) {
        assertThat(command).startsWith("bash -lc '").endsWith("'");
        return command.substring("bash -lc '".length(), command.length() - 1)
                .replace("'\"'\"'", "'");
    }

    private final class TestCommand extends AbstractCommandSupport {
        private TestCommand(String command) {
            super(command, null);
        }

        @Override
        public void run() {
            commands.add(getCommand());
            try {
                if (getCommand().contains("mkdir -p")) {
                    Files.createDirectories(remoteRoot.resolve("tmp/kubefoundry/")
                            .resolve(getCommand().contains("/42/") ? "42" :
                                    getCommand().contains("/7/") ? "7" : "8"));
                    onExit(0);
                } else if (getCommand().contains("/strict-install/")
                        && getCommand().contains("bash ./verify.sh")) {
                    int attempt = verificationCalls.computeIfAbsent(
                            "strict-install", ignored -> new AtomicInteger()).getAndIncrement();
                    onExit(attempt == 0 ? 10 : 0);
                } else if (getCommand().contains("/strict-error/")
                        && getCommand().contains("bash ./verify.sh")) {
                    onExit(20);
                } else if (getCommand().contains("/strict-timeout/")
                        && getCommand().contains("bash ./verify.sh")) {
                    onExit(21);
                } else if (getCommand().contains("/strict-unknown/")
                        && getCommand().contains("bash ./verify.sh")) {
                    onExit(37);
                } else if (getCommand().contains("/strict-post-fail/")
                        && getCommand().contains("bash ./verify.sh")) {
                    int attempt = verificationCalls.computeIfAbsent(
                            "strict-post-fail", ignored -> new AtomicInteger()).getAndIncrement();
                    onExit(attempt == 0 ? 10 : 20);
                } else if (getCommand().contains("/recover-init/")
                        && getCommand().contains("bash ./recovery.sh")) {
                    Path outputDirectory = remoteRoot.resolve("tmp/k8s");
                    Files.createDirectories(outputDirectory);
                    Files.writeString(outputDirectory.resolve("kube_join_master"),
                            "control-command\n", StandardCharsets.UTF_8);
                    Files.writeString(outputDirectory.resolve("kube_join_nodes"),
                            "worker-command\n", StandardCharsets.UTF_8);
                    onExit(0);
                } else if (getCommand().contains("/tmp/kubefoundry/jobs/7/steps/")
                        && getCommand().contains("bash ./step.sh")) {
                    getErrorStream().write("failed\n".getBytes(StandardCharsets.UTF_8));
                    getErrorStream().flush();
                    onExit(7);
                } else {
                    getOutputStream().write("stdout\n".getBytes(StandardCharsets.UTF_8));
                    getErrorStream().write("stderr\n".getBytes(StandardCharsets.UTF_8));
                    getOutputStream().flush();
                    getErrorStream().flush();
                    onExit(0);
                }
            } catch (IOException exception) {
                onExit(1, exception.getMessage());
            }
        }
    }
}
