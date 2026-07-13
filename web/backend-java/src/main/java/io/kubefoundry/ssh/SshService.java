package io.kubefoundry.ssh;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.SimpleFileVisitor;
import java.time.Duration;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import org.apache.sshd.client.channel.ChannelExec;
import org.apache.sshd.client.channel.ClientChannelEvent;
import org.apache.sshd.sftp.client.SftpClient;
import org.apache.sshd.sftp.client.SftpClientFactory;
import org.apache.sshd.sftp.common.SftpException;
import org.springframework.stereotype.Service;

@Service
public final class SshService {

    private static final int MAX_CAPTURE_BYTES = 1024 * 1024;

    public SshCommandResult execute(SshSession session, String command, Duration timeout) throws IOException {
        if (session == null) throw new IllegalArgumentException("SSH 会话不能为空");
        if (command == null || command.isBlank()) throw new IllegalArgumentException("远程命令不能为空");
        if (timeout == null || timeout.isZero() || timeout.isNegative()) {
            throw new IllegalArgumentException("命令超时必须大于 0");
        }

        LimitedOutputStream stdout = new LimitedOutputStream(MAX_CAPTURE_BYTES);
        LimitedOutputStream stderr = new LimitedOutputStream(MAX_CAPTURE_BYTES);
        try (ChannelExec channel = session.delegate().createExecChannel(command)) {
            channel.setOut(stdout);
            channel.setErr(stderr);
            channel.open().verify(timeout);
            Set<ClientChannelEvent> events = channel.waitFor(
                    EnumSet.of(ClientChannelEvent.CLOSED), timeout);
            if (events.contains(ClientChannelEvent.TIMEOUT) || channel.getExitStatus() == null) {
                throw new SshCommandTimeoutException("远程命令执行超时");
            }
            return new SshCommandResult(
                    channel.getExitStatus(), stdout.asString(), stderr.asString());
        }
    }

    public void upload(SshSession session, Path local, String remotePath) throws IOException {
        if (session == null) throw new IllegalArgumentException("SSH 会话不能为空");
        if (local == null || !Files.isRegularFile(local)) {
            throw new IllegalArgumentException("本地上传文件不存在");
        }
        if (remotePath == null || remotePath.isBlank()) {
            throw new IllegalArgumentException("远端路径不能为空");
        }
        try (SftpClient sftp = SftpClientFactory.instance().createSftpClient(session.delegate())) {
            sftp.put(local, remotePath);
        }
    }

    public void uploadDirectory(SshSession session, Path localDirectory, String remoteDirectory)
            throws IOException {
        if (session == null) throw new IllegalArgumentException("SSH 会话不能为空");
        if (localDirectory == null || !Files.isDirectory(localDirectory, LinkOption.NOFOLLOW_LINKS)) {
            throw new IllegalArgumentException("本地上传目录不存在");
        }
        if (Files.isSymbolicLink(localDirectory)) {
            throw new IllegalArgumentException("本地上传目录不能是符号链接");
        }
        String normalizedRemote = normalizeRemoteDirectory(remoteDirectory);
        Path root = localDirectory.toAbsolutePath().normalize();
        try (SftpClient sftp = SftpClientFactory.instance().createSftpClient(session.delegate())) {
            Files.walkFileTree(root, new SimpleFileVisitor<>() {
                @Override
                public FileVisitResult preVisitDirectory(
                        Path directory, java.nio.file.attribute.BasicFileAttributes attrs)
                        throws IOException {
                    rejectUnsafeLocalPath(root, directory, true);
                    ensureRemoteDirectory(sftp, remotePathFor(root, directory, normalizedRemote));
                    return FileVisitResult.CONTINUE;
                }

                @Override
                public FileVisitResult visitFile(
                        Path file, java.nio.file.attribute.BasicFileAttributes attrs)
                        throws IOException {
                    rejectUnsafeLocalPath(root, file, false);
                    String remotePath = remotePathFor(root, file, normalizedRemote);
                    int separator = remotePath.lastIndexOf('/');
                    if (separator > 0) ensureRemoteDirectory(sftp, remotePath.substring(0, separator));
                    sftp.put(file, remotePath);
                    return FileVisitResult.CONTINUE;
                }
            });
        }
    }

