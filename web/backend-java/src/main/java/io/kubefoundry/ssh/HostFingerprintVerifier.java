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
    public synchronized boolean verify(long nodeId, String nodeName, PublicKey serverKey) {
        if (serverKey == null) {
            throw new IllegalArgumentException("SSH 主机公钥不能为空");
        }
        Node node = nodes.findById(nodeId)
                .orElseThrow(() -> new IllegalArgumentException("节点不存在: " + nodeId));
        String fingerprint = KeyUtils.getFingerPrint(BuiltinDigests.sha256, serverKey);
        String stored = node.getHostFingerprint();
        if (stored == null || stored.isBlank()) {
            node.recordHostFingerprint(fingerprint);
            nodes.save(node);
            return true;
        }
        if (stored.equals(fingerprint)) {
            return true;
        }

        String effectiveName = node.getHostname() == null || node.getHostname().isBlank()
                ? nodeName
                : node.getHostname();
        throw new HostFingerprintChangedException(
                "节点 " + effectiveName + " 的 SSH 主机指纹已变化，旧指纹: " + stored
                        + "，新指纹: " + fingerprint + "。请人工确认服务器身份后再处理。");
    }

    public ServerKeyVerifier forNode(long nodeId, String nodeName) {
        return (session, remoteAddress, serverKey) -> verify(nodeId, nodeName, serverKey);
    }
}
