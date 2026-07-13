package io.kubefoundry.ssh;

import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AuthorizedKeysServiceTest {

    @Test
    void usesAnIdempotentQuotedAuthorizedKeysCommand() throws Exception {
        SshService ssh = mock(SshService.class);
        SshSession session = mock(SshSession.class);
        when(ssh.execute(eq(session), any(), any(Duration.class)))
                .thenReturn(new SshCommandResult(0, "", ""));
        AuthorizedKeysService service = new AuthorizedKeysService(ssh);
        String publicKey = "ssh-ed25519 AAAA'test kubefoundry";

        service.install(session, publicKey);
        service.install(session, publicKey);

        ArgumentCaptor<String> commands = ArgumentCaptor.forClass(String.class);
        verify(ssh, times(2)).execute(eq(session), commands.capture(), any(Duration.class));
        assertThat(commands.getAllValues()).containsOnly(commands.getValue());
        assertThat(commands.getValue())
                .contains("grep -qxF --", "||", "printf '%s\\n'", "'\"'\"'")
                .doesNotContain("echo ");
    }

    @Test
    void parsesOsReleaseAndNormalizesArchitecture() {
        NodeProbe probe = JavaSshNodeTestRunner.parseProbe(
                "ID=kylin\nVERSION_ID=V10\n__KF_ARCH=aarch64\n");

        assertThat(probe).isEqualTo(new NodeProbe("kylin", "V10", "arm64"));
    }
}
