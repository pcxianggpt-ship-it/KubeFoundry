package io.kubefoundry.credential;

import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * 使用 AES-256-GCM 加密和解密节点凭据。
 */
public final class AesGcmCredentialCipher {

    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final String ALGORITHM = "AES";
    private static final int KEY_LENGTH_BYTES = 32;
    private static final int IV_LENGTH_BYTES = 12;
    private static final int TAG_LENGTH_BITS = 128;
    private static final int VERSION = 1;

    private final SecretKey masterKey;
    private final SecureRandom secureRandom;

    public AesGcmCredentialCipher(SecretKey masterKey) {
        if (masterKey == null) {
            throw new IllegalArgumentException("主密钥不能为空");
        }

        validateMasterKey(masterKey);
        this.masterKey = masterKey;
        this.secureRandom = new SecureRandom();
    }

    public EncryptedCredential encrypt(char[] plaintext) {
        if (plaintext == null) {
            throw new IllegalArgumentException("明文不能为空");
        }

        byte[] plaintextBytes = toUtf8Bytes(plaintext);
        byte[] iv = new byte[IV_LENGTH_BYTES];
        byte[] ciphertext = null;
        try {
            secureRandom.nextBytes(iv);
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.ENCRYPT_MODE, masterKey, new GCMParameterSpec(TAG_LENGTH_BITS, iv));
            ciphertext = cipher.doFinal(plaintextBytes);
            return new EncryptedCredential(
                    Base64.getEncoder().encodeToString(ciphertext),
                    Base64.getEncoder().encodeToString(iv),
                    VERSION);
        } catch (GeneralSecurityException exception) {
            throw new IllegalStateException("无法加密凭据", exception);
        } finally {
            Arrays.fill(plaintextBytes, (byte) 0);
            Arrays.fill(iv, (byte) 0);
            clear(ciphertext);
        }
    }

    public char[] decrypt(EncryptedCredential credential) {
        if (credential == null) {
            throw new IllegalArgumentException("加密凭据不能为空");
        }
        if (credential.version() != VERSION) {
            throw new CredentialDecryptionException();
        }

        byte[] ciphertext = null;
        byte[] iv = null;
        byte[] plaintextBytes = null;
        try {
            ciphertext = Base64.getDecoder().decode(credential.ciphertext());
            iv = Base64.getDecoder().decode(credential.iv());
            if (iv.length != IV_LENGTH_BYTES) {
                throw new CredentialDecryptionException();
            }

            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.DECRYPT_MODE, masterKey, new GCMParameterSpec(TAG_LENGTH_BITS, iv));
            plaintextBytes = cipher.doFinal(ciphertext);
            return toChars(plaintextBytes);
        } catch (GeneralSecurityException | RuntimeException exception) {
            throw new CredentialDecryptionException();
        } finally {
            clear(ciphertext);
            clear(iv);
            clear(plaintextBytes);
        }
    }

    private static void validateMasterKey(SecretKey masterKey) {
        byte[] encoded = masterKey.getEncoded();
        try {
            if (!ALGORITHM.equalsIgnoreCase(masterKey.getAlgorithm())
                    || encoded == null
                    || encoded.length != KEY_LENGTH_BYTES) {
                throw new IllegalArgumentException("主密钥必须为 256 位 AES 密钥");
            }
        } finally {
            clear(encoded);
        }
    }

    private static byte[] toUtf8Bytes(char[] plaintext) {
        ByteBuffer encoded = StandardCharsets.UTF_8.encode(CharBuffer.wrap(plaintext));
        try {
            byte[] bytes = new byte[encoded.remaining()];
            encoded.get(bytes);
            return bytes;
        } finally {
            if (encoded.hasArray()) {
                Arrays.fill(encoded.array(), (byte) 0);
            }
        }
    }

    private static char[] toChars(byte[] plaintextBytes) {
        CharBuffer decoded = StandardCharsets.UTF_8.decode(ByteBuffer.wrap(plaintextBytes));
        try {
            char[] chars = new char[decoded.remaining()];
            decoded.get(chars);
            return chars;
        } finally {
            if (decoded.hasArray()) {
                Arrays.fill(decoded.array(), '\0');
            }
        }
    }

    private static void clear(byte[] bytes) {
        if (bytes != null) {
            Arrays.fill(bytes, (byte) 0);
        }
    }
}
