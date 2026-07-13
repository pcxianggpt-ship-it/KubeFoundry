package io.kubefoundry.installer;

public final class ActiveInstallerJobException extends RuntimeException {

    private final long jobId;

    ActiveInstallerJobException(String type, long jobId) {
        super("集群已有活动的 " + type + " 任务: " + jobId);
        this.jobId = jobId;
    }

    public long jobId() { return jobId; }
}
