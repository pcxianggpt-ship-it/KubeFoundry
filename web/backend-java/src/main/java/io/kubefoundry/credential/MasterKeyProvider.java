package io.kubefoundry.credential;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.SeekableByteChannel;
import java.nio.file.DirectoryStream;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.NoSuchFileException;
import java.nio.file.OpenOption;
import java.nio.file.Path;
import java.nio.file.SecureDirectoryStream;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.nio.file.attribute.FileAttribute;
import java.nio.file.attribute.FileTime;
import java.nio.file.attribute.PosixFileAttributeView;
import java.nio.file.attribute.PosixFileAttributes;
import java.nio.file.attribute.PosixFilePermission;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.Arrays;
import java.util.Base64;
import java.util.Objects;
import java.util.Set;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;

/**
 * 管理存放在数据目录之外的 H2 主密钥文件。
 */
public final class MasterKeyProvider {

    private static final String ALGORITHM = "AES";
    private static final int KEY_LENGTH_BYTES = 32;
    private static final int BASE64_KEY_LENGTH_BYTES = 44;
    private static final Path SECRETS_DIRECTORY = Path.of("secrets");
    private static final Path MASTER_KEY_FILE = Path.of("master.key");
    private static final Set<PosixFilePermission> OWNER_READ_WRITE = Set.of(
            PosixFilePermission.OWNER_READ,
            PosixFilePermission.OWNER_WRITE);
    private static final FileAttribute<Set<PosixFilePermission>> OWNER_READ_WRITE_ATTRIBUTE =
            PosixFilePermissions.asFileAttribute(OWNER_READ_WRITE);
    private static final Set<OpenOption> READ_OPTIONS = Set.of(
            StandardOpenOption.READ,
            LinkOption.NOFOLLOW_LINKS);
    private static final Set<OpenOption> CREATE_OPTIONS = Set.of(
            StandardOpenOption.CREATE_NEW,
            StandardOpenOption.WRITE);

    private final BeforeExistingKeyOpen beforeExistingKeyOpen;

    public MasterKeyProvider() {
        this(keyFile -> { });
    }

    MasterKeyProvider(BeforeExistingKeyOpen beforeExistingKeyOpen) {
        if (beforeExistingKeyOpen == null) {
            throw new IllegalArgumentException("打开前操作不能为空");
        }
        this.beforeExistingKeyOpen = beforeExistingKeyOpen;
    }

    public SecretKey loadOrCreate(Path dataDir) {
        if (dataDir == null) {
            throw new IllegalArgumentException("数据目录不能为空");
        }

        try {
            Files.createDirectories(dataDir);
            if (Files.getFileAttributeView(dataDir, PosixFileAttributeView.class) != null) {
                return loadOrCreatePosix(dataDir);
            }
            return loadOrCreateNonPosix(dataDir);
        } catch (MasterKeyPermissionException | IllegalStateException exception) {
            throw exception;
        } catch (IOException exception) {
            throw new IllegalStateException("无法加载主密钥文件", exception);
        }
    }

    private SecretKey loadOrCreatePosix(Path dataDir) throws IOException {
        try (DirectoryStream<Path> dataDirectory = Files.newDirectoryStream(dataDir)) {
            if (!(dataDirectory instanceof SecureDirectoryStream<Path> secureDataDirectory)) {
                throw new IllegalStateException("当前 POSIX 文件系统不支持安全目录访问");
            }
            try (SecureDirectoryStream<Path> secretsDirectory =
                         openOrCreateSecureSecretsDirectory(secureDataDirectory, dataDir)) {
                try {
                    return createPosixKey(secretsDirectory);
                } catch (FileAlreadyExistsException exception) {
                    return readExistingPosixKey(
                            secretsDirectory,
                            dataDir.resolve(SECRETS_DIRECTORY).resolve(MASTER_KEY_FILE));
                }
            }
        }
    }

