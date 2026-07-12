package io.kubefoundry.credential;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.SeekableByteChannel;
import java.nio.file.DirectoryStream;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.NoSuchFileException;
import java.nio.file.OpenOption;
import java.nio.file.Path;
import java.nio.file.SecureDirectoryStream;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.FileAttribute;
import java.nio.file.attribute.PosixFileAttributeView;
import java.nio.file.attribute.PosixFileAttributes;
import java.nio.file.attribute.PosixFilePermission;
import java.nio.file.attribute.PosixFilePermissions;
import java.nio.file.attribute.UserPrincipal;
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
    private static final Set<PosixFilePermission> OWNER_READ_WRITE_EXECUTE = Set.of(
            PosixFilePermission.OWNER_READ,
            PosixFilePermission.OWNER_WRITE,
            PosixFilePermission.OWNER_EXECUTE);
    private static final FileAttribute<Set<PosixFilePermission>> OWNER_READ_WRITE_ATTRIBUTE =
            PosixFilePermissions.asFileAttribute(OWNER_READ_WRITE);
    private static final FileAttribute<Set<PosixFilePermission>> OWNER_READ_WRITE_EXECUTE_ATTRIBUTE =
            PosixFilePermissions.asFileAttribute(OWNER_READ_WRITE_EXECUTE);
    private static final Set<OpenOption> READ_OPTIONS = Set.of(
            StandardOpenOption.READ,
            LinkOption.NOFOLLOW_LINKS);
    private static final Set<OpenOption> CREATE_OPTIONS = Set.of(
            StandardOpenOption.CREATE_NEW,
            StandardOpenOption.WRITE);

    private final PosixAttributeReader posixAttributeReader;
    private final BeforeExistingKeyOpen beforeExistingKeyOpen;
    private final CurrentUserProvider currentUserProvider;

    public MasterKeyProvider() {
        this(PosixFileAttributeView::readAttributes, keyFile -> { }, MasterKeyProvider::currentUser);
    }

    MasterKeyProvider(BeforeExistingKeyOpen beforeExistingKeyOpen) {
        this(PosixFileAttributeView::readAttributes, beforeExistingKeyOpen, MasterKeyProvider::currentUser);
    }

    MasterKeyProvider(
            PosixAttributeReader posixAttributeReader, BeforeExistingKeyOpen beforeExistingKeyOpen) {
        this(posixAttributeReader, beforeExistingKeyOpen, MasterKeyProvider::currentUser);
    }

    MasterKeyProvider(
            PosixAttributeReader posixAttributeReader,
            BeforeExistingKeyOpen beforeExistingKeyOpen,
            CurrentUserProvider currentUserProvider) {
        if (posixAttributeReader == null || beforeExistingKeyOpen == null || currentUserProvider == null) {
            throw new IllegalArgumentException("安全依赖不能为空");
        }
        this.posixAttributeReader = posixAttributeReader;
        this.beforeExistingKeyOpen = beforeExistingKeyOpen;
        this.currentUserProvider = currentUserProvider;
    }

    public SecretKey loadOrCreate(Path dataDir) {
        if (dataDir == null) {
            throw new IllegalArgumentException("数据目录不能为空");
        }

        try {
            if (!dataDir.getFileSystem().supportedFileAttributeViews().contains("posix")) {
                throw unsupportedFileSystem();
            }
            Path secureDataDir = dataDir.toAbsolutePath().normalize();
            createDataDirectoryIfMissing(secureDataDir);
            if (Files.getFileAttributeView(secureDataDir, PosixFileAttributeView.class) == null) {
                throw unsupportedFileSystem();
            }
            UserPrincipal currentUser = currentUserProvider.currentUser();
            validateDirectory(secureDataDir, "dataDir", currentUser);
            return loadOrCreatePosix(secureDataDir, currentUser);
        } catch (MasterKeyPermissionException | IllegalStateException exception) {
            throw exception;
        } catch (IOException exception) {
            throw new IllegalStateException("无法加载主密钥文件", exception);
        }
    }

    private SecretKey loadOrCreatePosix(Path dataDir, UserPrincipal currentUser) throws IOException {
        try (DirectoryStream<Path> dataDirectory = Files.newDirectoryStream(dataDir)) {
            if (!(dataDirectory instanceof SecureDirectoryStream<Path> secureDataDirectory)) {
                throw unsupportedFileSystem();
            }
            DirectoryIdentity dataDirectoryIdentity = validateDirectory(dataDir, "dataDir", currentUser);
            try (SecureDirectoryStream<Path> secretsDirectory =
                         openOrCreateSecureSecretsDirectory(secureDataDirectory, dataDir, currentUser)) {
                if (!dataDirectoryIdentity.sameDirectoryAs(validateDirectory(dataDir, "dataDir", currentUser))) {
                    throw new IllegalStateException("dataDir 身份在安全打开期间发生变化");
                }
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
            SecureDirectoryStream<Path> dataDirectory, Path dataDir, UserPrincipal currentUser) throws IOException {
        try {
            DirectoryIdentity before = validateSecureDirectory(
                    dataDirectory, SECRETS_DIRECTORY, "secrets", currentUser);
            SecureDirectoryStream<Path> secretsDirectory =
                    dataDirectory.newDirectoryStream(SECRETS_DIRECTORY, LinkOption.NOFOLLOW_LINKS);
            try {
                DirectoryIdentity after = validateSecureDirectory(
                        dataDirectory, SECRETS_DIRECTORY, "secrets", currentUser);
                if (!before.sameDirectoryAs(after)) {
                    throw new IllegalStateException("secrets 目录身份在安全打开期间发生变化");
                }
                return secretsDirectory;
            } catch (IOException | RuntimeException exception) {
                secretsDirectory.close();
                throw exception;
            }
        } catch (NoSuchFileException exception) {
            try {
                Files.createDirectory(dataDir.resolve(SECRETS_DIRECTORY), OWNER_READ_WRITE_EXECUTE_ATTRIBUTE);
            } catch (FileAlreadyExistsException ignored) {
                // The directory is validated through the already anchored parent below.
            }
            return openOrCreateSecureSecretsDirectory(dataDirectory, dataDir, currentUser);
        }
    }

    private SecretKey createPosixKey(SecureDirectoryStream<Path> secretsDirectory) throws IOException {
        byte[] keyBytes = new byte[KEY_LENGTH_BYTES];
        byte[] encodedKey = null;
        boolean created = false;
        boolean permissionsVerified = false;
        ExistingKeyIdentity createdKeyIdentity = null;
        try {
            new java.security.SecureRandom().nextBytes(keyBytes);
            encodedKey = Base64.getEncoder().encode(keyBytes);
            try (SeekableByteChannel channel = secretsDirectory.newByteChannel(
                    MASTER_KEY_FILE, CREATE_OPTIONS, OWNER_READ_WRITE_ATTRIBUTE)) {
                created = true;
                createdKeyIdentity = readMasterKeyIdentity(secretsDirectory);
                verifyNewKeyPermissions(secretsDirectory, createdKeyIdentity);
                permissionsVerified = true;
                writeFully(channel, encodedKey);
            }
            return new SecretKeySpec(keyBytes, ALGORITHM);
        } catch (IOException | RuntimeException exception) {
            if (created && !permissionsVerified) {
                deleteEmptyNewKey(secretsDirectory, createdKeyIdentity, exception);
            }
            throw exception;
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

        ExistingKeyIdentity before = validateExistingPosixKey(posixAttributeReader.read(view));
        beforeExistingKeyOpen.run(keyFileForVerification);
        try (SeekableByteChannel channel = secretsDirectory.newByteChannel(MASTER_KEY_FILE, READ_OPTIONS)) {
            ExistingKeyIdentity after = validateExistingPosixKey(posixAttributeReader.read(view));
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

    private ExistingKeyIdentity validateExistingKey(PosixFileAttributes attributes) {
        if (attributes.isSymbolicLink() || !attributes.isRegularFile()) {
            throw new IllegalStateException("主密钥文件不能是符号链接且必须为普通文件");
        }
        if (attributes.fileKey() == null) {
            throw new IllegalStateException("无法可靠确认主密钥文件身份");
        }
        return new ExistingKeyIdentity(attributes.fileKey());
    }

    private void createDataDirectoryIfMissing(Path dataDir) throws IOException {
        if (Files.exists(dataDir, LinkOption.NOFOLLOW_LINKS)) {
            return;
        }

        Path parent = dataDir.getParent();
        if (parent == null) {
            throw new IllegalStateException("无法创建 dataDir");
        }
        createDataDirectoryIfMissing(parent);
        try {
            Files.createDirectory(dataDir, OWNER_READ_WRITE_EXECUTE_ATTRIBUTE);
        } catch (FileAlreadyExistsException ignored) {
            // Validate the directory after a concurrent creator wins the race.
        }
    }

    private DirectoryIdentity validateDirectory(Path directory, String label, UserPrincipal currentUser)
            throws IOException {
        PosixFileAttributes attributes = Files.readAttributes(
                directory, PosixFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
        return validateDirectoryAttributes(attributes, label, currentUser);
    }

    private DirectoryIdentity validateSecureDirectory(
            SecureDirectoryStream<Path> parent,
            Path directory,
            String label,
            UserPrincipal currentUser) throws IOException {
        PosixFileAttributeView view = parent.getFileAttributeView(
                directory, PosixFileAttributeView.class, LinkOption.NOFOLLOW_LINKS);
        if (view == null) {
            throw unsupportedFileSystem();
        }
        return validateDirectoryAttributes(view.readAttributes(), label, currentUser);
    }

    private DirectoryIdentity validateDirectoryAttributes(
            PosixFileAttributes attributes, String label, UserPrincipal currentUser) {
        if (attributes.isSymbolicLink() || !attributes.isDirectory()) {
            throw new IllegalStateException(label + " 目录不能是符号链接且必须为目录");
        }
        if (attributes.fileKey() == null) {
            throw new IllegalStateException("无法可靠确认 " + label + " 目录身份");
        }
        if (!currentUser.equals(attributes.owner())) {
            throw new MasterKeyPermissionException(label + " 目录所有者不是当前服务账户，请由当前账户修复");
        }
        if (!OWNER_READ_WRITE_EXECUTE.equals(attributes.permissions())) {
            throw new MasterKeyPermissionException(label + " 目录权限必须为 chmod 700");
        }
        return new DirectoryIdentity(attributes.fileKey());
    }

    private void verifyNewKeyPermissions(
            SecureDirectoryStream<Path> secretsDirectory, ExistingKeyIdentity createdKeyIdentity) throws IOException {
        PosixFileAttributeView view = secretsDirectory.getFileAttributeView(
                MASTER_KEY_FILE, PosixFileAttributeView.class, LinkOption.NOFOLLOW_LINKS);
        if (view == null) {
            throw new MasterKeyPermissionException("无法读取新建主密钥文件权限");
        }

        PosixFileAttributes beforeAttributes = posixAttributeReader.read(view);
        ExistingKeyIdentity before = validateExistingKey(beforeAttributes);
        if (!createdKeyIdentity.sameFileAs(before)) {
            throw new MasterKeyPermissionException("新建主密钥文件身份无法可靠确认");
        }
        if (!OWNER_READ_WRITE.equals(beforeAttributes.permissions())) {
            view.setPermissions(OWNER_READ_WRITE);
        }
        PosixFileAttributes afterAttributes = posixAttributeReader.read(view);
        ExistingKeyIdentity after = validateExistingKey(afterAttributes);
        if (!before.sameFileAs(after)
                || !createdKeyIdentity.sameFileAs(after)
                || !OWNER_READ_WRITE.equals(afterAttributes.permissions())) {
            throw new MasterKeyPermissionException("新建主密钥文件权限无法安全设置为 chmod 600");
        }
    }

    private ExistingKeyIdentity readMasterKeyIdentity(SecureDirectoryStream<Path> secretsDirectory) throws IOException {
        PosixFileAttributeView view = secretsDirectory.getFileAttributeView(
                MASTER_KEY_FILE, PosixFileAttributeView.class, LinkOption.NOFOLLOW_LINKS);
        if (view == null) {
            throw new IllegalStateException("无法读取主密钥文件属性");
        }
        return validateExistingKey(posixAttributeReader.read(view));
    }

    private void deleteEmptyNewKey(
            SecureDirectoryStream<Path> secretsDirectory,
            ExistingKeyIdentity createdKeyIdentity,
            Exception original) {
        if (createdKeyIdentity == null) {
            original.addSuppressed(new IllegalStateException("未捕获主密钥文件身份，保留文件"));
            return;
        }
        try {
            ExistingKeyIdentity currentKeyIdentity = readMasterKeyIdentity(secretsDirectory);
            if (!createdKeyIdentity.sameFileAs(currentKeyIdentity)) {
                original.addSuppressed(new IllegalStateException("主密钥文件已被替换，保留当前文件"));
                return;
            }
            secretsDirectory.deleteFile(MASTER_KEY_FILE);
        } catch (IOException | RuntimeException deletionFailure) {
            original.addSuppressed(deletionFailure);
        }
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

    private static IllegalStateException unsupportedFileSystem() {
        return new IllegalStateException("主密钥仅支持具备 POSIX 权限和 SecureDirectoryStream 的文件系统");
    }

    private static UserPrincipal currentUser() throws IOException {
        String userName = System.getProperty("user.name");
        return FileSystems.getDefault().getUserPrincipalLookupService().lookupPrincipalByName(userName);
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

    @FunctionalInterface
    interface PosixAttributeReader {
        PosixFileAttributes read(PosixFileAttributeView view) throws IOException;
    }

    @FunctionalInterface
    interface CurrentUserProvider {
        UserPrincipal currentUser() throws IOException;
    }

    private record ExistingKeyIdentity(Object fileKey) {
        private boolean sameFileAs(ExistingKeyIdentity other) {
            return Objects.equals(fileKey, other.fileKey);
        }
    }

    private record DirectoryIdentity(Object fileKey) {
        private boolean sameDirectoryAs(DirectoryIdentity other) {
            return Objects.equals(fileKey, other.fileKey);
        }
    }
}
