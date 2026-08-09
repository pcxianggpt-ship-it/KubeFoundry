package io.kubefoundry.ssh;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
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
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;

class SshServiceTest {

    @TempDir
    Path temporaryDirectory;

    SshServer server;
    SshClientFactory clients;
    SshService service;
    Path remoteRoot;
    KeyPair clientKeyPair;
    List<PublicKey> presentedKeys;

    @BeforeEach
    void startServer() throws Exception {
        remoteRoot = temporaryDirectory.resolve("remote");
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
    void rejectsFinalRemoteSymlinkForSingleFileUpload() throws Exception {
        Path local = Files.writeString(
                temporaryDirectory.resolve("symlink-source.txt"), "replacement", StandardCharsets.UTF_8);
        Path outside = Files.writeString(remoteRoot.resolve("outside.txt"), "original", StandardCharsets.UTF_8);
        createSymbolicLinkOrSkip(remoteRoot.resolve("uploaded.txt"), Path.of("outside.txt"));

        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            assertThatThrownBy(() -> service.upload(session, local, "/uploaded.txt"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("远端文件");
        }

        assertThat(outside).hasContent("original");
    }

    @Test
    void rejectsFinalRemoteDirectoryForSingleFileUpload() throws Exception {
        Path local = Files.writeString(
                temporaryDirectory.resolve("directory-source.txt"), "replacement", StandardCharsets.UTF_8);
        Files.createDirectory(remoteRoot.resolve("uploaded.txt"));

        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            assertThatThrownBy(() -> service.upload(session, local, "/uploaded.txt"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("远端文件");
        }
    }

    @Test
    void rejectsParentRemoteSymlinkForSingleFileUpload() throws Exception {
        Path local = Files.writeString(
                temporaryDirectory.resolve("parent-symlink-source.txt"),
                "replacement",
                StandardCharsets.UTF_8);
        Path remoteParent = Files.createDirectory(remoteRoot.resolve("safe-upload"));
        Path outside = Files.createDirectory(remoteRoot.resolve("outside-upload"));
        createSymbolicLinkOrSkip(remoteParent.resolve("redirect"), Path.of("../outside-upload"));

        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            assertThatThrownBy(() -> service.upload(
                    session, local, "/safe-upload/redirect/payload.txt"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("远端目录");
        }

        assertThat(outside.resolve("payload.txt")).doesNotExist();
    }

    @Test
    void uploadsDirectoryTreeOverSftpIncludingEmptyDirectories() throws Exception {
        Path local = Files.createDirectory(temporaryDirectory.resolve("payload"));
        Files.createDirectories(local.resolve("bin/tools"));
        Files.createDirectories(local.resolve("empty"));
        Files.writeString(local.resolve("README.txt"), "root", StandardCharsets.UTF_8);
        Files.writeString(local.resolve("bin/tools/nerdctl"), "binary", StandardCharsets.UTF_8);

        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            service.uploadDirectory(session, local, "/runtime");
        }

        assertThat(temporaryDirectory.resolve("remote/runtime/README.txt")).hasContent("root");
        assertThat(temporaryDirectory.resolve("remote/runtime/bin/tools/nerdctl"))
                .hasContent("binary");
        assertThat(temporaryDirectory.resolve("remote/runtime/empty")).isDirectory();
    }

    @Test
    void rejectsFinalRemoteSymlinkForDirectoryFileUpload() throws Exception {
        Path local = Files.createDirectory(temporaryDirectory.resolve("symlink-payload"));
        Files.writeString(local.resolve("payload.txt"), "replacement", StandardCharsets.UTF_8);
        Path remoteDirectory = Files.createDirectory(remoteRoot.resolve("runtime"));
        Path outside = Files.writeString(remoteRoot.resolve("outside.txt"), "original", StandardCharsets.UTF_8);
        createSymbolicLinkOrSkip(remoteDirectory.resolve("payload.txt"), Path.of("../outside.txt"));

        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            assertThatThrownBy(() -> service.uploadDirectory(session, local, "/runtime"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("远端文件");
        }

        assertThat(outside).hasContent("original");
    }

    @Test
    void rejectsFinalRemoteDirectoryForDirectoryFileUpload() throws Exception {
        Path local = Files.createDirectory(temporaryDirectory.resolve("directory-payload-file"));
        Files.writeString(local.resolve("payload.txt"), "replacement", StandardCharsets.UTF_8);
        Path remoteDirectory = Files.createDirectory(remoteRoot.resolve("runtime"));
        Files.createDirectory(remoteDirectory.resolve("payload.txt"));

        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            assertThatThrownBy(() -> service.uploadDirectory(session, local, "/runtime"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("远端文件");
        }
    }

    @Test
    void rejectsSymbolicLinksAndRemoteTraversalDuringDirectoryUpload() throws Exception {
        Path local = Files.createDirectory(temporaryDirectory.resolve("unsafe-payload"));
        Path outside = Files.writeString(
                temporaryDirectory.resolve("outside.txt"), "secret", StandardCharsets.UTF_8);
        try {
            Files.createSymbolicLink(local.resolve("escape"), outside);
        } catch (UnsupportedOperationException | IOException exception) {
            org.junit.jupiter.api.Assumptions.assumeTrue(false, "当前平台不能创建符号链接");
        }

        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            assertThatThrownBy(() -> service.uploadDirectory(session, local, "/safe"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("符号链接");
            assertThatThrownBy(() -> service.uploadDirectory(session, local, "/safe/../escape"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("越界");
        }
    }

    @Test
    void rejectsRemoteDirectorySymlinksWithoutWritingOutsideTheUploadTree() throws Exception {
        Path local = Files.createDirectory(temporaryDirectory.resolve("safe-payload"));
        Files.createDirectories(local.resolve("nested"));
        Files.writeString(local.resolve("nested/payload.txt"), "payload", StandardCharsets.UTF_8);
        Path outside = Files.createDirectories(remoteRoot.resolve("outside"));
        Path remoteParent = Files.createDirectories(remoteRoot.resolve("safe/runtime"));
        try {
            Files.createSymbolicLink(remoteParent.resolve("nested"), Path.of("../../outside"));
        } catch (UnsupportedOperationException | IOException exception) {
            org.junit.jupiter.api.Assumptions.assumeTrue(false, "当前平台不能创建远端符号链接");
        }

        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            assertThatThrownBy(() -> service.uploadDirectory(session, local, "/safe/runtime"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("远端目录");
        }

        assertThat(outside.resolve("payload.txt")).doesNotExist();
    }

    @Test
    void rejectsRemotePathSegmentsThatAreNotDirectories() throws Exception {
        Path local = Files.createDirectory(temporaryDirectory.resolve("directory-payload"));
        Files.createDirectories(local.resolve("nested"));
        Files.writeString(local.resolve("nested/payload.txt"), "payload", StandardCharsets.UTF_8);
        Path remoteParent = Files.createDirectories(remoteRoot.resolve("safe-file/runtime"));
        Files.writeString(remoteParent.resolve("nested"), "not a directory", StandardCharsets.UTF_8);

        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            assertThatThrownBy(() -> service.uploadDirectory(session, local, "/safe-file/runtime"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("远端目录");
        }

        assertThat(Files.exists(
                remoteParent.resolve("nested/payload.txt"), LinkOption.NOFOLLOW_LINKS)).isFalse();
    }

    @Test
    void downloadsFileOverSftp() throws Exception {
        Files.writeString(temporaryDirectory.resolve("remote/artifact.txt"),
                "join command\n", StandardCharsets.UTF_8);
        Path local = temporaryDirectory.resolve("downloaded.txt");
        try (SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray())) {
            service.download(session, "/artifact.txt", local);
        }

        assertThat(local).hasContent("join command\n");
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

    @Test
    void closesClientPromptlyAfterRemoteDisconnect() throws Exception {
        SshSession session = clients.connectWithPassword(spec(), "secret".toCharArray());
        server.stop(true);
        server = null;

        assertTimeoutPreemptively(Duration.ofSeconds(7), () -> {
            try (session) {
                assertThatThrownBy(() -> service.execute(session, "success", Duration.ofSeconds(1)))
                        .isInstanceOfAny(IOException.class, IllegalStateException.class);
            }
            clients.close();
            clients = null;
        });
    }

    private SshConnectionSpec spec() {
        return new SshConnectionSpec("127.0.0.1", server.getPort(), "root",
                Duration.ofSeconds(3), Duration.ofSeconds(3));
    }

    private static void createSymbolicLinkOrSkip(Path link, Path target) {
        try {
            Files.createSymbolicLink(link, target);
        } catch (UnsupportedOperationException | IOException | SecurityException exception) {
            org.junit.jupiter.api.Assumptions.assumeTrue(false, "当前平台不能创建符号链接");
        }
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
