package io.kubefoundry.credential;

import java.io.IOException;
import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.GroupPrincipal;
import java.nio.file.attribute.PosixFileAttributeView;
import java.nio.file.attribute.PosixFileAttributes;
import java.nio.file.attribute.PosixFilePermission;
import java.nio.file.attribute.UserPrincipal;
import java.nio.file.attribute.FileTime;
import java.util.Base64;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;
import javax.crypto.SecretKey;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class MasterKeyProviderTest {

    private static final Set<PosixFilePermission> OWNER_READ_WRITE_EXECUTE = Set.of(
            PosixFilePermission.OWNER_READ,
            PosixFilePermission.OWNER_WRITE,
            PosixFilePermission.OWNER_EXECUTE);

    @TempDir
    Path temporaryDirectory;

    @BeforeEach
    void prepareSecureDataDirectory() throws IOException {
        if (FileSystems.getDefault().supportedFileAttributeViews().contains("posix")) {
            Files.setPosixFilePermissions(temporaryDirectory, OWNER_READ_WRITE_EXECUTE);
        }
    }

    @Test
    void createsAndReusesBase64Encoded256BitMasterKey() throws IOException {
        assumePosixFileSystem();
        MasterKeyProvider provider = new MasterKeyProvider();

        SecretKey created = provider.loadOrCreate(temporaryDirectory);
        SecretKey loaded = provider.loadOrCreate(temporaryDirectory);
        Path keyFile = temporaryDirectory.resolve("secrets").resolve("master.key");

        assertThat(loaded.getEncoded()).containsExactly(created.getEncoded());
        assertThat(keyFile).isRegularFile();
        assertThat(Base64.getDecoder().decode(Files.readString(keyFile))).hasSize(32);
    }

    @Test
    void rejectsInvalidMasterKeyFileAndNullDataDirectory() throws IOException {
        assumePosixFileSystem();
        Path keyFile = temporaryDirectory.resolve("secrets").resolve("master.key");
        Files.createDirectories(keyFile.getParent());
        Files.setPosixFilePermissions(keyFile.getParent(), OWNER_READ_WRITE_EXECUTE);
        Files.writeString(keyFile, Base64.getEncoder().encodeToString(new byte[31]));
        MasterKeyProvider provider = new MasterKeyProvider();

        assertThatThrownBy(() -> provider.loadOrCreate(temporaryDirectory))
                .isInstanceOf(IllegalStateException.class);
        assertThatIllegalArgumentException().isThrownBy(() -> provider.loadOrCreate(null));
    }

    @Test
    void rejectsExistingMasterKeyFileWithGroupOrOtherPermissions() throws IOException {
        assumePosixFileSystem();
        Path keyFile = temporaryDirectory.resolve("secrets").resolve("master.key");
        Files.createDirectories(keyFile.getParent());
        Files.setPosixFilePermissions(keyFile.getParent(), OWNER_READ_WRITE_EXECUTE);
        Files.writeString(keyFile, Base64.getEncoder().encodeToString(new byte[32]));
        Files.setPosixFilePermissions(keyFile, Set.of(
                PosixFilePermission.OWNER_READ,
                PosixFilePermission.OWNER_WRITE,
                PosixFilePermission.GROUP_READ));

        assertThatThrownBy(() -> new MasterKeyProvider().loadOrCreate(temporaryDirectory))
                .isInstanceOf(MasterKeyPermissionException.class)
                .hasMessageContaining("chmod 600")
                .hasMessageContaining("主密钥");
    }

    @Test
    void failsClosedWhenPosixPermissionsAreUnavailable() {
        Assumptions.assumeFalse(FileSystems.getDefault().supportedFileAttributeViews().contains("posix"));

        assertThatThrownBy(() -> new MasterKeyProvider().loadOrCreate(temporaryDirectory))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("仅支持具备 POSIX 权限和 SecureDirectoryStream 的文件系统");
    }

    @Test
    void createsMasterKeyWithExactOwnerReadWritePermissions() throws IOException {
        assumePosixFileSystem();

        new MasterKeyProvider().loadOrCreate(temporaryDirectory);

        assertThat(Files.getPosixFilePermissions(masterKeyFile()))
                .containsExactlyInAnyOrder(
                        PosixFilePermission.OWNER_READ,
                        PosixFilePermission.OWNER_WRITE);
        assertThat(Files.getPosixFilePermissions(temporaryDirectory.resolve("secrets")))
                .containsExactlyInAnyOrderElementsOf(OWNER_READ_WRITE_EXECUTE);
    }

    @Test
    void rejectsSymbolicLinkForSecretsDirectory() throws IOException {
        assumePosixFileSystem();
        Path targetDirectory = temporaryDirectory.resolve("other-secrets");
        Files.createDirectory(targetDirectory);
        Files.createSymbolicLink(temporaryDirectory.resolve("secrets"), targetDirectory);

        assertThatThrownBy(() -> new MasterKeyProvider().loadOrCreate(temporaryDirectory))
                .isInstanceOf(IllegalStateException.class);
        assertThat(targetDirectory.resolve("master.key")).doesNotExist();
    }

    @Test
    void rejectsSymbolicLinkForMasterKey() throws IOException {
        assumePosixFileSystem();
        Path targetKey = temporaryDirectory.resolve("target.key");
        writeValidKey(targetKey, (byte) 1);
        Files.createDirectory(temporaryDirectory.resolve("secrets"));
        Files.setPosixFilePermissions(temporaryDirectory.resolve("secrets"), OWNER_READ_WRITE_EXECUTE);
        Files.createSymbolicLink(masterKeyFile(), targetKey);

        assertThatThrownBy(() -> new MasterKeyProvider().loadOrCreate(temporaryDirectory))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void rejectsMasterKeyWhenIdentityChangesBeforeSecureOpen() throws IOException {
        assumePosixFileSystem();
        Path keyFile = masterKeyFile();
        Files.createDirectories(keyFile.getParent());
        Files.setPosixFilePermissions(keyFile.getParent(), OWNER_READ_WRITE_EXECUTE);
        writeValidKey(keyFile, (byte) 1);
        Path replacement = temporaryDirectory.resolve("replacement.key");
        writeValidKey(replacement, (byte) 2);

        MasterKeyProvider provider = new MasterKeyProvider(path ->
                Files.move(replacement, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING));

        assertThatThrownBy(() -> provider.loadOrCreate(temporaryDirectory))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void rejectsMasterKeyWhenFileIdentityIsUnavailable() throws IOException {
        assumePosixFileSystem();
        Files.createDirectories(masterKeyFile().getParent());
        Files.setPosixFilePermissions(masterKeyFile().getParent(), OWNER_READ_WRITE_EXECUTE);
        writeValidKey(masterKeyFile(), (byte) 1);

        MasterKeyProvider provider = new MasterKeyProvider(
                view -> attributesWith(view.readAttributes(), null, null),
                path -> { });

        assertThatThrownBy(() -> provider.loadOrCreate(temporaryDirectory))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("无法可靠确认主密钥文件身份");
    }

    @Test
    void correctsNewMasterKeyPermissionsBeforeWriting() throws IOException {
        assumePosixFileSystem();
        AtomicInteger attributeReads = new AtomicInteger();
        MasterKeyProvider provider = new MasterKeyProvider(
                view -> {
                    PosixFileAttributes attributes = view.readAttributes();
                    if (attributeReads.getAndIncrement() == 1) {
                        return attributesWith(attributes, attributes.fileKey(), Set.of(
                                PosixFilePermission.OWNER_READ,
                                PosixFilePermission.OWNER_WRITE,
                                PosixFilePermission.GROUP_READ));
                    }
                    return attributes;
                },
                path -> { });

        provider.loadOrCreate(temporaryDirectory);

        assertThat(Files.getPosixFilePermissions(masterKeyFile()))
                .containsExactlyInAnyOrder(
                        PosixFilePermission.OWNER_READ,
                        PosixFilePermission.OWNER_WRITE);
    }

    @Test
    void deletesEmptyMasterKeyWhenPermissionCorrectionCannotBeVerified() {
        assumePosixFileSystem();
        MasterKeyProvider provider = new MasterKeyProvider(
                view -> {
                    PosixFileAttributes attributes = view.readAttributes();
                    return attributesWith(attributes, attributes.fileKey(), Set.of(
                            PosixFilePermission.OWNER_READ,
                            PosixFilePermission.OWNER_WRITE,
                            PosixFilePermission.GROUP_READ));
                },
                path -> { });

        assertThatThrownBy(() -> provider.loadOrCreate(temporaryDirectory))
                .isInstanceOf(MasterKeyPermissionException.class);
        assertThat(masterKeyFile()).doesNotExist();
    }

    @Test
    void rejectsDataDirectoryWithGroupPermissions() throws IOException {
        assumePosixFileSystem();
        Files.setPosixFilePermissions(temporaryDirectory, Set.of(
                PosixFilePermission.OWNER_READ,
                PosixFilePermission.OWNER_WRITE,
                PosixFilePermission.OWNER_EXECUTE,
                PosixFilePermission.GROUP_READ));

        assertThatThrownBy(() -> new MasterKeyProvider().loadOrCreate(temporaryDirectory))
                .isInstanceOf(MasterKeyPermissionException.class)
                .hasMessageContaining("dataDir")
                .hasMessageContaining("chmod 700");
    }

    @Test
    void rejectsSecretsDirectoryWithGroupPermissions() throws IOException {
        assumePosixFileSystem();
        Path secretsDirectory = temporaryDirectory.resolve("secrets");
        Files.createDirectory(secretsDirectory);
        Files.setPosixFilePermissions(secretsDirectory, Set.of(
                PosixFilePermission.OWNER_READ,
                PosixFilePermission.OWNER_WRITE,
                PosixFilePermission.OWNER_EXECUTE,
                PosixFilePermission.GROUP_READ));

        assertThatThrownBy(() -> new MasterKeyProvider().loadOrCreate(temporaryDirectory))
                .isInstanceOf(MasterKeyPermissionException.class)
                .hasMessageContaining("secrets")
                .hasMessageContaining("chmod 700");
    }

    @Test
    void rejectsDirectoryNotOwnedByCurrentServiceAccount() {
        assumePosixFileSystem();
        MasterKeyProvider provider = new MasterKeyProvider(
                PosixFileAttributeView::readAttributes,
                path -> { },
                () -> () -> "other-service-account");

        assertThatThrownBy(() -> provider.loadOrCreate(temporaryDirectory))
                .isInstanceOf(MasterKeyPermissionException.class)
                .hasMessageContaining("所有者");
    }

    @Test
    void doesNotDeleteReplacementWhenNewMasterKeyIdentityChangesDuringCleanup() throws IOException {
        assumePosixFileSystem();
        Path replacement = temporaryDirectory.resolve("replacement.key");
        writeValidKey(replacement, (byte) 9);
        AtomicInteger attributeReads = new AtomicInteger();
        MasterKeyProvider provider = new MasterKeyProvider(
                view -> {
                    PosixFileAttributes attributes = view.readAttributes();
                    if (attributeReads.getAndIncrement() == 0) {
                        return attributesWith(attributes, attributes.fileKey(), Set.of(
                                PosixFilePermission.OWNER_READ,
                                PosixFilePermission.OWNER_WRITE,
                                PosixFilePermission.GROUP_READ));
                    }
                    if (attributeReads.get() == 2) {
                        Files.move(replacement, masterKeyFile(),
                                StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
                    }
                    return view.readAttributes();
                },
                path -> { });

        assertThatThrownBy(() -> provider.loadOrCreate(temporaryDirectory))
                .isInstanceOf(MasterKeyPermissionException.class);
        assertThat(masterKeyFile()).exists();
        assertThat(replacement).doesNotExist();
    }

    private Path masterKeyFile() {
        return temporaryDirectory.resolve("secrets").resolve("master.key");
    }

    private static void assumePosixFileSystem() {
        Assumptions.assumeTrue(FileSystems.getDefault().supportedFileAttributeViews().contains("posix"));
    }

    private static void writeValidKey(Path path, byte value) throws IOException {
        byte[] key = new byte[32];
        java.util.Arrays.fill(key, value);
        Files.writeString(path, Base64.getEncoder().encodeToString(key));
        Files.setPosixFilePermissions(path, Set.of(
                PosixFilePermission.OWNER_READ,
                PosixFilePermission.OWNER_WRITE));
    }

    private static PosixFileAttributes attributesWith(
            PosixFileAttributes delegate, Object fileKey, Set<PosixFilePermission> permissions) {
        return new PosixFileAttributes() {
            @Override
            public FileTime lastModifiedTime() {
                return delegate.lastModifiedTime();
            }

            @Override
            public FileTime lastAccessTime() {
                return delegate.lastAccessTime();
            }

            @Override
            public FileTime creationTime() {
                return delegate.creationTime();
            }

            @Override
            public boolean isRegularFile() {
                return delegate.isRegularFile();
            }

            @Override
            public boolean isDirectory() {
                return delegate.isDirectory();
            }

            @Override
            public boolean isSymbolicLink() {
                return delegate.isSymbolicLink();
            }

            @Override
            public boolean isOther() {
                return delegate.isOther();
            }

            @Override
            public long size() {
                return delegate.size();
            }

            @Override
            public Object fileKey() {
                return fileKey;
            }

            @Override
            public UserPrincipal owner() {
                return delegate.owner();
            }

            @Override
            public GroupPrincipal group() {
                return delegate.group();
            }

            @Override
            public Set<PosixFilePermission> permissions() {
                return permissions == null ? delegate.permissions() : permissions;
            }
        };
    }
}