    public void download(SshSession session, String remotePath, Path local) throws IOException {
        if (session == null) throw new IllegalArgumentException("SSH 会话不能为空");
        if (remotePath == null || remotePath.isBlank()) {
            throw new IllegalArgumentException("远端路径不能为空");
        }
        if (local == null) throw new IllegalArgumentException("本地下载路径不能为空");
        Path parent = local.toAbsolutePath().normalize().getParent();
        if (parent != null) Files.createDirectories(parent);
        try (SftpClient sftp = SftpClientFactory.instance().createSftpClient(session.delegate())) {
            try (java.io.InputStream input = sftp.read(remotePath)) {
                Files.copy(input, local, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            }
        }
    }

    private static void rejectUnsafeLocalPath(Path root, Path path, boolean directory) {
        Path normalized = path.toAbsolutePath().normalize();
        if (!normalized.startsWith(root)) {
            throw new IllegalArgumentException("本地上传路径越界");
        }
        if (Files.isSymbolicLink(path)) {
            throw new IllegalArgumentException("本地上传目录包含符号链接");
        }
        if (!directory && !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
            throw new IllegalArgumentException("本地上传目录只能包含普通文件");
        }
    }

    private static String normalizeRemoteDirectory(String remoteDirectory) {
        if (remoteDirectory == null || remoteDirectory.isBlank()) {
            throw new IllegalArgumentException("远端目录不能为空");
        }
        String value = remoteDirectory.replace('\\', '/');
        if (!value.startsWith("/")) {
            throw new IllegalArgumentException("远端目录必须是绝对路径");
        }
        List<String> segments = java.util.Arrays.stream(value.split("/"))
                .filter(segment -> !segment.isBlank())
                .toList();
        if (segments.stream().anyMatch(segment -> ".".equals(segment) || "..".equals(segment))) {
            throw new IllegalArgumentException("远端目录越界");
        }
        return "/" + String.join("/", segments);
    }

    private static String remotePathFor(Path root, Path path, String remoteRoot) {
        Path relative = root.relativize(path.toAbsolutePath().normalize());
        if (relative.getNameCount() == 0) return remoteRoot;
        String suffix = relative.toString().replace('\\', '/');
        if (suffix.contains("../") || suffix.equals("..")) {
            throw new IllegalArgumentException("本地上传路径越界");
        }
        return remoteRoot.endsWith("/") ? remoteRoot + suffix : remoteRoot + "/" + suffix;
    }

    private static void ensureRemoteDirectory(SftpClient sftp, String remoteDirectory) throws IOException {
        String normalized = normalizeRemoteDirectory(remoteDirectory);
        String current = "";
        for (String segment : normalized.substring(1).split("/")) {
            current += "/" + segment;
            try {
                sftp.mkdir(current);
            } catch (SftpException exception) {
                if (!remoteDirectoryExists(sftp, current)) throw exception;
            }
        }
    }

    private static boolean remoteDirectoryExists(SftpClient sftp, String remotePath) throws IOException {
        try {
            return sftp.stat(remotePath).isDirectory();
        } catch (SftpException exception) {
            return false;
        }
    }

    private static final class LimitedOutputStream extends ByteArrayOutputStream {
        private final int limit;

        private LimitedOutputStream(int limit) {
            this.limit = limit;
        }

        @Override
        public synchronized void write(int value) {
            ensureCapacityFor(1);
            super.write(value);
        }

        @Override
        public synchronized void write(byte[] bytes, int offset, int length) {
            ensureCapacityFor(length);
            super.write(bytes, offset, length);
        }

        private void ensureCapacityFor(int length) {
            if (count + length > limit) {
                throw new IllegalStateException("远程命令输出超过 1 MiB 限制");
            }
        }

        private String asString() {
            return toString(StandardCharsets.UTF_8);
        }
    }
}
