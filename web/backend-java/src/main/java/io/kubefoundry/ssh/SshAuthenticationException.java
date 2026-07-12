package io.kubefoundry.ssh;

import java.io.IOException;

public class SshAuthenticationException extends IOException {
    public SshAuthenticationException(String message, Throwable cause) {
        super(message, cause);
    }
}
