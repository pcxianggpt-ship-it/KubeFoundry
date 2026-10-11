package io.kubefoundry.cluster;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.credential.AesGcmCredentialCipher;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermission;
import java.util.Map;
import java.util.Optional;
import javax.crypto.spec.SecretKeySpec;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class RedisPasswordServiceTest {
    private final ObjectMapper mapper = new ObjectMapper();
    private final ClusterComponentRepository components = mock(ClusterComponentRepository.class);
    private final ObjectProvider<AesGcmCredentialCipher> provider = mock(ObjectProvider.class);

    private RedisPasswordService service() {
        when(provider.getObject()).thenReturn(new AesGcmCredentialCipher(new SecretKeySpec(new byte[32], "AES")));
        return new RedisPasswordService(components, provider, mapper);
    }

    @Test
    void encryptsPasswordAndPreservesCredentialsOnlyForMissingOrUnchangedInput() throws Exception {
        RedisPasswordService service = service();
        String password = "test-only-$pecial;' 中文";
        Map<String, Object> stored = service.configure(Map.of(), Map.of("password", password), true);
        assertThat(mapper.writeValueAsString(stored)).doesNotContain(password);
        assertThat(RedisPasswordService.publicConfig(stored)).containsExactly(Map.entry("has_password", true));
        assertThat(service.configure(stored, Map.of("has_password", false), true)).isSameAs(stored);
        assertThatThrownBy(() -> service.configure(stored, Map.of("password", ""), true))
                .isInstanceOf(ClusterComponentService.ComponentConfigurationException.class);
        assertThat(service.configure(stored, Map.of("password", password), true)).isSameAs(stored);
        assertThat(service.configure(stored, Map.of("password", "different-test-only-value"), true)).isNotEqualTo(stored);
        assertThat(RedisPasswordService.publicConfig(Map.of())).containsEntry("has_password", false);
    }

    @Test
    void rejectsInvalidPasswordAndInjectedCredentialFieldsWithoutEchoingInput() {
        RedisPasswordService service = service();
        for (Map<String, Object> input : java.util.List.<Map<String, Object>>of(
                Map.of("password", ""), Map.of("password", "test-only\nvalue"), Map.of("password", " "),
                Map.of("password", "x".repeat(257)), Map.of("password", 123),
                Map.of("password_credential", "forged"), Map.of("has_password", "true"))) {
            assertThatThrownBy(() -> service.configure(Map.of(), input, true))
                    .isInstanceOf(ClusterComponentService.ComponentConfigurationException.class)
                    .hasMessageNotContaining("test-only").hasMessageNotContaining("forged");
        }
    }

    @Test
    void decryptsOnlyToAnOwnerOnlyTemporaryFileAndRejectsMissingPassword() throws Exception {
        RedisPasswordService service = service();
        Cluster cluster = new Cluster("redis-test");
        when(components.findByClusterIdAndComponentKey(1L, "redis_sentinel"))
                .thenReturn(Optional.of(new ClusterComponent(cluster, "redis_sentinel", true, "{}")));
        assertThatThrownBy(() -> service.createPasswordFile(1L))
                .isInstanceOf(ClusterComponentService.ComponentConfigurationException.class)
                .hasMessageContaining("必须配置密码");
        Map<String, Object> stored = service.configure(Map.of(), Map.of("password", "test-only-file-value"), true);
        when(components.findByClusterIdAndComponentKey(1L, "redis_sentinel"))
                .thenReturn(Optional.of(new ClusterComponent(cluster, "redis_sentinel", true,
                        mapper.writeValueAsString(stored))));
        Path file = service.createPasswordFile(1L);
        try {
            assertThat(file).hasContent("test-only-file-value");
            if (file.getFileSystem().supportedFileAttributeViews().contains("posix")) {
                assertThat(Files.getPosixFilePermissions(file)).containsExactlyInAnyOrder(
                        PosixFilePermission.OWNER_READ, PosixFilePermission.OWNER_WRITE);
            }
        } finally {
            Files.deleteIfExists(file);
        }
    }

    @Test
    void requiresPasswordOnlyForEnabledRedisAndDoesNotTrustTheClientConfigurationFlag() {
        RedisPasswordService service = service();
        assertThat(service.configure(Map.of(), Map.of(), false)).isEmpty();
        for (Map<String, Object> input : java.util.List.<Map<String, Object>>of(Map.of(), Map.of("has_password", true))) {
            assertThatThrownBy(() -> service.configure(Map.of(), input, true))
                    .isInstanceOf(ClusterComponentService.ComponentConfigurationException.class)
                    .hasMessageContaining("必须配置密码");
        }
        Cluster cluster = new Cluster("missing-password");
        when(components.findByClusterIdAndComponentKey(1L, "redis_sentinel"))
                .thenReturn(Optional.of(new ClusterComponent(cluster, "redis_sentinel", true, "{}")));
        assertThatThrownBy(() -> service.requireConfiguredPassword(1L))
                .hasMessageContaining("必须配置密码");
        when(components.findByClusterIdAndComponentKey(1L, "redis_sentinel"))
                .thenReturn(Optional.of(new ClusterComponent(cluster, "redis_sentinel", false, "{}")));
        service.requireConfiguredPassword(1L);
    }
}
