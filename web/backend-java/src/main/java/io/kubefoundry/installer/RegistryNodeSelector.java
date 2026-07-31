package io.kubefoundry.installer;

import io.kubefoundry.cluster.Node;
import java.util.Comparator;
import java.util.List;

final class RegistryNodeSelector {

    private RegistryNodeSelector() {
    }

    static Node select(List<Node> nodes) {
        if (nodes == null) return null;
        return nodes.stream()
                .filter(node -> node.hasRole("registry") || "registry".equals(node.getRole()))
                .min(Comparator.comparing(Node::getId, Comparator.nullsLast(Long::compareTo)))
                .orElse(null);
    }
}
