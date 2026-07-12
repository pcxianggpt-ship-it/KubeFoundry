package io.kubefoundry.job;

public class JobQueueFullException extends IllegalStateException {
    public JobQueueFullException() {
        super("任务队列已满，请稍后重试");
    }
}
