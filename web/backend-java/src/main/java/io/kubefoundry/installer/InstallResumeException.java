package io.kubefoundry.installer;

/** Stable, credential-free rejection returned by the installation resume boundary. */
public class InstallResumeException extends RuntimeException {
    private final String code;

    public InstallResumeException(String code, String message) {
        super(message);
        if (code == null || !code.matches("RESUME_[A-Z0-9_]+")) {
            throw new IllegalArgumentException("续跑错误码不合法");
        }
        this.code = code;
    }

    public String code() {
        return code;
    }
}
