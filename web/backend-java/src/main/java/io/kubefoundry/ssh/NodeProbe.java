package io.kubefoundry.ssh;

public record NodeProbe(String remoteHostname, String osType, String osVersion, String architecture) {
    public NodeProbe {
        if (remoteHostname == null || remoteHostname.isBlank()
                || osType == null || osType.isBlank()
                || architecture == null || architecture.isBlank()) {
            throw new IllegalArgumentException("远端主机名、操作系统或架构识别失败");
        }
    }
}
