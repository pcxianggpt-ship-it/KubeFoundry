package io.kubefoundry.ssh;

import java.io.IOException;

public class SshCommandTimeoutException extends IOException {
    public SshCommandTimeoutException(String message) {
        super(message);
    }
}
