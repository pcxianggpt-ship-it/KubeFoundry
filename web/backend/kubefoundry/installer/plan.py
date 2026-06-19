import os

from kubefoundry.store.db import project_root


def script_path(relative):
    return os.path.join(project_root(), relative.replace("/", os.sep))


STEP_PLAN = [
    {
        "key": "10-setup-yum-source",
        "name": "配置 Kubernetes YUM 源",
        "phase": "k8s_base",
        "target_scope": "primary_control_plane",
        "script": script_path("scripts/steps/phase2_k8s_base/10-setup-yum-source.sh"),
        "mode": "serial",
        "fail_fast": True,
        "resources": [
            {
                "path_key": "repo_source",
                "kind": "file",
                "remote_path": "/tmp/k8s/k8s-repo-source.tar.gz",
            }
        ],
        "args": [{"literal": "/tmp/k8s/k8s-repo-source.tar.gz"}],
        "verify_command": "systemctl is-active httpd >/dev/null && yum -q repolist | grep -q k8s",
    },
    {
        "key": "11b-setup-hostname",
        "name": "配置主机名和 hosts",
        "phase": "k8s_base",
        "target_scope": "all_nodes",
        "builtin": "setup_hostname",
        "mode": "parallel",
        "max_workers": 5,
        "fail_fast": False,
        "resources": [],
        "verify_command": "test \"$(hostname)\" = {node_hostname} && grep -q '^# >>>KubeFoundry>>>$' /etc/hosts",
    },
    {
        "key": "12-setup-k8s-repo",
        "name": "配置 Kubernetes HTTP Repo",
        "phase": "k8s_base",
        "target_scope": "non_primary_k8s_nodes",
        "script": script_path("scripts/steps/phase2_k8s_base/12-setup-k8s-repo.sh"),
        "mode": "parallel",
        "max_workers": 5,
        "fail_fast": False,
        "resources": [],
        "verify_command": "test -f /etc/yum.repos.d/k8s-http.repo && yum -q repolist | grep -q k8s-repo",
    },
    {
        "key": "13-install-k8s-deps",
        "name": "安装 Kubernetes 依赖",
        "phase": "k8s_base",
        "target_scope": "all_k8s_nodes",
        "script": script_path("scripts/steps/phase2_k8s_base/13-install-k8s-deps.sh"),
        "mode": "parallel",
        "max_workers": 5,
        "fail_fast": False,
        "resources": [],
        "verify_command": "command -v kubeadm >/dev/null && command -v kubelet >/dev/null && systemctl is-enabled kubelet >/dev/null",
    },
    {
        "key": "14-replace-kubeadm",
        "name": "替换长期证书 kubeadm",
        "phase": "k8s_base",
        "target_scope": "primary_control_plane",
        "script": script_path("scripts/steps/phase2_k8s_base/14-replace-kubeadm.sh"),
        "mode": "serial",
        "fail_fast": True,
        "resources": [
            {
                "path_key": "kubeadm_100y",
                "kind": "file",
                "remote_path": "/tmp/k8s/kubeadm-100y",
            }
        ],
        "verify_command": "test -x /usr/bin/kubeadm && test -f /tmp/k8s/kubeadm_bak",
    },
    {
        "key": "15-environment-config",
        "name": "环境配置",
        "phase": "k8s_base",
        "target_scope": "all_nodes",
        "script": script_path("scripts/steps/phase2_k8s_base/15-environment-config.sh"),
        "mode": "parallel",
        "max_workers": 5,
        "fail_fast": False,
        "resources": [],
        "verify_command": "test -z \"$(swapon --show --noheadings)\" && test \"$(sysctl -n net.ipv4.ip_forward)\" = 1",
    },
    {
        "key": "16-install-containerd",
        "name": "安装 containerd",
        "phase": "k8s_base",
        "target_scope": "all_nodes",
        "script": script_path("scripts/steps/phase2_k8s_base/16-install-containerd.sh"),
        "mode": "parallel",
        "max_workers": 5,
        "fail_fast": False,
        "resources": [
            {
                "path_key": "container_runtime",
                "kind": "directory",
                "remote_path": "/tmp/k8s/02.container_runtime",
            }
        ],
        "verify_command": "systemctl is-active containerd >/dev/null && command -v runc >/dev/null && command -v nerdctl >/dev/null",
    },
    {
        "key": "17-install-registry",
        "name": "安装镜像仓库",
        "phase": "k8s_base",
        "target_scope": "registry",
        "script": script_path("scripts/steps/phase2_k8s_base/17-install-registry.sh"),
        "mode": "serial",
        "fail_fast": True,
        "resources": [
            {
                "path_key": "registry_install",
                "kind": "directory",
                "remote_path": "{k8s_home}/04.registry",
            }
        ],
        "verify_command": "(nerdctl ps 2>/dev/null || docker ps 2>/dev/null) | grep -q registry",
    },
    {
        "key": "18-init-k8s-cluster",
        "name": "初始化 Kubernetes 集群",
        "phase": "k8s_base",
        "target_scope": "primary_control_plane",
        "script": script_path("scripts/steps/phase2_k8s_base/18-init-k8s-cluster.sh"),
        "mode": "serial",
        "fail_fast": True,
        "resources": [],
        "outputs": [
            {"key": "control_join", "remote_path": "/tmp/k8s/kube_join_master"},
            {"key": "worker_join", "remote_path": "/tmp/k8s/kube_join_nodes"},
        ],
        "verify_command": "test -f /etc/kubernetes/admin.conf && KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes >/dev/null",
    },
    {
        "key": "19-modify-cert-expiry",
        "name": "修改证书有效期",
        "phase": "k8s_base",
        "target_scope": "primary_control_plane",
        "script": script_path("scripts/steps/phase2_k8s_base/19-modify-cert-expiry.sh"),
        "mode": "serial",
        "fail_fast": True,
        "resources": [],
        "verify_command": "grep -q cluster-signing-duration /etc/kubernetes/manifests/kube-controller-manager.yaml",
    },
    {
        "key": "20-add-control-nodes",
        "name": "加入其他控制节点",
        "phase": "k8s_base",
        "target_scope": "other_control_planes",
        "script": script_path("scripts/steps/phase2_k8s_base/20-add-control-nodes.sh"),
        "mode": "serial",
        "fail_fast": True,
        "resources": [
            {
                "artifact_key": "control_join",
                "kind": "file",
                "remote_path": "/tmp/k8s/kube_join_master",
            }
        ],
        "args": [{"context": "primary_control_ip"}],
        "verify_command": "systemctl is-active kubelet >/dev/null && test -f /etc/kubernetes/kubelet.conf",
    },
    {
        "key": "21-add-worker-nodes",
        "name": "加入工作节点",
        "phase": "k8s_base",
        "target_scope": "workers",
        "script": script_path("scripts/steps/phase2_k8s_base/21-add-worker-nodes.sh"),
        "mode": "parallel",
        "max_workers": 5,
        "fail_fast": False,
        "resources": [
            {
                "artifact_key": "worker_join",
                "kind": "file",
                "remote_path": "/tmp/k8s/kube_join_nodes",
            }
        ],
        "verify_command": "systemctl is-active kubelet >/dev/null && test -f /etc/kubernetes/kubelet.conf",
    },
    {
        "key": "22-install-cni-flannel",
        "name": "安装 Flannel CNI",
        "phase": "k8s_base",
        "target_scope": "primary_control_plane",
        "script": script_path("scripts/steps/phase2_k8s_base/22-install-cni-flannel.sh"),
        "mode": "serial",
        "fail_fast": True,
        "resources": [
            {
                "path_key": "flannel_config",
                "kind": "file",
                "remote_path": "/tmp/k8s/kube-flannel.yml",
            }
        ],
        "verify_command": "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A | grep -q flannel",
    },
]


