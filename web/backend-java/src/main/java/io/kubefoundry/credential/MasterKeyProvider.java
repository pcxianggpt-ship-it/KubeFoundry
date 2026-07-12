package io.kubefoundry.credential;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.PosixFileAttributeView;
import java.nio.file.attribute.PosixFilePermission;
import java.util.Arrays;
import java.util.Base64;
import java.util.Set;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;

/**
 * 管理存放在数据目录之外的 H2 主密钥文件。
 */
public final class MasterKeyProvider {

    private static final String ALGORITHM = "AES";
    private static final int KEY_LENGTH_BYTES = 32;
    private static final Set<PosixFilePermission> OWNER_READ_WRITE = Set.of(
            PosixFilePermission.OWNER_READ,
            PosixFilePermission.OWNER_WRITE);

    public SecretKey loadOrCreate(Path dataDir) {
        if (dataDir == null) {
            throw new IllegalArgumentException("数据目录不能为空");
        }

        Path keyFile = dataDir.resolve("secrets").resolve("master.key");
        try {
            Files.createDirectories(keyFile.getParent());
            if (Files.exists(keyFile)) {
                validateExistingFilePermissions(keyFile);
                return readKey(keyFile);
            }
            return createKey(keyFile);
        } catch (MasterKeyPermissionException | IllegalStateException exception) {
            throw exception;
        } catch (IOException exception) {
            throw new IllegalStateException("无法加载主密钥文件", exception);
        }
    }

    private SecretKey createKey(Path keyFile) throws IOException {
        byte[] keyBytes = new byte[KEY_LENGTH_BYTES];
        try {
            new java.security.SecureRandom().nextBytes(keyBytes);
            String encoded = Base64.getEncoder().encodeToString(keyBytes);
            try {
                Files.writeString(keyFile, encoded, StandardCharsets.US_ASCII,
                        StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
                setOwnerReadWritePermissions(keyFile);
                return new SecretKeySpec(keyBytes, ALGORITHM);
            } catch (FileAlreadyExistsException exception) {
                validateExistingFilePermissions(keyFile);
                return readKey(keyFile);
            }
        } finally {
            Arrays.fill(keyBytes, (byte) 0);
        }
    }

    private SecretKey readKey(Path keyFile) throws IOException {
        byte[] keyBytes = null;
        try {
            keyBytes = Base64.getDecoder().decode(Files.readString(keyFile, StandardCharsets.US_ASCII));
            if (keyBytes.length != KEY_LENGTH_BYTES) {
                throw new IllegalStateException("主密钥文件内容无效");
            }
            return new SecretKeySpec(keyBytes, ALGORITHM);
        } catch (IllegalArgumentException exception) {
            throw new IllegalStateException("主密钥文件内容无效");
        } finally {
            if (keyBytes != null) {
                Arrays.fill(keyBytes, (byte) 0);
            }
        }
    }

    private void validateExistingFilePermissions(Path keyFile) throws IOException {
        PosixFileAttributeView view = Files.getFileAttributeView(keyFile, PosixFileAttributeView.class);
        if (view == null) {
            return;
        }

        Set<PosixFilePermission> permissions = view.readAttributes().permissions();
        boolean groupOrOtherCanAccess = permissions.stream()
                .anyMatch(permission -> permission.name().startsWith("GROUP_")
                        || permission.name().startsWith("OTHERS_"));
        if (groupOrOtherCanAccess) {
            throw new MasterKeyPermissionException("主密钥文件权限过宽，请执行 chmod 600 " + keyFile);
        }
    }

    private void setOwnerReadWritePermissions(Path keyFile) throws IOException {
        PosixFileAttributeView view = Files.getFileAttributeView(keyFile, PosixFileAttributeView.class);
        if (view != null) {
            view.setPermissions(OWNER_READ_WRITE);
        }
    }
}
