package io.kubefoundry.ssh;

import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import java.security.PublicKey;
import org.apache.sshd.client.keyverifier.ServerKeyVerifier;
import org.apache.sshd.common.config.keys.KeyUtils;
import org.apache.sshd.common.digest.BuiltinDigests;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class HostFingerprintVerifier {

    private final NodeRepository nodes;

    public HostFingerprintVerifier(NodeRepository nodes) {
        this.nodes = nodes;
    }

    @Transactional
    public boolean verify(long nodeId, String nodeName, PublicKey serverKey) {
        Node node = nodes.findById(nodeId)
                .orElseThrow(() -> new IllegalArgumentException("节点不存在: " + nodeId));
        return verify(nodeId, nodeName, node.getCluster().getNodeConfigVersion(), serverKey);
    }

    @Transactional
    public boolean verify(
            long nodeId, String nodeName, long expectedConfigVersion, PublicKey serverKey) {
        if (serverKey == null) {
            throw new IllegalArgumentException("SSH 主机公钥不能为空");
        }
        Node node = nodes.findById(nodeId)
                .orElseThrow(() -> new IllegalArgumentException("节点不存在: " + nodeId));
        String fingerprint = KeyUtils.getFingerPrint(BuiltinDigests.sha256, serverKey);
        if (nodes.recordHostFingerprintIfConfigurationUnchanged(
                nodeId, expectedConfigVersion, fingerprint) == 1) {
            return true;
        }
        Node current = nodes.findById(nodeId)
                .orElseThrow(() -> new IllegalArgumentException("节点不存在: " + nodeId));
        if (current.getCluster().getNodeConfigVersion() != expectedConfigVersion) {
            throw new NodeConfigurationChangedException(nodeId);
        }

        String effectiveName = current.getHostname() == null || current.getHostname().isBlank()
                ? nodeName
                : current.getHostname();
        throw new HostFingerprintChangedException(
                "节点 " + effectiveName + " 的 SSH 主机指纹已变化，旧指纹: "
                        + current.getHostFingerprint()
                        + "，新指纹: " + fingerprint + "。请人工确认服务器身份后再处理。");
    }

    public ServerKeyVerifier forNode(long nodeId, String nodeName) {
        return (session, remoteAddress, serverKey) -> verify(nodeId, nodeName, serverKey);
    }

    public ServerKeyVerifier forNode(long nodeId, String nodeName, long expectedConfigVersion) {
        return (session, remoteAddress, serverKey) ->
                verify(nodeId, nodeName, expectedConfigVersion, serverKey);
    }
}
