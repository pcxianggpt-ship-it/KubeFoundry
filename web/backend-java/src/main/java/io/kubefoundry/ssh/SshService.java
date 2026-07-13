package io.kubefoundry.ssh;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Duration;
import java.util.EnumSet;
import java.util.Set;
import org.apache.sshd.client.channel.ChannelExec;
import org.apache.sshd.client.channel.ClientChannelEvent;
import org.apache.sshd.sftp.client.SftpClient;
import org.apache.sshd.sftp.client.SftpClientFactory;
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
        if (local == null || !java.nio.file.Files.isRegularFile(local)) {
            throw new IllegalArgumentException("本地上传文件不存在");
        }
        if (remotePath == null || remotePath.isBlank()) {
            throw new IllegalArgumentException("远端路径不能为空");
        }
        try (SftpClient sftp = SftpClientFactory.instance().createSftpClient(session.delegate())) {
            sftp.put(local, remotePath);
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
