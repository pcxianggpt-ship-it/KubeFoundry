package io.kubefoundry.ssh;

import java.io.IOException;
import java.security.KeyPair;
import org.apache.sshd.client.SshClient;
import org.apache.sshd.client.auth.password.PasswordIdentityProvider;
import org.apache.sshd.client.config.hosts.HostConfigEntryResolver;
import org.apache.sshd.client.keyverifier.RejectAllServerKeyVerifier;
import org.apache.sshd.client.keyverifier.ServerKeyVerifier;
import org.apache.sshd.client.session.ClientSession;
import org.apache.sshd.common.keyprovider.KeyIdentityProvider;

public final class SshClientFactory implements AutoCloseable {

    private final SshClient client;

    public SshClientFactory(ServerKeyVerifier serverKeyVerifier) {
        if (serverKeyVerifier == null) throw new IllegalArgumentException("主机密钥校验器不能为空");
        client = SshClient.setUpDefaultClient();
        client.setServerKeyVerifier(serverKeyVerifier);
        client.setHostConfigEntryResolver(HostConfigEntryResolver.EMPTY);
        client.setKeyIdentityProvider(KeyIdentityProvider.EMPTY_KEYS_PROVIDER);
        client.setPasswordIdentityProvider(PasswordIdentityProvider.EMPTY_PASSWORDS_PROVIDER);
        client.start();
    }

    public static SshClientFactory rejectingUnknownHosts() {
        return new SshClientFactory(RejectAllServerKeyVerifier.INSTANCE);
    }

    static SshClientFactory acceptingForTests() {
        return new SshClientFactory((session, address, key) -> true);
    }

    public SshSession connectWithPassword(SshConnectionSpec spec, char[] password) throws IOException {
        if (password == null) throw new IllegalArgumentException("SSH 密码不能为空");
        ClientSession session = connect(spec);
        try {
            session.addPasswordIdentity(new String(password));
            session.auth().verify(spec.authenticationTimeout());
            return new SshSession(session);
        } catch (IOException exception) {
            session.close();
            throw new SshAuthenticationException(
                    "SSH 密码认证失败: " + spec.username() + "@" + spec.host() + ":" + spec.port(),
                    exception);
        }
    }

    public SshSession connectWithKey(SshConnectionSpec spec, KeyPair keyPair) throws IOException {
        if (keyPair == null) throw new IllegalArgumentException("SSH 密钥不能为空");
        ClientSession session = connect(spec);
        try {
            session.addPublicKeyIdentity(keyPair);
            session.auth().verify(spec.authenticationTimeout());
            return new SshSession(session);
        } catch (IOException exception) {
            session.close();
            throw new SshAuthenticationException(
                    "SSH 公钥认证失败: " + spec.username() + "@" + spec.host() + ":" + spec.port(),
                    exception);
        }
    }

    private ClientSession connect(SshConnectionSpec spec) throws IOException {
        return client.connect(spec.username(), spec.host(), spec.port())
                .verify(spec.connectTimeout())
                .getSession();
    }

    @Override
    public void close() throws IOException {
        client.stop();
    }
}