def selected_plan(selected_steps=None):
    if not selected_steps:
        return list(STEP_PLAN)
    selected = set(selected_steps)
    return [step for step in STEP_PLAN if step["key"] in selected]


def validate_selected_plan(selected_steps=None):
    if selected_steps:
        known = set(step["key"] for step in STEP_PLAN)
        unknown = sorted(set(selected_steps) - known)
        if unknown:
            raise ValueError("unknown installation steps: %s" % ", ".join(unknown))
    plan = selected_plan(selected_steps)
    if selected_steps and not plan:
        raise ValueError("no valid installation steps selected")
    _validate_artifact_dependencies(plan)
    return plan


def validate_step_resources(plan, context):
    errors = []
    paths = context.get("paths") or {}
    for step in plan:
        for resource in step.get("resources") or []:
            path_key = resource.get("path_key")
            if resource.get("artifact_key"):
                continue
            source = paths.get(path_key)
            if not source:
                errors.append("%s: path setting %s is empty" % (step["key"], path_key))
                continue
            kind = resource.get("kind", "file")
            exists = os.path.isdir(source) if kind == "directory" else os.path.isfile(source)
            if not exists:
                errors.append("%s: %s does not exist: %s" % (step["key"], kind, source))
    if errors:
        raise ValueError("; ".join(errors))
    return True


def _validate_artifact_dependencies(plan):
    produced = set()
    for step in plan:
        for resource in step.get("resources") or []:
            artifact_key = resource.get("artifact_key")
            if artifact_key and artifact_key not in produced:
                raise ValueError(
                    "step %s requires output from an earlier selected step: %s"
                    % (step["key"], artifact_key)
                )
        for output in step.get("outputs") or []:
            produced.add(output.get("key"))


def resolve_targets(step, context):
    scope = step.get("target_scope")
    nodes = context.get("nodes") or []
    if scope == "all_nodes":
        return _unique_nodes(nodes)
    if scope == "all_k8s_nodes":
        return _unique_nodes((context.get("control_plane") or []) + (context.get("workers") or []))
    if scope == "control_plane":
        return context.get("control_plane") or []
    if scope == "workers":
        return context.get("workers") or []
    if scope == "non_primary_k8s_nodes":
        primary = (context.get("control_plane") or [])[:1]
        primary_ids = set(item.get("id") for item in primary)
        k8s_nodes = (context.get("control_plane") or []) + (context.get("workers") or [])
        return _unique_nodes([node for node in k8s_nodes if node.get("id") not in primary_ids])
    if scope == "registry":
        registry_ip = (context.get("registry") or {}).get("ip")
        return [n for n in nodes if n.get("ip") == registry_ip or n.get("role") == "registry"]
    if scope == "primary_control_plane":
        cps = context.get("control_plane") or []
        return cps[:1]
    if scope == "other_control_planes":
        cps = context.get("control_plane") or []
        return cps[1:]
    return []


def _unique_nodes(nodes):
    result = []
    seen = set()
    for node in nodes:
        identity = node.get("ip") or node.get("id")
        if identity in seen:
            continue
        seen.add(identity)
        result.append(node)
    return result
