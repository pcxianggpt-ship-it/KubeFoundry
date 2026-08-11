package io.kubefoundry.installer;

import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.Cluster;
import java.nio.file.Path;
import java.nio.file.Files;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Predicate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

@Component
public class BaseInstallPlanFactory {

    private final Path projectRoot;
    private final NfsTargetResolver nfsTargets;

    public BaseInstallPlanFactory(Path projectRoot) {
        this(projectRoot, null);
    }

    @Autowired
    public BaseInstallPlanFactory(
            @Value("${kubefoundry.project-dir:}") String configuredProjectRoot,
            NfsTargetResolver nfsTargets) {
        this(configuredProjectRoot == null || configuredProjectRoot.isBlank()
                ? discoverProjectRoot(Path.of("").toAbsolutePath())
                : Path.of(configuredProjectRoot), nfsTargets);
    }

    private BaseInstallPlanFactory(Path projectRoot, NfsTargetResolver nfsTargets) {
        this.projectRoot = projectRoot.toAbsolutePath().normalize();
        this.nfsTargets = nfsTargets;
    }

    public InstallPlan create() {
        return new InstallPlan(List.of(
                script("10-setup-yum-source", "配置 Kubernetes YUM 源", "primary_control_plane",
                        "10-setup-yum-source.sh", "serial", 1, true,
                        List.of(pathResource("repo_source", "file", "/tmp/k8s/k8s-repo-source.tar.gz")),
                        List.of(literal("/tmp/k8s/k8s-repo-source.tar.gz")), List.of(),
                        "systemctl is-active httpd >/dev/null && yum -q repolist | grep -q k8s"),
                InstallStep.builtin("11b-setup-hostname", "配置主机名和 hosts", "k8s_base",
                        "all_nodes", "setup_hostname", "parallel", 5, false,
                        "test \"$(hostname)\" = {node_hostname} && grep -q '^# >>>KubeFoundry>>>$' /etc/hosts"),
                script("12-setup-k8s-repo", "配置 Kubernetes HTTP Repo", "non_primary_k8s_nodes",
                        "12-setup-k8s-repo.sh", "parallel", 5, false, List.of(), List.of(), List.of(),
                        "test -f /etc/yum.repos.d/k8s-http.repo && yum -q repolist | grep -q k8s-repo"),
                script("13-install-k8s-deps", "安装 Kubernetes 依赖", "all_k8s_nodes",
                        "13-install-k8s-deps.sh", "parallel", 5, false, List.of(), List.of(), List.of(),
                        "command -v kubeadm >/dev/null && command -v kubelet >/dev/null && systemctl is-enabled kubelet >/dev/null"),
                script("14-replace-kubeadm", "替换长期证书 kubeadm", "primary_control_plane",
                        "14-replace-kubeadm.sh", "serial", 1, true,
                        List.of(pathResource("kubeadm_100y", "file", "/tmp/k8s/kubeadm-100y")),
                        List.of(), List.of(),
                        "test -x /usr/bin/kubeadm && test -f /tmp/k8s/kubeadm_bak"),
                script("15-environment-config", "环境配置", "all_nodes",
                        "15-environment-config.sh", "parallel", 5, false,
                        List.of(), List.of(), List.of(),
                        "test -z \"$(swapon --show --noheadings)\" && test \"$(sysctl -n net.ipv4.ip_forward)\" = 1"),
                script("16-install-containerd", "安装 containerd", "all_nodes",
                        "16-install-containerd.sh", "parallel", 5, false,
                        List.of(pathResource("container_runtime", "directory", "/tmp/k8s/02.container_runtime")),
                        List.of(), List.of(),
                        "systemctl is-active containerd >/dev/null && command -v runc >/dev/null && command -v nerdctl >/dev/null"),
                script("17-install-registry", "安装镜像仓库", "registry",
                        "17-install-registry.sh", "serial", 1, true,
                        List.of(pathResource("registry_install", "directory", "{k8s_home}/04.registry")),
                        List.of(), List.of(),
                        "(nerdctl ps 2>/dev/null || docker ps 2>/dev/null) | grep -q registry"),
                script("18-init-k8s-cluster", "初始化 Kubernetes 集群", "primary_control_plane",
                        "18-init-k8s-cluster.sh", "serial", 1, true, List.of(), List.of(),
                        List.of(new InstallStep.Output("control_join", "/tmp/k8s/kube_join_master"),
                                new InstallStep.Output("worker_join", "/tmp/k8s/kube_join_nodes")),
                        "test -f /etc/kubernetes/admin.conf && KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes >/dev/null"),
                script("19-modify-cert-expiry", "修改证书有效期", "primary_control_plane",
                        "19-modify-cert-expiry.sh", "serial", 1, true, List.of(), List.of(), List.of(),
                        "grep -q cluster-signing-duration /etc/kubernetes/manifests/kube-controller-manager.yaml"),
                script("20-add-control-nodes", "加入其他控制节点", "other_control_planes",
                        "20-add-control-nodes.sh", "serial", 1, true,
                        List.of(artifactResource("control_join", "/tmp/k8s/kube_join_master")),
                        List.of(context("primary_control_ip")), List.of(),
                        "systemctl is-active kubelet >/dev/null && test -f /etc/kubernetes/kubelet.conf"),
                script("21-add-worker-nodes", "加入工作节点", "workers",
                        "21-add-worker-nodes.sh", "parallel", 5, false,
                        List.of(artifactResource("worker_join", "/tmp/k8s/kube_join_nodes")),
                        List.of(), List.of(),
                        "systemctl is-active kubelet >/dev/null && test -f /etc/kubernetes/kubelet.conf"),
                script("22-install-cni-flannel", "安装 Flannel CNI", "primary_control_plane",
                        "22-install-cni-flannel.sh", "serial", 1, true,
                        List.of(pathResource("flannel_config", "file", "/tmp/k8s/kube-flannel.yml")),
                        List.of(), List.of(),
                        "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A | grep -q flannel"),
                script("23-configure-coredns-affinity", "配置 CoreDNS 副本反亲和", "primary_control_plane",
                        "23-configure-coredns-affinity.sh", "serial", 1, true,
                        List.of(), List.of(), List.of(),
                        "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get deployment coredns -n kube-system "
                                + "-o jsonpath='{.metadata.annotations.kubefoundry\\.io/coredns-anti-affinity}' "
                                + "| grep -qx v2"),
                InstallStep.builtin("web-verify-cluster-health", "验证 Kubernetes 集群健康",
                        "verify", "primary_control_plane", "cluster_health",
                        "serial", 1, true, "")));
    }