    private SecureDirectoryStream<Path> openOrCreateSecureSecretsDirectory(
            SecureDirectoryStream<Path> dataDirectory, Path dataDir) throws IOException {
        try {
            return dataDirectory.newDirectoryStream(SECRETS_DIRECTORY, LinkOption.NOFOLLOW_LINKS);
        } catch (NoSuchFileException exception) {
            try {
                Files.createDirectory(dataDir.resolve(SECRETS_DIRECTORY));
            } catch (FileAlreadyExistsException ignored) {
                // Re-open through the already anchored parent to verify it is not a symbolic link.
            }
            return dataDirectory.newDirectoryStream(SECRETS_DIRECTORY, LinkOption.NOFOLLOW_LINKS);
        }
    }

    private SecretKey createPosixKey(SecureDirectoryStream<Path> secretsDirectory) throws IOException {
        byte[] keyBytes = new byte[KEY_LENGTH_BYTES];
        byte[] encodedKey = null;
        try {
            new java.security.SecureRandom().nextBytes(keyBytes);
            encodedKey = Base64.getEncoder().encode(keyBytes);
            try (SeekableByteChannel channel = secretsDirectory.newByteChannel(
                    MASTER_KEY_FILE, CREATE_OPTIONS, OWNER_READ_WRITE_ATTRIBUTE)) {
                writeFully(channel, encodedKey);
            }
            return new SecretKeySpec(keyBytes, ALGORITHM);
        } finally {
            clear(encodedKey);
            clear(keyBytes);
        }
    }

    private SecretKey readExistingPosixKey(
            SecureDirectoryStream<Path> secretsDirectory, Path keyFileForVerification) throws IOException {
        PosixFileAttributeView view = secretsDirectory.getFileAttributeView(
                MASTER_KEY_FILE, PosixFileAttributeView.class, LinkOption.NOFOLLOW_LINKS);
        if (view == null) {
            throw new IllegalStateException("无法读取主密钥文件属性");
        }

        ExistingKeyIdentity before = validateExistingPosixKey(view.readAttributes());
        beforeExistingKeyOpen.run(keyFileForVerification);
        try (SeekableByteChannel channel = secretsDirectory.newByteChannel(MASTER_KEY_FILE, READ_OPTIONS)) {
            ExistingKeyIdentity after = validateExistingPosixKey(view.readAttributes());
            if (!before.sameFileAs(after)) {
                throw new IllegalStateException("主密钥文件身份在安全打开期间发生变化");
            }
            return decodeKey(channel);
        }
    }

    private SecretKey loadOrCreateNonPosix(Path dataDir) throws IOException {
        Path secretsDirectory = dataDir.resolve(SECRETS_DIRECTORY);
        ensureNonPosixSecretsDirectory(secretsDirectory);
        Path keyFile = secretsDirectory.resolve(MASTER_KEY_FILE);
        try {
            return createNonPosixKey(keyFile);
        } catch (FileAlreadyExistsException exception) {
            return readExistingNonPosixKey(keyFile);
        }
    }

    private void ensureNonPosixSecretsDirectory(Path secretsDirectory) throws IOException {
        if (Files.notExists(secretsDirectory, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(secretsDirectory);
            } catch (FileAlreadyExistsException ignored) {
                // Validate the component below after a concurrent creator wins the race.
            }
        }
        if (Files.isSymbolicLink(secretsDirectory)
                || !Files.isDirectory(secretsDirectory, LinkOption.NOFOLLOW_LINKS)) {
            throw new IllegalStateException("secrets 目录不能是符号链接且必须为目录");
        }
    }

    private SecretKey createNonPosixKey(Path keyFile) throws IOException {
        byte[] keyBytes = new byte[KEY_LENGTH_BYTES];
        byte[] encodedKey = null;
        try {
            new java.security.SecureRandom().nextBytes(keyBytes);
            encodedKey = Base64.getEncoder().encode(keyBytes);
            try (SeekableByteChannel channel = Files.newByteChannel(keyFile, CREATE_OPTIONS)) {
                writeFully(channel, encodedKey);
            }
            return new SecretKeySpec(keyBytes, ALGORITHM);
        } finally {
            clear(encodedKey);
            clear(keyBytes);
        }
    }

