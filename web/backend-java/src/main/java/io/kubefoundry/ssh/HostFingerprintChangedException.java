package io.kubefoundry.ssh;

public class HostFingerprintChangedException extends SecurityException {
    public HostFingerprintChangedException(String message) {
        super(message);
    }
}
