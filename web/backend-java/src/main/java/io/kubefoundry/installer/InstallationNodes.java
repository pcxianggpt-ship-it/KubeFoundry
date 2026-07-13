package io.kubefoundry.installer;

import io.kubefoundry.cluster.Node;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;

final class InstallationNodes {

    private static final Comparator<Node> ORDER = Comparator
            .comparing(Node::getId, Comparator.nullsLast(Long::compareTo))
            .thenComparing(Node::getHostname, Comparator.nullsLast(String::compareTo))
            .thenComparing(Node::getIp, Comparator.nullsLast(String::compareTo))
            .thenComparing(Node::getRole, Comparator.nullsLast(String::compareTo));

    private InstallationNodes() {
    }

    static List<Node> normalize(List<Node> nodes) {
        if (nodes == null || nodes.isEmpty()) return List.of();
        LinkedHashMap<String, Node> unique = new LinkedHashMap<>();
        nodes.stream().sorted(ORDER).forEach(node -> {
            String identity = node.getIp() == null || node.getIp().isBlank()
                    ? "id:" + node.getId() : "ip:" + node.getIp().trim();
            unique.putIfAbsent(identity, node);
        });
        return List.copyOf(unique.values());
    }
}