    private SecretKey readExistingNonPosixKey(Path keyFile) throws IOException {
        ExistingKeyIdentity before = validateExistingKey(Files.readAttributes(
                keyFile, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS));
        beforeExistingKeyOpen.run(keyFile);
        try (SeekableByteChannel channel = Files.newByteChannel(keyFile, READ_OPTIONS)) {
            ExistingKeyIdentity after = validateExistingKey(Files.readAttributes(
                    keyFile, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS));
            if (!before.sameFileAs(after)) {
                throw new IllegalStateException("主密钥文件身份在安全打开期间发生变化");
            }
            return decodeKey(channel);
        }
    }

    private ExistingKeyIdentity validateExistingPosixKey(PosixFileAttributes attributes) {
        ExistingKeyIdentity identity = validateExistingKey(attributes);
        boolean groupOrOtherCanAccess = attributes.permissions().stream()
                .anyMatch(permission -> permission.name().startsWith("GROUP_")
                        || permission.name().startsWith("OTHERS_"));
        if (groupOrOtherCanAccess) {
            throw new MasterKeyPermissionException("主密钥文件权限过宽，请执行 chmod 600");
        }
        return identity;
    }

    private ExistingKeyIdentity validateExistingKey(BasicFileAttributes attributes) {
        if (attributes.isSymbolicLink() || !attributes.isRegularFile()) {
            throw new IllegalStateException("主密钥文件不能是符号链接且必须为普通文件");
        }
        return new ExistingKeyIdentity(attributes.fileKey(), attributes.size(), attributes.lastModifiedTime());
    }

    private SecretKey decodeKey(SeekableByteChannel channel) throws IOException {
        byte[] encodedKey = new byte[BASE64_KEY_LENGTH_BYTES];
        byte[] keyBytes = null;
        try {
            readFully(channel, encodedKey);
            if (hasTrailingBytes(channel)) {
                throw invalidKeyContents();
            }
            keyBytes = Base64.getDecoder().decode(encodedKey);
            if (keyBytes.length != KEY_LENGTH_BYTES) {
                throw invalidKeyContents();
            }
            return new SecretKeySpec(keyBytes, ALGORITHM);
        } catch (IllegalArgumentException exception) {
            throw invalidKeyContents();
        } finally {
            clear(encodedKey);
            clear(keyBytes);
        }
    }

    private static void writeFully(SeekableByteChannel channel, byte[] bytes) throws IOException {
        ByteBuffer buffer = ByteBuffer.wrap(bytes);
        while (buffer.hasRemaining()) {
            channel.write(buffer);
        }
    }

    private static void readFully(SeekableByteChannel channel, byte[] bytes) throws IOException {
        ByteBuffer buffer = ByteBuffer.wrap(bytes);
        while (buffer.hasRemaining()) {
            if (channel.read(buffer) < 0) {
                throw invalidKeyContents();
            }
        }
    }

    private static boolean hasTrailingBytes(SeekableByteChannel channel) throws IOException {
        byte[] extraByte = new byte[1];
        try {
            return channel.read(ByteBuffer.wrap(extraByte)) != -1;
        } finally {
            clear(extraByte);
        }
    }

    private static IllegalStateException invalidKeyContents() {
        return new IllegalStateException("主密钥文件内容无效");
    }

    private static void clear(byte[] bytes) {
        if (bytes != null) {
            Arrays.fill(bytes, (byte) 0);
        }
    }

    @FunctionalInterface
    interface BeforeExistingKeyOpen {
        void run(Path keyFile) throws IOException;
    }

    private record ExistingKeyIdentity(Object fileKey, long size, FileTime lastModifiedTime) {
        private boolean sameFileAs(ExistingKeyIdentity other) {
            if (fileKey != null && other.fileKey != null) {
                return Objects.equals(fileKey, other.fileKey);
            }
            return size == other.size && Objects.equals(lastModifiedTime, other.lastModifiedTime);
        }
    }
}
