package io.kubefoundry.installer;

import io.kubefoundry.cluster.Node;
import java.util.Comparator;
import java.util.List;

final class PrimaryControlPlaneSelector {

    private static final Comparator<Node> ORDER = Comparator
            .comparing(Node::getId, Comparator.nullsLast(Long::compareTo))
            .thenComparing(Node::getHostname, Comparator.nullsLast(String::compareTo))
            .thenComparing(Node::getIp, Comparator.nullsLast(String::compareTo));

    private PrimaryControlPlaneSelector() {
    }

    static Node select(List<Node> nodes) {
        if (nodes == null) return null;
        return nodes.stream()
                .filter(node -> node.hasRole("control_plane")
                        || "control_plane".equals(node.getRole()))
                .min(ORDER)
                .orElse(null);
    }
}
