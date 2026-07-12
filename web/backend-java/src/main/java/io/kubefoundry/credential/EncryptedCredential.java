package io.kubefoundry.credential;

/**
 * 已加密的凭据载体。
 */
public record EncryptedCredential(String ciphertext, String iv, int version) {

    public EncryptedCredential {
        if (ciphertext == null || iv == null) {
            throw new IllegalArgumentException("加密凭据不能为空");
        }
    }
}
