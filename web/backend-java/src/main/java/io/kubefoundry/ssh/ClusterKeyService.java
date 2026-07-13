package io.kubefoundry.ssh;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.credential.AesGcmCredentialCipher;
import io.kubefoundry.credential.EncryptedCredential;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.SeekableByteChannel;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.OpenOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.FileAttribute;
import java.nio.file.attribute.PosixFilePermission;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Arrays;
import java.util.Base64;
import java.util.Collections;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.function.Supplier;
import org.apache.sshd.common.config.keys.PublicKeyEntry;
import org.apache.sshd.common.util.security.SecurityUtils;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class ClusterKeyService {

    private static final String KEY_NAME = "cluster-default";
    private static final Set<PosixFilePermission> OWNER_DIRECTORY_PERMISSIONS = Set.of(
            PosixFilePermission.OWNER_READ,
            PosixFilePermission.OWNER_WRITE,
            PosixFilePermission.OWNER_EXECUTE);
    private static final Set<PosixFilePermission> OWNER_FILE_PERMISSIONS = Set.of(
            PosixFilePermission.OWNER_READ,
            PosixFilePermission.OWNER_WRITE);

    private final ClusterRepository clusters;
    private final SshKeyRepository sshKeys;
    private final Supplier<AesGcmCredentialCipher> cipherSupplier;
    private final ObjectMapper objectMapper;
    private final Path dataDirectory;
    private final ConcurrentMap<Long, Object> clusterLocks = new ConcurrentHashMap<>();

    @Autowired
    public ClusterKeyService(
            ClusterRepository clusters,
            SshKeyRepository sshKeys,
            ObjectProvider<AesGcmCredentialCipher> cipherProvider,
            ObjectMapper objectMapper,
            @Value("${kubefoundry.data-dir:data}") String dataDirectory) {
        this(clusters, sshKeys, cipherProvider::getObject, objectMapper, Path.of(dataDirectory));
    }

    ClusterKeyService(
            ClusterRepository clusters,
            SshKeyRepository sshKeys,
            AesGcmCredentialCipher cipher,
            ObjectMapper objectMapper,
            Path dataDirectory) {
        this(clusters, sshKeys, () -> cipher, objectMapper, dataDirectory);
    }

    private ClusterKeyService(
            ClusterRepository clusters,
            SshKeyRepository sshKeys,
            Supplier<AesGcmCredentialCipher> cipherSupplier,
            ObjectMapper objectMapper,
            Path dataDirectory) {
        this.clusters = clusters;
        this.sshKeys = sshKeys;
        this.cipherSupplier = cipherSupplier;
        this.objectMapper = objectMapper;
        this.dataDirectory = dataDirectory.toAbsolutePath().normalize();
    }

    public ClusterKeyMaterial getOrCreate(long clusterId) {
        synchronized (clusterLocks.computeIfAbsent(clusterId, ignored -> new Object())) {
            return sshKeys.findByClusterIdAndName(clusterId, KEY_NAME)
                    .map(this::load)
                    .orElseGet(() -> create(clusterId));
        }
    }

    private ClusterKeyMaterial create(long clusterId) {
        Cluster cluster = clusters.findById(clusterId)
                .orElseThrow(() -> new IllegalArgumentException("集群不存在: " + clusterId));
        Path privateKeyFile = null;
        try {
            KeyPairGenerator generator = SecurityUtils.getKeyPairGenerator(SecurityUtils.EDDSA);
            KeyPair keyPair = generator.generateKeyPair();
            String publicKey = PublicKeyEntry.toString(keyPair.getPublic()) + " kubefoundry-cluster-" + clusterId;
            privateKeyFile = writeEncryptedPrivateKey(clusterId, keyPair.getPrivate());
            sshKeys.saveAndFlush(new SshKey(cluster, KEY_NAME, publicKey, privateKeyFile.toString()));
            return new ClusterKeyMaterial(publicKey, keyPair);
        } catch (GeneralSecurityException | IOException exception) {
            deleteCreatedFile(privateKeyFile, exception);
            throw new IllegalStateException("无法创建集群 SSH 密钥", exception);
        } catch (RuntimeException exception) {
            deleteCreatedFile(privateKeyFile, exception);
            throw exception;
        }
    }

    private ClusterKeyMaterial load(SshKey stored) {
        char[] encodedPrivateKey = null;
        byte[] encodedPrivateKeyBytes = null;
        byte[] privateKeyBytes = null;
        try {
            EncryptedPrivateKey encrypted = objectMapper.readValue(
                    validatePrivateKeyFile(Path.of(stored.getPrivateKeyPath())).toFile(),
                    EncryptedPrivateKey.class);
            encodedPrivateKey = cipherSupplier.get().decrypt(new EncryptedCredential(
                    encrypted.ciphertext(), encrypted.iv(), encrypted.version()));
            encodedPrivateKeyBytes = toAsciiBytes(encodedPrivateKey);
            privateKeyBytes = Base64.getDecoder().decode(encodedPrivateKeyBytes);
            KeyFactory keyFactory = SecurityUtils.getKeyFactory(SecurityUtils.EDDSA);
            PrivateKey privateKey = keyFactory.generatePrivate(new PKCS8EncodedKeySpec(privateKeyBytes));
            PublicKeyEntry publicKeyEntry = PublicKeyEntry.parsePublicKeyEntry(stored.getPublicKey());
            PublicKey publicKey = publicKeyEntry.resolvePublicKey(null, Collections.emptyMap(), null);
            return new ClusterKeyMaterial(stored.getPublicKey(), new KeyPair(publicKey, privateKey));
        } catch (GeneralSecurityException | IOException | RuntimeException exception) {
            throw new IllegalStateException("无法加载集群 SSH 密钥", exception);
        } finally {
            clear(encodedPrivateKey);
            clear(encodedPrivateKeyBytes);
            clear(privateKeyBytes);
        }
    }

    private Path writeEncryptedPrivateKey(long clusterId, PrivateKey privateKey) throws IOException {
        byte[] privateKeyBytes = privateKey.getEncoded();
        byte[] encoded = null;
        char[] encodedChars = null;
        try {
            encoded = Base64.getEncoder().encode(privateKeyBytes);
            encodedChars = toAsciiChars(encoded);
            EncryptedCredential encrypted = cipherSupplier.get().encrypt(encodedChars);
            byte[] payload = objectMapper.writeValueAsBytes(new EncryptedPrivateKey(
                    encrypted.ciphertext(), encrypted.iv(), encrypted.version()));
            try {
                Path directory = createKeyDirectory();
                Path target = directory.resolve("cluster-" + clusterId + "-" + UUID.randomUUID() + ".json");
                writeNewPrivateKeyFile(target, payload);
                return target;
            } finally {
                clear(payload);
            }
        } finally {
            clear(privateKeyBytes);
            clear(encoded);
            clear(encodedChars);
        }
    }

    private Path createKeyDirectory() throws IOException {
        Path directory = dataDirectory.resolve("secrets").resolve("ssh");
        if (supportsPosix(directory)) {
            FileAttribute<Set<PosixFilePermission>> permissions =
                    PosixFilePermissions.asFileAttribute(OWNER_DIRECTORY_PERMISSIONS);
            Files.createDirectories(directory, permissions);
            Files.setPosixFilePermissions(directory, OWNER_DIRECTORY_PERMISSIONS);
        } else {
            Files.createDirectories(directory);
        }
        if (Files.isSymbolicLink(directory)
                || !Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)) {
            throw new IllegalStateException("集群私钥目录不是普通目录");
        }
        return directory;
    }

    private void writeNewPrivateKeyFile(Path target, byte[] payload) throws IOException {
        Set<OpenOption> options = Set.of(StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
        FileAttribute<?>[] attributes = supportsPosix(target)
                ? new FileAttribute<?>[] {PosixFilePermissions.asFileAttribute(OWNER_FILE_PERMISSIONS)}
                : new FileAttribute<?>[0];
        try (SeekableByteChannel channel = Files.newByteChannel(target, options, attributes)) {
            ByteBuffer buffer = ByteBuffer.wrap(payload);
            while (buffer.hasRemaining()) {
                channel.write(buffer);
            }
        }
    }

    private Path validatePrivateKeyFile(Path path) {
        Path normalized = path.toAbsolutePath().normalize();
        Path expectedDirectory = dataDirectory.resolve("secrets").resolve("ssh").normalize();
        if (!normalized.startsWith(expectedDirectory)) {
            throw new IllegalStateException("集群私钥引用超出数据目录");
        }
        if (Files.isSymbolicLink(normalized)
                || !Files.isRegularFile(normalized, LinkOption.NOFOLLOW_LINKS)) {
            throw new IllegalStateException("集群私钥引用不是普通文件");
        }
        return normalized;
    }

    private static boolean supportsPosix(Path path) {
        return path.getFileSystem().supportedFileAttributeViews().contains("posix");
    }

    private static byte[] toAsciiBytes(char[] chars) {
        byte[] bytes = new byte[chars.length];
        for (int index = 0; index < chars.length; index++) {
            if (chars[index] > 127) throw new IllegalArgumentException("私钥编码不是 ASCII");
            bytes[index] = (byte) chars[index];
        }
        return bytes;
    }

    private static char[] toAsciiChars(byte[] bytes) {
        char[] chars = new char[bytes.length];
        for (int index = 0; index < bytes.length; index++) {
            chars[index] = (char) (bytes[index] & 0xff);
        }
        return chars;
    }

    private static void deleteCreatedFile(Path path, Exception original) {
        if (path == null) return;
        try {
            Files.deleteIfExists(path);
        } catch (IOException deletionFailure) {
            original.addSuppressed(deletionFailure);
        }
    }

    private static void clear(byte[] bytes) {
        if (bytes != null) Arrays.fill(bytes, (byte) 0);
    }

    private static void clear(char[] chars) {
        if (chars != null) Arrays.fill(chars, '\0');
    }

    private record EncryptedPrivateKey(String ciphertext, String iv, int version) {
    }
}
