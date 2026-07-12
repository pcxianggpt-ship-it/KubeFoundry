package io.kubefoundry.ssh;

import java.time.Duration;

public record SshConnectionSpec(
        String host,
        int port,
        String username,
        Duration connectTimeout,
        Duration authenticationTimeout) {

    public SshConnectionSpec {
        if (host == null || host.isBlank()) throw new IllegalArgumentException("SSH 主机不能为空");
        if (port < 1 || port > 65535) throw new IllegalArgumentException("SSH 端口必须在 1 到 65535 之间");
        if (username == null || username.isBlank()) throw new IllegalArgumentException("SSH 用户不能为空");
        if (connectTimeout == null || connectTimeout.isZero() || connectTimeout.isNegative()) {
            throw new IllegalArgumentException("SSH 连接超时必须大于 0");
        }
        if (authenticationTimeout == null
                || authenticationTimeout.isZero()
                || authenticationTimeout.isNegative()) {
            throw new IllegalArgumentException("SSH 认证超时必须大于 0");
        }
    }
}
