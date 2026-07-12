package io.kubefoundry.credential;

/**
 * 主密钥文件权限不符合要求时抛出。
 */
public final class MasterKeyPermissionException extends RuntimeException {

    public MasterKeyPermissionException(String message) {
        super(message);
    }
}
