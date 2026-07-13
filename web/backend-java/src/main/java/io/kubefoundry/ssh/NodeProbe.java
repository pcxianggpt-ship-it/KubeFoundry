package io.kubefoundry.ssh;

public record NodeProbe(String osType, String osVersion, String architecture) {
    public NodeProbe {
        if (osType == null || osType.isBlank() || architecture == null || architecture.isBlank()) {
            throw new IllegalArgumentException("操作系统或架构识别失败");
        }
    }
}
