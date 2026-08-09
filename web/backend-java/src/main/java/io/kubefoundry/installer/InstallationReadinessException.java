package io.kubefoundry.installer;

/** A configuration issue that must be fixed before a precheck or installation can begin. */
public class InstallationReadinessException extends IllegalArgumentException {
    public InstallationReadinessException(String message) {
        super(message);
    }
}
