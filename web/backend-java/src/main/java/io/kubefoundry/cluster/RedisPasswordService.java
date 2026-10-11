package io.kubefoundry.cluster;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.credential.AesGcmCredentialCipher;
import io.kubefoundry.credential.EncryptedCredential;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;

/** Redis 密码只以密文保存；API 仅暴露配置状态，安装快照不保存任何密码信息。 */
@Service
public class RedisPasswordService {
    public static final String GROUP_KEY = "redis_sentinel";
    private static final String CREDENTIAL = "password_credential";
    private final ClusterComponentRepository components;
    private final ObjectProvider<AesGcmCredentialCipher> cipher;
    private final ObjectMapper mapper;

    public RedisPasswordService(ClusterComponentRepository components,
            ObjectProvider<AesGcmCredentialCipher> cipher, ObjectMapper mapper) {
        this.components = components;
        this.cipher = cipher;
        this.mapper = mapper;
    }

    public Map<String, Object> configure(Map<String, Object> current, Map<String, Object> requested) {
        if (!requested.keySet().stream().allMatch(Set.of("password", "has_password")::contains)
                || requested.containsKey("has_password") && !(requested.get("has_password") instanceof Boolean)) {
            throw invalid("Redis 配置包含未知字段或无效的密码状态");
        }
        if (!requested.containsKey("password")) return current;
        if (!(requested.get("password") instanceof String password)) {
            throw invalid("Redis 密码必须是字符串");
        }
        // 留空不删除已保存凭据，也不改变旧集群的随机密码策略。
        if (password.isEmpty()) return current;
        if (password.isBlank() || password.length() > 256
                || password.chars().anyMatch(Character::isISOControl)) {
            throw invalid("Redis 密码不能仅包含空白、包含控制字符或超过 256 个字符");
        }
        char[] plaintext = password.toCharArray();
        char[] previous = null;
        try {
            if (hasPassword(current)) {
                previous = cipher.getObject().decrypt(credential(current));
                if (Arrays.equals(previous, plaintext)) return current;
            }
            EncryptedCredential encrypted = cipher.getObject().encrypt(plaintext);
            return Map.of(CREDENTIAL, Map.of("ciphertext", encrypted.ciphertext(),
                    "iv", encrypted.iv(), "version", encrypted.version()));
        } finally {
            Arrays.fill(plaintext, '\0');
            if (previous != null) Arrays.fill(previous, '\0');
        }
    }

    public static Map<String, Object> publicConfig(Map<String, Object> stored) {
        return Map.of("has_password", hasPassword(stored));
    }

    private static boolean hasPassword(Map<String, Object> stored) {
        return stored.containsKey(CREDENTIAL);
    }

    /** 独立临时文件不进入任务 work/evidence；调用方负责在所有退出路径删除。 */
    public Path createPasswordFile(long clusterId) throws IOException {
        ClusterComponent component = components.findByClusterIdAndComponentKey(clusterId, GROUP_KEY).orElse(null);
        if (component == null || !component.isEnabled()) return null;
        Map<String, Object> config;
        try {
            config = mapper.readValue(component.getConfigJson(), Map.class);
        } catch (JsonProcessingException exception) {
            throw new IOException("Redis 密码配置无法读取");
        }
        if (!hasPassword(config)) return null;
        char[] plaintext = cipher.getObject().decrypt(credential(config));
        Path file = null;
        try {
            file = Files.createTempFile("kubefoundry-redis-password-", ".secret");
            Files.writeString(file, new String(plaintext), StandardCharsets.UTF_8);
            return file;
        } catch (IOException exception) {
            if (file != null) Files.deleteIfExists(file);
            throw exception;
        } finally {
            Arrays.fill(plaintext, '\0');
        }
    }

    private EncryptedCredential credential(Map<String, Object> stored) {
        try {
            return mapper.convertValue(stored.get(CREDENTIAL), EncryptedCredential.class);
        } catch (IllegalArgumentException exception) {
            throw new IllegalStateException("Redis 密码密文无效");
        }
    }

    private static IllegalArgumentException invalid(String message) {
        return new ClusterComponentService.ComponentConfigurationException("COMPONENT_CONFIG_INVALID", message);
    }
}
