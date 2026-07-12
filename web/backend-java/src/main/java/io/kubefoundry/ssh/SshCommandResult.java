package io.kubefoundry.ssh;

public record SshCommandResult(int exitCode, String stdout, String stderr) {
}
