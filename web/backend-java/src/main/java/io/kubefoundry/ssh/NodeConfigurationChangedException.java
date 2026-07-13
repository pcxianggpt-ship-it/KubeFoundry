package io.kubefoundry.ssh;

public class NodeConfigurationChangedException extends IllegalStateException {

    public NodeConfigurationChangedException(long nodeId) {
        super("节点配置已变化，已丢弃本次测试结果: " + nodeId);
    }

    public static NodeConfigurationChangedException forCluster(long clusterId) {
        return new NodeConfigurationChangedException(
                "集群节点配置已变化，未启动旧版本测试任务: " + clusterId);
    }

    private NodeConfigurationChangedException(String message) {
        super(message);
    }
}
