package io.kubefoundry.credential;

/**
 * 凭据不能被安全解密时抛出。
 */
public final class CredentialDecryptionException extends RuntimeException {

    public CredentialDecryptionException() {
        super("凭据解密失败");
    }
}
