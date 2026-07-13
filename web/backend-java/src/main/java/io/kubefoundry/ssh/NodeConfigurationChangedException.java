package io.kubefoundry.ssh;

public class NodeConfigurationChangedException extends IllegalStateException {

    public NodeConfigurationChangedException(long nodeId) {
        super("节点配置已变化，已丢弃本次测试结果: " + nodeId);
    }
}
