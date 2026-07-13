package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.ssh.ClusterKeyMaterial;
import io.kubefoundry.ssh.ClusterKeyService;
import io.kubefoundry.ssh.HostFingerprintVerifier;
import io.kubefoundry.ssh.SshClientFactory;
import io.kubefoundry.ssh.SshCommandResult;
import io.kubefoundry.ssh.SshConnectionSpec;
import io.kubefoundry.ssh.SshSession;
import java.time.Duration;
import org.springframework.stereotype.Component;

@Component
public class JavaRemoteSessionProvider implements RemoteSessionProvider {

    private static final Duration CONNECTION_TIMEOUT = Duration.ofSeconds(30);
    private static final Duration AUTHENTICATION_TIMEOUT = Duration.ofSeconds(30);

    private final ClusterKeyService clusterKeys;
    private final HostFingerprintVerifier fingerprints;

    public JavaRemoteSessionProvider(
            ClusterKeyService clusterKeys, HostFingerprintVerifier fingerprints) {
        this.clusterKeys = clusterKeys;
        this.fingerprints = fingerprints;
    }

    @Override
    public SshCommandResult withSession(
            Cluster cluster, Node node, SessionWork work) throws Exception {
        long clusterId = cluster.getId();
        long configVersion = cluster.getNodeConfigVersion();
        ClusterKeyMaterial key = clusterKeys.getOrCreate(clusterId);
        SshConnectionSpec spec = new SshConnectionSpec(
                node.getIp(), node.getSshPort(), node.getSshUser(),
                CONNECTION_TIMEOUT, AUTHENTICATION_TIMEOUT);
        try (SshClientFactory clients = new SshClientFactory(
                fingerprints.forNode(node.getId(), node.getHostname(), configVersion));
             SshSession session = clients.connectWithKey(spec, key.keyPair())) {
            return work.apply(session);
        }
    }
}
