package io.kubefoundry.ssh;

import java.io.IOException;
import org.apache.sshd.client.session.ClientSession;

public final class SshSession implements AutoCloseable {

    private final ClientSession delegate;

    SshSession(ClientSession delegate) {
        this.delegate = delegate;
    }

    ClientSession delegate() {
        return delegate;
    }

    @Override
    public void close() throws IOException {
        delegate.close();
    }
}
