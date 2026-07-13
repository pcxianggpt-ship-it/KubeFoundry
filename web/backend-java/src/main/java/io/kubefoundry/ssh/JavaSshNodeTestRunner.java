package io.kubefoundry.ssh;

import io.kubefoundry.cluster.Node;
import java.io.IOException;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import org.springframework.stereotype.Service;

@Service
public class JavaSshNodeTestRunner implements NodeTestRunner {

    private static final Duration CONNECT_TIMEOUT = Duration.ofSeconds(30);
    private static final Duration AUTHENTICATION_TIMEOUT = Duration.ofSeconds(30);
    private static final Duration COMMAND_TIMEOUT = Duration.ofSeconds(60);
    private static final String PROBE_COMMAND =
            "cat /etc/os-release; printf '__KF_ARCH=%s\\n' \"$(uname -m)\"";

    private final HostFingerprintVerifier fingerprints;
    private final AuthorizedKeysService authorizedKeys;
    private final SshService ssh;

    public JavaSshNodeTestRunner(
            HostFingerprintVerifier fingerprints,
            AuthorizedKeysService authorizedKeys,
            SshService ssh) {
        this.fingerprints = fingerprints;
        this.authorizedKeys = authorizedKeys;
        this.ssh = ssh;
    }

    @Override
    public NodeProbe test(
            Node node,
            char[] password,
            ClusterKeyMaterial clusterKey,
            PhaseReporter reporter,
            long expectedConfigVersion) throws Exception {
        SshConnectionSpec spec = new SshConnectionSpec(
                node.getIp(), node.getSshPort(), node.getSshUser(),
                CONNECT_TIMEOUT, AUTHENTICATION_TIMEOUT);

        reporter.report("password_connecting");
        try (SshClientFactory clients = new SshClientFactory(
                fingerprints.forNode(node.getId(), node.getHostname(), expectedConfigVersion));
             SshSession session = clients.connectWithPassword(spec, password)) {
            reporter.report("key_installing");
            authorizedKeys.install(session, clusterKey.authorizedKey());
        }

        reporter.report("key_verifying");
        try (SshClientFactory clients = new SshClientFactory(
                fingerprints.forNode(node.getId(), node.getHostname(), expectedConfigVersion));
             SshSession session = clients.connectWithKey(spec, clusterKey.keyPair())) {
            SshCommandResult result = ssh.execute(session, PROBE_COMMAND, COMMAND_TIMEOUT);
            if (result.exitCode() != 0) {
                throw new IOException("环境探测失败，退出码: " + result.exitCode());
            }
            return parseProbe(result.stdout());
        }
    }

    static NodeProbe parseProbe(String output) {
        Map<String, String> values = new HashMap<>();
        String architecture = "";
        for (String rawLine : output.split("\\R")) {
            String line = rawLine.trim();
            if (line.startsWith("__KF_ARCH=")) {
                architecture = normalizeArchitecture(line.substring("__KF_ARCH=".length()).trim());
            } else if (!line.isEmpty() && !line.startsWith("#") && line.contains("=")) {
                int separator = line.indexOf('=');
                values.put(line.substring(0, separator), unquote(line.substring(separator + 1)));
            }
        }
        String osType = values.getOrDefault("ID", "");
        String osVersion = values.getOrDefault("VERSION_ID", values.getOrDefault("VERSION", ""));
        return new NodeProbe(osType, osVersion, architecture);
    }

    private static String normalizeArchitecture(String value) {
        return switch (value) {
            case "x86_64" -> "amd64";
            case "aarch64" -> "arm64";
            default -> value;
        };
    }

    private static String unquote(String value) {
        String trimmed = value.trim();
        if (trimmed.length() >= 2
                && ((trimmed.startsWith("\"") && trimmed.endsWith("\""))
                || (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
            return trimmed.substring(1, trimmed.length() - 1);
        }
        return trimmed;
    }
}
