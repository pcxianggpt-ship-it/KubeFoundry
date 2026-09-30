package io.kubefoundry.installer;

public class MinioWorkerCountException extends IllegalStateException {
    public static final int REQUIRED_WORKERS = 4;
    private final int actualWorkers;

    public MinioWorkerCountException(int actualWorkers) {
        super("启用 MinIO 至少需要 4 个工作节点，当前为 " + actualWorkers + " 个");
        this.actualWorkers = actualWorkers;
    }

    public int actualWorkers() {
        return actualWorkers;
    }
}
