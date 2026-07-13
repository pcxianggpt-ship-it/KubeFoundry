package io.kubefoundry.ssh;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.credential.AesGcmCredentialCipher;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import javax.crypto.spec.SecretKeySpec;
import org.apache.sshd.common.config.keys.KeyUtils;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

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

    @Test
    void getOrCreateForDifferentClustersDoesNotShareALock() throws Exception {
        ClusterRepository testClusters = mock(ClusterRepository.class);
        SshKeyRepository testKeys = mock(SshKeyRepository.class);
        Cluster firstCluster = new Cluster("first-key-lock");
        Cluster secondCluster = new Cluster("second-key-lock");
        CountDownLatch firstClusterLookupEntered = new CountDownLatch(1);
        CountDownLatch releaseFirstClusterLookup = new CountDownLatch(1);
        when(testKeys.findByClusterIdAndName(any(Long.class), any(String.class)))
                .thenReturn(Optional.empty());
        when(testClusters.findById(1L)).thenAnswer(invocation -> {
            firstClusterLookupEntered.countDown();
            assertThat(releaseFirstClusterLookup.await(5, TimeUnit.SECONDS)).isTrue();
            return Optional.of(firstCluster);
        });
        when(testClusters.findById(2L)).thenReturn(Optional.of(secondCluster));
        when(testKeys.saveAndFlush(any(SshKey.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        ClusterKeyService service = newService(testClusters, testKeys);

        CompletableFuture<ClusterKeyMaterial> first = CompletableFuture.supplyAsync(
                () -> service.getOrCreate(1L));
        assertThat(firstClusterLookupEntered.await(5, TimeUnit.SECONDS)).isTrue();
        CompletableFuture<ClusterKeyMaterial> second = CompletableFuture.supplyAsync(
                () -> service.getOrCreate(2L));
        boolean secondCompletedBeforeRelease;
        try {
            second.get(1, TimeUnit.SECONDS);
            secondCompletedBeforeRelease = true;
        } catch (java.util.concurrent.TimeoutException exception) {
            secondCompletedBeforeRelease = false;
        } finally {
            releaseFirstClusterLookup.countDown();
        }
        assertThat(first.get(5, TimeUnit.SECONDS)).isNotNull();
        assertThat(second.get(5, TimeUnit.SECONDS)).isNotNull();
        assertThat(secondCompletedBeforeRelease).isTrue();
    }

    @Test
    void concurrentGetOrCreateForSameClusterCreatesOneKey() throws Exception {
        ClusterRepository testClusters = mock(ClusterRepository.class);
        SshKeyRepository testKeys = mock(SshKeyRepository.class);
        Cluster testCluster = new Cluster("same-key-lock");
        AtomicReference<SshKey> stored = new AtomicReference<>();
        when(testKeys.findByClusterIdAndName(1L, "cluster-default"))
                .thenAnswer(invocation -> Optional.ofNullable(stored.get()));
        when(testClusters.findById(1L)).thenReturn(Optional.of(testCluster));
        when(testKeys.saveAndFlush(any(SshKey.class))).thenAnswer(invocation -> {
            SshKey created = invocation.getArgument(0);
            stored.set(created);
            return created;
        });
        ClusterKeyService service = newService(testClusters, testKeys);

        CompletableFuture<ClusterKeyMaterial> first = CompletableFuture.supplyAsync(
                () -> service.getOrCreate(1L));
        CompletableFuture<ClusterKeyMaterial> second = CompletableFuture.supplyAsync(
                () -> service.getOrCreate(1L));

        assertThat(KeyUtils.compareKeyPairs(
                first.get(5, TimeUnit.SECONDS).keyPair(),
                second.get(5, TimeUnit.SECONDS).keyPair())).isTrue();
        verify(testKeys).saveAndFlush(any(SshKey.class));
    }

    private ClusterKeyService newService() {
        return newService(clusters, sshKeys);
    }

    private ClusterKeyService newService(
            ClusterRepository clusterRepository, SshKeyRepository keyRepository) {
        return new ClusterKeyService(
                clusterRepository,
                keyRepository,
                new AesGcmCredentialCipher(new SecretKeySpec(new byte[32], "AES")),
                new ObjectMapper(),
                dataDirectory);
    }
}