    public InstallPlan select(List<String> selectedKeys) {
        InstallPlan complete = create();
        if (selectedKeys == null || selectedKeys.isEmpty()) return complete;
        Set<String> selected = new HashSet<>(selectedKeys);
        Set<String> known = complete.steps().stream().map(InstallStep::key)
                .collect(java.util.stream.Collectors.toSet());
        List<String> unknown = selected.stream().filter(key -> !known.contains(key)).sorted().toList();
        if (!unknown.isEmpty()) throw new IllegalArgumentException("未知安装步骤: " + String.join(", ", unknown));
        List<InstallStep> steps = complete.steps().stream()
                .filter(step -> selected.contains(step.key())).toList();
        validateArtifactDependencies(steps);
        return new InstallPlan(steps);
    }

    public List<Node> resolveTargets(InstallStep step, List<Node> configuredNodes) {
        return resolveTargets(step, null, configuredNodes);
    }

    public List<Node> resolveTargets(InstallStep step, Cluster cluster, List<Node> configuredNodes) {
        List<Node> nodes = InstallationNodes.normalize(configuredNodes);
        if (nfsTargets != null && "nfs_server".equals(step.targetScope())) {
            List<Node> resolved = nfsTargets.resolve(step, cluster, nodes);
            return resolved == null ? List.of() : resolved;
        }
        List<Node> controls = filter(nodes, node -> hasRole(node, "control_plane"));
        Node primary = PrimaryControlPlaneSelector.select(nodes);
        return switch (step.targetScope()) {
            case "all_nodes" -> nodes;
            case "all_k8s_nodes" -> filter(nodes,
                    node -> hasRole(node, "control_plane") || hasRole(node, "worker"));
            case "control_plane" -> controls;
            case "workers" -> {
                List<Node> workers = filter(nodes, node -> hasRole(node, "worker"));
                yield nfsTargets != null && "nfs".equals(step.componentGroupKey())
                        && "32-mount-nfs-workers".equals(step.key())
                        ? nfsTargets.mountTargets(cluster, workers) : workers;
            }
            case "non_primary_k8s_nodes" -> filter(nodes,
                    node -> (hasRole(node, "control_plane") || hasRole(node, "worker"))
                            && (primary == null || !node.getId().equals(primary.getId())));
            case "registry" -> {
                List<Node> registries = filter(nodes, node -> hasRole(node, "registry"));
                yield registries.isEmpty() && cluster != null && !cluster.getRegistryIp().isBlank()
                        ? filter(nodes, node -> cluster.getRegistryIp().equals(node.getIp())) : registries;
            }
            case "primary_control_plane" -> primary == null ? List.of() : List.of(primary);
            case "other_control_planes" -> filter(controls,
                    node -> primary == null || !node.getId().equals(primary.getId()));
            default -> List.of();
        };
    }

