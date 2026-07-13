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
import java.util.concurrent.CopyOnWriteArrayList;
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

import static org.assertj.core.api.Assertions.assertThat;

class RemoteStepRunnerTest {

    @TempDir
    Path temporaryDirectory;

    SshServer server;
    SshClientFactory clients;
    Path remoteRoot;
    List<String> commands;
    KeyPair clientKey;
    Cluster cluster;
    Node node;

    @BeforeEach
    void startServer() throws Exception {
        remoteRoot = Files.createDirectory(temporaryDirectory.resolve("remote"));
        commands = new CopyOnWriteArrayList<>();
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
        assertThat(commands).hasSize(2);
        assertThat(commands.get(0)).startsWith("bash -lc ").contains("mkdir -p");
        assertThat(commands.get(1)).startsWith("bash -lc ")
                .contains("/tmp/kubefoundry/42/")
                .contains("source ./runtime.env")
                .contains("bash ./step.sh")
                .contains("printf verified");
        assertThat(remoteRoot.resolve("tmp/kubefoundry/42/runtime.env")).isRegularFile();
        assertThat(remoteRoot.resolve("tmp/kubefoundry/42/step.sh")).hasSameTextualContentAs(script);
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
    }

    @Test
    void uploadsDirectoryResourceTreeAndThenExecutesStep() throws Exception {
        Path directory = Files.createDirectory(temporaryDirectory.resolve("payload"));
        Files.createDirectories(directory.resolve("bin/tools"));
        Files.writeString(directory.resolve("bin/tools/containerd"), "binary", StandardCharsets.UTF_8);
        Path script = temporaryDirectory.resolve("directory-step.sh");
        Files.writeString(script, "#!/bin/bash\n", StandardCharsets.UTF_8);
        InstallStep step = InstallStep.script(
                "directory-step", "目录资源", "test", "primary_control_plane", script,
                "serial", 1, true,
                List.of(new InstallStep.Resource("container_runtime", null, "directory", "/tmp/runtime")),
                List.of(), List.of(), "");

        JobService.NodeOutcome outcome = runner().run(
                8L, cluster, List.of(node), node, step,
                new RemoteStepRunner.RuntimePaths().with("container_runtime", directory));

        assertThat(outcome.success()).isTrue();
        assertThat(remoteRoot.resolve("tmp/runtime/bin/tools/containerd")).hasContent("binary");
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
                } else if (getCommand().contains("/tmp/kubefoundry/7/")) {
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
