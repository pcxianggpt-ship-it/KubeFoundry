import os

from kubefoundry.store.db import project_root


def script_path(relative):
    return os.path.join(project_root(), relative.replace("/", os.sep))


STEP_PLAN = [
    {
        "key": "13-install-k8s-deps",
        "name": "安装 Kubernetes 依赖",
        "phase": "k8s_base",
        "target_scope": "all_k8s_nodes",
        "script": script_path("scripts/steps/phase2_k8s_base/13-install-k8s-deps.sh"),
        "mode": "parallel",
        "max_workers": 5,
        "fail_fast": False,
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
    },
]


def selected_plan(selected_steps=None):
    if not selected_steps:
        return list(STEP_PLAN)
    selected = set(selected_steps)
    return [step for step in STEP_PLAN if step["key"] in selected]


def resolve_targets(step, context):
    scope = step.get("target_scope")
    nodes = context.get("nodes") or []
    if scope in ("all_nodes", "all_k8s_nodes"):
        return nodes
    if scope == "control_plane":
        return context.get("control_plane") or []
    if scope == "workers":
        return context.get("workers") or []
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
