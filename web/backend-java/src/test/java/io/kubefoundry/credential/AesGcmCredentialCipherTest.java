package io.kubefoundry.credential;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Arrays;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class AesGcmCredentialCipherTest {

    @Test
    void encryptsAndDecryptsUnicodePlaintext() {
        AesGcmCredentialCipher cipher = new AesGcmCredentialCipher(newMasterKey());
        char[] plaintext = "密码-hello-秘密".toCharArray();

        EncryptedCredential encrypted = cipher.encrypt(plaintext);
        char[] decrypted = cipher.decrypt(encrypted);

        assertThat(encrypted.version()).isEqualTo(1);
        assertThat(decrypted).containsExactly(plaintext);
        Arrays.fill(decrypted, '\0');
    }

    @Test
    void generatesDifferentIvAndCiphertextForTheSamePlaintext() {
        AesGcmCredentialCipher cipher = new AesGcmCredentialCipher(newMasterKey());
        char[] plaintext = "same-secret".toCharArray();

        EncryptedCredential first = cipher.encrypt(plaintext);
        EncryptedCredential second = cipher.encrypt(plaintext);

        assertThat(first.iv()).isNotEqualTo(second.iv());
        assertThat(first.ciphertext()).isNotEqualTo(second.ciphertext());
    }

    @Test
    void rejectsWrongKeyCorruptedCiphertextAndUnsupportedVersionWithoutLeakingSecrets() {
        char[] plaintext = "do-not-leak".toCharArray();
        EncryptedCredential encrypted = new AesGcmCredentialCipher(newMasterKey()).encrypt(plaintext);
        AesGcmCredentialCipher wrongKeyCipher = new AesGcmCredentialCipher(newMasterKey());

        assertDecryptionFailsWithoutSecrets(() -> wrongKeyCipher.decrypt(encrypted), plaintext, encrypted);
        assertDecryptionFailsWithoutSecrets(
                () -> new AesGcmCredentialCipher(newMasterKey())
                        .decrypt(new EncryptedCredential("not-base64", encrypted.iv(), encrypted.version())),
                plaintext,
                encrypted);
        assertDecryptionFailsWithoutSecrets(
                () -> new AesGcmCredentialCipher(newMasterKey())
                        .decrypt(new EncryptedCredential(encrypted.ciphertext(), encrypted.iv(), 2)),
                plaintext,
                encrypted);
    }

    @Test
    void permitsEmptyPlaintextAndRejectsNullParameters() {
        AesGcmCredentialCipher cipher = new AesGcmCredentialCipher(newMasterKey());
        char[] decrypted = cipher.decrypt(cipher.encrypt(new char[0]));

        assertThat(decrypted).isEmpty();
        assertThatIllegalArgumentException().isThrownBy(() -> cipher.encrypt(null));
        assertThatIllegalArgumentException().isThrownBy(() -> cipher.decrypt(null));
        assertThatIllegalArgumentException().isThrownBy(() -> new AesGcmCredentialCipher(null));
    }

    private static SecretKey newMasterKey() {
        byte[] key = new byte[32];
        new SecureRandom().nextBytes(key);
        return new SecretKeySpec(key, "AES");
    }

    private static void assertDecryptionFailsWithoutSecrets(
            ThrowingCallable callable, char[] plaintext, EncryptedCredential credential) {
        assertThatThrownBy(callable::call)
                .isInstanceOf(CredentialDecryptionException.class)
                .satisfies(exception -> assertThat(exception.getMessage())
                        .doesNotContain(new String(plaintext))
                        .doesNotContain(credential.ciphertext())
                        .doesNotContain(credential.iv()));
    }

    @FunctionalInterface
    private interface ThrowingCallable {
        void call();
    }
}
