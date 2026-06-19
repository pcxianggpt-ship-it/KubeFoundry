import os
import shlex


def _q(value):
    return shlex.quote("" if value is None else str(value))


def render_runtime_env(context, node):
    cluster = context["cluster"]
    registry = context["registry"]
    paths = context["paths"]
    env = context["env"]
    values = {
        "KF_CLUSTER_NAME": cluster.get("name"),
        "KF_K8S_VERSION": cluster.get("k8s_version"),
        "KF_POD_SUBNET": cluster.get("pod_subnet"),
        "KF_SERVICE_SUBNET": cluster.get("service_subnet"),
        "KF_API_SERVER_PORT": cluster.get("api_server_port"),
        "KF_NODE_HOSTNAME": node.get("hostname"),
        "KF_NODE_IP": node.get("ip"),
        "KF_NODE_ROLE": node.get("role"),
        "KF_REGISTRY_HOSTNAME": registry.get("hostname"),
        "KF_REGISTRY_IP": registry.get("ip"),
        "KF_REGISTRY_PORT": registry.get("port"),
        "KF_K8S_HOME": paths.get("k8s_home"),
        "KF_INSTALL_MEDIA": paths.get("install_media"),
        "KF_ARCH": node.get("arch") or paths.get("arch"),
        "KF_KUBELET_ROOT": env.get("kubelet_root"),
        "KF_CONTAINERD_ROOT": env.get("containerd_root"),
        "KF_ETCD_DATA_DIR": env.get("etcd_data_dir"),
    }
    compat = {
        "K8S_VERSION": "${KF_K8S_VERSION}",
        "POD_SUBNET": "${KF_POD_SUBNET}",
        "SERVICE_SUBNET": "${KF_SERVICE_SUBNET}",
        "API_SERVER_PORT": "${KF_API_SERVER_PORT}",
        "REGISTRY_IP": "${KF_REGISTRY_IP}",
        "REGISTRY_HOSTNAME": "${KF_REGISTRY_HOSTNAME}",
        "REGISTRY_PORT": "${KF_REGISTRY_PORT}",
        "K8S_HOME": "${KF_K8S_HOME}",
        "K8S_SOFT": "${KF_K8S_HOME}",
        "INSTALL_MEDIA": "${KF_INSTALL_MEDIA}",
        "ARCH": "${KF_ARCH}",
        "KUBELET_ROOT": "${KF_KUBELET_ROOT}",
        "CONTAINERD_ROOT": "${KF_CONTAINERD_ROOT}",
        "ETCD_DATA_DIR": "${KF_ETCD_DATA_DIR}",
    }
    lines = ["#!/bin/bash", ""]
    for key in sorted(values.keys()):
        lines.append("export %s=%s" % (key, _q(values[key])))
    for key in sorted(compat.keys()):
        lines.append("export %s=\"%s\"" % (key, compat[key]))
    lines.append("")
    return "\n".join(lines)


def write_runtime_env(path, context, node):
    parent = os.path.dirname(path)
    if parent and not os.path.exists(parent):
        os.makedirs(parent)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(render_runtime_env(context, node))
    return path