    private InstallStep script(
            String key, String name, String scope, String scriptName, String mode,
            int maxWorkers, boolean failFast, List<InstallStep.Resource> resources,
            List<InstallStep.Argument> arguments, List<InstallStep.Output> outputs,
            String verifyCommand) {
        return InstallStep.script(key, name, "k8s_base", scope,
                projectRoot.resolve("scripts/steps/phase2_k8s_base").resolve(scriptName),
                mode, maxWorkers, failFast, resources, arguments, outputs, verifyCommand);
    }

    private static InstallStep.Resource pathResource(String key, String kind, String remotePath) {
        return new InstallStep.Resource(key, null, kind, remotePath);
    }

    private static InstallStep.Resource artifactResource(String key, String remotePath) {
        return new InstallStep.Resource(null, key, "file", remotePath);
    }

    private static InstallStep.Argument literal(String value) {
        return new InstallStep.Argument(value, null);
    }

    private static InstallStep.Argument context(String key) {
        return new InstallStep.Argument(null, key);
    }

    private static List<Node> filter(List<Node> nodes, Predicate<Node> predicate) {
        return nodes.stream().filter(predicate).toList();
    }

    private static boolean hasRole(Node node, String role) {
        return node.hasRole(role) || role.equals(node.getRole());
    }

    private static void validateArtifactDependencies(List<InstallStep> steps) {
        Set<String> produced = new HashSet<>();
        for (InstallStep step : steps) {
            for (InstallStep.Resource resource : step.resources()) {
                if (resource.artifactKey() != null && !produced.contains(resource.artifactKey())) {
                    throw new IllegalArgumentException("步骤 " + step.key()
                            + " 依赖未选择的前置产物: " + resource.artifactKey());
                }
            }
            step.outputs().forEach(output -> produced.add(output.key()));
        }
    }

    static Path discoverProjectRoot(Path start) {
        Path current = start.toAbsolutePath().normalize();
        while (current != null) {
            if (Files.isDirectory(current.resolve("scripts/steps"))) return current;
            current = current.getParent();
        }
        throw new IllegalStateException("无法定位包含 scripts/steps 的 KubeFoundry 项目目录");
    }
}
