package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import org.springframework.stereotype.Component;

@Component
public class RuntimeEnvRenderer {

    public String render(Cluster cluster, List<Node> nodes, Node node) {
        Node primary = nodes.stream()
                .filter(item -> "control_plane".equals(item.getRole()))
                .sorted(Comparator.comparing(Node::getHostname)
                        .thenComparing(Node::getIp))
                .findFirst().orElse(null);
        Map<String, String> values = new TreeMap<>();
        values.put("KF_ARCH", value(node.getArchitecture(), "amd64"));
        values.put("KF_CLUSTER_NAME", cluster.getName());
        values.put("KF_CONTAINERD_ROOT", "/data/k8s_install/containerd-data");
        values.put("KF_DUAL_STACK", "N");
        values.put("KF_ETCD_DATA_DIR", "/data/k8s_install/etcd_backup");
        values.put("KF_INSTALL_MEDIA", "/root/kube-media");
        values.put("KF_K8S_HOME", "/data/k8s_install");
        values.put("KF_K8S_VERSION", cluster.getKubernetesVersion());
        values.put("KF_KUBELET_ROOT", "/data/k8s_install/kubelet_root");
        values.put("KF_NODE_HOSTNAME", node.getHostname());
        values.put("KF_NODE_IP", node.getIp());
        values.put("KF_NODE_ROLE", node.getRole());
        values.put("KF_POD_SUBNET", cluster.getPodSubnet());
        values.put("KF_PRIMARY_CONTROL_HOSTNAME", primary == null ? "" : primary.getHostname());
        values.put("KF_PRIMARY_CONTROL_IP", primary == null ? "" : primary.getIp());
        values.put("KF_REGISTRY_HOSTNAME", value(cluster.getRegistryHostname(), "registry"));
        values.put("KF_REGISTRY_IP", cluster.getRegistryIp());
        values.put("KF_REGISTRY_PORT", Integer.toString(cluster.getRegistryPort()));
        values.put("KF_SERVICE_SUBNET", cluster.getServiceSubnet());

        Map<String, String> compatibility = new TreeMap<>();
        compatibility.put("ARCH", "KF_ARCH");
        compatibility.put("CONTAINERD_ROOT", "KF_CONTAINERD_ROOT");
        compatibility.put("DUAL_STACK", "KF_DUAL_STACK");
        compatibility.put("ETCD_DATA_DIR", "KF_ETCD_DATA_DIR");
        compatibility.put("INSTALL_MEDIA", "KF_INSTALL_MEDIA");
        compatibility.put("K8S_HOME", "KF_K8S_HOME");
        compatibility.put("K8S_SOFT", "KF_K8S_HOME");
        compatibility.put("K8S_VERSION", "KF_K8S_VERSION");
        compatibility.put("KUBELET_ROOT", "KF_KUBELET_ROOT");
        compatibility.put("POD_SUBNET", "KF_POD_SUBNET");
        compatibility.put("PRIMARY_CONTROL_HOSTNAME", "KF_PRIMARY_CONTROL_HOSTNAME");
        compatibility.put("PRIMARY_CONTROL_IP", "KF_PRIMARY_CONTROL_IP");
        compatibility.put("REGISTRY_HOSTNAME", "KF_REGISTRY_HOSTNAME");
        compatibility.put("REGISTRY_IP", "KF_REGISTRY_IP");
        compatibility.put("REGISTRY_PORT", "KF_REGISTRY_PORT");
        compatibility.put("SERVICE_SUBNET", "KF_SERVICE_SUBNET");

        StringBuilder output = new StringBuilder();
        output.append("#!/bin/bash\n\n")
                .append("log_info() { printf '\\033[0;34m[INFO]\\033[0m %s\\n' \"$*\"; }\n")
                .append("log_success() { printf '\\033[0;32m[SUCCESS]\\033[0m %s\\n' \"$*\"; }\n")
                .append("log_warn() { printf '\\033[0;33m[WARN]\\033[0m %s\\n' \"$*\"; }\n")
                .append("log_error() { printf '\\033[0;31m[ERROR]\\033[0m %s\\n' \"$*\" >&2; }\n")
                .append("log_substep() { printf '\\n\\033[0;36m==> %s\\033[0m\\n' \"$*\"; }\n")
                .append("log_separator() { printf '%s\\n' '============================================================'; }\n")
                .append("export -f log_info log_success log_warn log_error log_substep log_separator\n\n");
        values.forEach((key, item) -> output.append("export ").append(key).append('=')
                .append(shellQuote(item)).append('\n'));
        compatibility.forEach((key, source) -> output.append("export ").append(key)
                .append("=\"${").append(source).append("}\"\n"));
        return output.append('\n').toString();
    }

    public static String shellQuote(String value) {
        return "'" + (value == null ? "" : value).replace("'", "'\"'\"'") + "'";
    }

    private static String value(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }
}
