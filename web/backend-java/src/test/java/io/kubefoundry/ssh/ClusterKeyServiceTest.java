package io.kubefoundry.ssh;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.credential.AesGcmCredentialCipher;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import javax.crypto.spec.SecretKeySpec;
import org.apache.sshd.common.config.keys.KeyUtils;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@DataJpaTest
class ClusterKeyServiceTest {

    @Autowired
    ClusterRepository clusters;

    @Autowired
    SshKeyRepository sshKeys;

    @TempDir
    Path dataDirectory;

    @Test
    void createsAndReusesOneEncryptedEd25519KeyPerCluster() throws Exception {
        Cluster cluster = clusters.save(new Cluster("key-test"));
        ClusterKeyService service = newService();

        ClusterKeyMaterial first = service.getOrCreate(cluster.getId());
        ClusterKeyMaterial second = service.getOrCreate(cluster.getId());

        assertThat(KeyUtils.getKeyType(first.keyPair())).isEqualTo("ssh-ed25519");
        assertThat(KeyUtils.compareKeyPairs(first.keyPair(), second.keyPair())).isTrue();
        assertThat(first.authorizedKey()).startsWith("ssh-ed25519 ");
        assertThat(sshKeys.count()).isEqualTo(1);

        SshKey stored = sshKeys.findByClusterIdAndName(cluster.getId(), "cluster-default")
                .orElseThrow();
        String privateKeyBase64 = Base64.getEncoder()
                .encodeToString(first.keyPair().getPrivate().getEncoded());
        String storedFile = Files.readString(Path.of(stored.getPrivateKeyPath()), StandardCharsets.UTF_8);
        assertThat(stored.getPublicKey()).isEqualTo(first.authorizedKey());
        assertThat(stored.getPrivateKeyPath()).doesNotContain(privateKeyBase64);
        assertThat(storedFile).doesNotContain(privateKeyBase64);
    }

    @Test
    void rejectsPrivateKeyReferenceOutsideDataDirectory() throws Exception {
        Cluster cluster = clusters.save(new Cluster("outside-key-test"));
        Path outside = dataDirectory.resolveSibling("outside-key.json").toAbsolutePath();
        Files.writeString(outside, "{}", StandardCharsets.UTF_8);
        sshKeys.save(new SshKey(cluster, "cluster-default", "ssh-ed25519 invalid", outside.toString()));

        assertThatThrownBy(() -> newService().getOrCreate(cluster.getId()))
                .isInstanceOf(IllegalStateException.class)
                .hasRootCauseMessage("集群私钥引用超出数据目录");
    }

    private ClusterKeyService newService() {
        return new ClusterKeyService(
                clusters,
                sshKeys,
                new AesGcmCredentialCipher(new SecretKeySpec(new byte[32], "AES")),
                new ObjectMapper(),
                dataDirectory);
    }
}
