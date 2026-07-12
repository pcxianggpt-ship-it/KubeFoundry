package io.kubefoundry.ssh;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import java.security.KeyPairGenerator;
import java.security.PublicKey;
import java.security.spec.ECGenParameterSpec;
import org.apache.sshd.common.config.keys.KeyUtils;
import org.apache.sshd.common.digest.BuiltinDigests;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@DataJpaTest
class HostFingerprintVerifierTest {

    @Autowired
    ClusterRepository clusters;

    @Autowired
    NodeRepository nodes;

    HostFingerprintVerifier verifier;
    Node node;

    @BeforeEach
    void setUp() {
        Cluster cluster = clusters.save(new Cluster("fingerprint-test"));
        node = new Node(cluster);
        node.update("node-a", "127.0.0.1", "", "control-plane", "root", 22);
        node = nodes.save(node);
        verifier = new HostFingerprintVerifier(nodes);
    }

    @Test
    void recordsSha256FingerprintOnFirstConnection() throws Exception {
        PublicKey hostKey = newHostKey();

        assertThat(verifier.verify(node.getId(), node.getHostname(), hostKey)).isTrue();

        assertThat(nodes.findById(node.getId()).orElseThrow().getHostFingerprint())
                .startsWith("SHA256:");
    }

    @Test
    void acceptsTheSameFingerprintAgain() throws Exception {
        PublicKey hostKey = newHostKey();
        verifier.verify(node.getId(), node.getHostname(), hostKey);

        assertThat(verifier.verify(node.getId(), node.getHostname(), hostKey)).isTrue();
    }

    @Test
    void rejectsChangedFingerprintWithoutOverwritingStoredValue() throws Exception {
        verifier.verify(node.getId(), node.getHostname(), newHostKey());
        String original = nodes.findById(node.getId()).orElseThrow().getHostFingerprint();
        PublicKey changedKey = newHostKey();
        String changed = KeyUtils.getFingerPrint(BuiltinDigests.sha256, changedKey);

        assertThatThrownBy(() -> verifier.verify(node.getId(), node.getHostname(), changedKey))
                .isInstanceOf(HostFingerprintChangedException.class)
                .hasMessageContaining("node-a", original, changed, "人工确认");
        assertThat(nodes.findById(node.getId()).orElseThrow().getHostFingerprint())
                .isEqualTo(original);
    }

    private static PublicKey newHostKey() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        return generator.generateKeyPair().getPublic();
    }
}
