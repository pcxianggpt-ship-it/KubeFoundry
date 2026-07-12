package io.kubefoundry.credential;

import java.io.IOException;
import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.PosixFilePermission;
import java.util.Base64;
import java.util.Set;
import javax.crypto.SecretKey;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class MasterKeyProviderTest {

    @TempDir
    Path temporaryDirectory;

    @Test
    void createsAndReusesBase64Encoded256BitMasterKey() throws IOException {
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
        Path keyFile = temporaryDirectory.resolve("secrets").resolve("master.key");
        Files.createDirectories(keyFile.getParent());
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
    void createsMasterKeyWithExactOwnerReadWritePermissions() throws IOException {
        assumePosixFileSystem();

        new MasterKeyProvider().loadOrCreate(temporaryDirectory);

        assertThat(Files.getPosixFilePermissions(masterKeyFile()))
                .containsExactlyInAnyOrder(
                        PosixFilePermission.OWNER_READ,
                        PosixFilePermission.OWNER_WRITE);
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
        Files.createSymbolicLink(masterKeyFile(), targetKey);

        assertThatThrownBy(() -> new MasterKeyProvider().loadOrCreate(temporaryDirectory))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void rejectsMasterKeyWhenIdentityChangesBeforeSecureOpen() throws IOException {
        assumePosixFileSystem();
        Path keyFile = masterKeyFile();
        Files.createDirectories(keyFile.getParent());
        writeValidKey(keyFile, (byte) 1);
        Path replacement = temporaryDirectory.resolve("replacement.key");
        writeValidKey(replacement, (byte) 2);

        MasterKeyProvider provider = new MasterKeyProvider(path ->
                Files.move(replacement, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING));

        assertThatThrownBy(() -> provider.loadOrCreate(temporaryDirectory))
                .isInstanceOf(IllegalStateException.class);
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
}
