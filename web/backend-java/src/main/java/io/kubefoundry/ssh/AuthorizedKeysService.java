package io.kubefoundry.ssh;

import java.io.IOException;
import java.time.Duration;
import org.springframework.stereotype.Service;

@Service
public class AuthorizedKeysService {

    private final SshService ssh;

    public AuthorizedKeysService(SshService ssh) {
        this.ssh = ssh;
    }

    public void install(SshSession session, String authorizedKey) throws IOException {
        if (authorizedKey == null || authorizedKey.isBlank()) {
            throw new IllegalArgumentException("集群 SSH 公钥不能为空");
        }
        String quotedKey = shellQuote(authorizedKey.trim());
        String command = "umask 077; mkdir -p ~/.ssh; chmod 700 ~/.ssh; "
                + "touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; "
                + "grep -qxF -- " + quotedKey + " ~/.ssh/authorized_keys || "
                + "printf '%s\\n' " + quotedKey + " >> ~/.ssh/authorized_keys";
        SshCommandResult result = ssh.execute(session, command, Duration.ofSeconds(60));
        if (result.exitCode() != 0) {
            throw new IOException("写入 authorized_keys 失败，退出码: " + result.exitCode());
        }
    }

    static String shellQuote(String value) {
        return "'" + value.replace("'", "'\"'\"'") + "'";
    }
}
