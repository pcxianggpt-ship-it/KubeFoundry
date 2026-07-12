package io.kubefoundry.ssh;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.PublicKey;
import java.security.spec.ECGenParameterSpec;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import org.apache.sshd.common.file.virtualfs.VirtualFileSystemFactory;
import org.apache.sshd.common.config.keys.KeyUtils;
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
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class SshServiceTest {

    @TempDir
    Path temporaryDirectory;

    SshServer server;
    SshClientFactory clients;
    SshService service;
    KeyPair clientKeyPair;
    List<PublicKey> presentedKeys;

    @BeforeEach
    void startServer() throws Exception {
        Path remoteRoot = temporaryDirectory.resolve("remote");
        Files.createDirectory(remoteRoot);
        server = SshServer.setUpDefaultServer();
        server.setPort(0);
        KeyPairProvider hostKeys = new SimpleGeneratorHostKeyProvider(
                temporaryDirectory.resolve("host-key.ser"));
        server.setKeyPairProvider(hostKeys);
        server.setPasswordAuthenticator((username, password, session) ->
                "root".equals(username) && "secret".equals(password));
        KeyPairGenerator keyPairGenerator = KeyPairGenerator.getInstance("EC");
        keyPairGenerator.initialize(new ECGenParameterSpec("secp256r1"));
        clientKeyPair = keyPairGenerator.generateKeyPair();
        presentedKeys = new CopyOnWriteArrayList<>();
        server.setPublickeyAuthenticator((username, key, session) -> {
            presentedKeys.add(key);
            return "root".equals(username);
        });
        server.setCommandFactory((channel, command) -> new TestCommand(command));
        server.setSubsystemFactories(List.of(new SftpSubsystemFactory.Builder().build()));
        server.setFileSystemFactory(new VirtualFileSystemFactory(remoteRoot));
        server.start();

        clients = SshClientFactory.acceptingForTests();
        service = new SshService();
    }

    @AfterEach
    void stopServer() throws IOException {
        if (clients != null) clients.close();
        if (server != null) server.stop(true);
    }

    @Test
    void connectsWithPasswordAndCapturesCommandResult() throws Exception {
        SshConnectionSpec spec = new SshConnectionSpec("127.0.0.1", server.getPort(), "root",
                Duration.ofSeconds(3), Duration.ofSeconds(3));

        try (SshSession session = clients.connectWithPassword(spec, "secret".toCharArray())) {
            SshCommandResult result = service.execute(session, "success", Duration.ofSeconds(3));

            assertThat(result.exitCode()).isZero();
            assertThat(result.stdout()).isEqualTo("done\n");
            assertThat(result.stderr()).isEmpty();
        }
    }

    @Test
    void capturesNonZeroExitAndStderr() throws Exception {
        SshConnectionSpec spec = spec();
        try (SshSession session = clients.connectWithPassword(spec, "secret".toCharArray())) {
            SshCommandResult result = service.execute(session, "failure", Duration.ofSeconds(3));
            assertThat(result.exitCode()).isEqualTo(7);
            assertThat(result.stderr()).isEqualTo("failed\n");
        }
    }

    @Test
    void uploadsFileOverSftp() throws Exception {
        Path local = temporaryDirectory.resolve("source.txt");
        Files.writeString(local, "payload", StandardCharsets.UTF_8);
        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            service.upload(session, local, "/uploaded.txt");
        }

        assertThat(temporaryDirectory.resolve("remote/uploaded.txt"))
                .hasContent("payload");
    }

    @Test
    void rejectsInvalidPasswordWithoutLeakingIt() {
        assertThatThrownBy(() -> clients.connectWithPassword(spec(), "wrong-secret".toCharArray()))
                .isInstanceOf(SshAuthenticationException.class)
                .hasMessageNotContaining("wrong-secret");
    }

    @Test
    void connectsWithPublicKey() throws Exception {
        try (SshSession session = clients.connectWithKey(spec(), clientKeyPair)) {
            SshCommandResult result = service.execute(session, "success", Duration.ofSeconds(3));

            assertThat(result.exitCode()).isZero();
        }
        assertThat(presentedKeys)
                .isNotEmpty()
                .allMatch(key -> KeyUtils.compareKeys(clientKeyPair.getPublic(), key));
    }

    @Test
    void mapsCommandTimeoutToStableException() throws Exception {
        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            assertThatThrownBy(() -> service.execute(session, "slow", Duration.ofMillis(50)))
                    .isInstanceOf(SshCommandTimeoutException.class);
        }
    }

    private SshConnectionSpec spec() {
        return new SshConnectionSpec("127.0.0.1", server.getPort(), "root",
                Duration.ofSeconds(3), Duration.ofSeconds(3));
    }

    private static final class TestCommand extends AbstractCommandSupport {
        private TestCommand(String command) {
            super(command, null);
        }

        @Override
        public void run() {
            try {
                if ("success".equals(getCommand())) {
                    getOutputStream().write("done\n".getBytes(StandardCharsets.UTF_8));
                    getOutputStream().flush();
                    onExit(0);
                } else if ("slow".equals(getCommand())) {
                    Thread.sleep(500);
                    onExit(0);
                } else {
                    getErrorStream().write("failed\n".getBytes(StandardCharsets.UTF_8));
                    getErrorStream().flush();
                    onExit(7);
                }
            } catch (IOException exception) {
                onExit(1, exception.getMessage());
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                onExit(1, "interrupted");
            }
        }
    }
}
