package io.kubefoundry.job;

public class JobNotFoundException extends RuntimeException {

    private final long jobId;

    public JobNotFoundException(long jobId) {
        super("任务不存在: " + jobId);
        this.jobId = jobId;
    }

    public long jobId() {
        return jobId;
    }
}
