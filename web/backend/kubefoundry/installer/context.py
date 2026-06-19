import json
import os
import re

try:
    import yaml
except ImportError:
    yaml = None

from kubefoundry.store.db import data_dir
from kubefoundry.store.repository import Repository


def _expand_vars(value, variables):
    if not isinstance(value, str):
        return value

    def repl(match):
        key = match.group(1)
        return str(variables.get(key, match.group(0)))

    return re.sub(r"\$\{([^}]+)\}", repl, value)


def build_cluster_context(cluster_id):
    repo = Repository()
    cluster = repo.get_cluster(cluster_id)
    if not cluster:
        raise ValueError("cluster not found")
    nodes = repo.list_nodes(cluster_id)
    ssh = repo.get_ssh_credentials(cluster_id) or {
        "auth_type": "key",
        "username": "root",
        "private_key_path": "~/.ssh/id_rsa",
    }
    settings = repo.get_settings()
    cluster_settings = repo.get_cluster_settings(cluster_id)

    control_planes = [n for n in nodes if n.get("role") == "control_plane"]
    workers = [n for n in nodes if n.get("role") == "worker"]
    registry_nodes = [n for n in nodes if n.get("role") == "registry"]
    registry = {
        "hostname": cluster.get("registry_hostname") or "registry",
        "ip": cluster.get("registry_ip") or (registry_nodes[0]["ip"] if registry_nodes else (control_planes[0]["ip"] if control_planes else "")),
        "port": cluster.get("registry_port") or 5000,
    }
    path_settings = cluster_settings.get("paths") or settings.get("paths") or {}
    ecosystem = cluster_settings.get("ecosystem") or settings.get("ecosystem") or {}
    advanced = cluster_settings.get("advanced") or settings.get("advanced") or {}
    paths = {
        "k8s_home": "/data/k8s_install",
        "install_media": "/root/kube-media",
        "arch": "amd64",
        "repo_source": "${install_media}/01.rpm_package/k8srepo_kylinos_sp3_${arch}.tar.gz",
        "kubeadm_100y": "${install_media}/01.rpm_package/kubeadm-${k8s_version}-100y-${arch}",
        "container_runtime": "${install_media}/02.container_runtime",
        "registry_install": "${install_media}/04.registry",
        "flannel_config": "${install_media}/03.setup_file/kube-flannel.yml",
    }
    paths.update(dict((k, v) for k, v in path_settings.items() if v not in (None, "")))
    env = {
        "kubelet_root": "${k8s_home}/kubelet_root",
        "containerd_root": "${k8s_home}/containerd-data",
        "etcd_data_dir": "${k8s_home}/etcd_backup",
    }
    if path_settings.get("kubelet_root"):
        env["kubelet_root"] = path_settings.get("kubelet_root")
    if path_settings.get("etcd_data_dir"):
        env["etcd_data_dir"] = path_settings.get("etcd_data_dir")
    variables = dict(paths)
    variables["k8s_version"] = cluster.get("k8s_version")
    for key in list(paths.keys()):
        paths[key] = _expand_vars(paths[key], variables)
        variables[key] = paths[key]
    env = dict((k, _expand_vars(v, variables)) for k, v in env.items())
    return {
        "cluster": cluster,
        "nodes": nodes,
        "control_plane": control_planes,
        "workers": workers,
        "registry_nodes": registry_nodes,
        "registry": registry,
        "network": {
            "api_server_port": cluster.get("api_server_port") or 6443,
        },
        "ssh": ssh,
        "paths": paths,
        "env": env,
        "storage": {},
        "advanced": advanced,
        "ecosystem": ecosystem,
    }


def context_to_yaml_data(context):
    cluster = context["cluster"]
    return {
        "cluster": {
            "name": cluster.get("name"),
            "k8s_version": cluster.get("k8s_version"),
            "pod_subnet": cluster.get("pod_subnet"),
            "service_subnet": cluster.get("service_subnet"),
        },
        "control_plane": [
            {"hostname": n.get("hostname"), "ip": n.get("ip"), "ipv6": n.get("ipv6") or ""}
            for n in context["control_plane"]
        ],
        "workers": [
            {"hostname": n.get("hostname"), "ip": n.get("ip"), "ipv6": n.get("ipv6") or ""}
            for n in context["workers"]
        ],
        "registry": context["registry"],
        "network": context["network"],
        "ssh": {
            "user": context["ssh"].get("username") or "root",
            "port": _first_node_ssh_port(context["nodes"]),
            "key_path": context["ssh"].get("private_key_path") or "~/.ssh/id_rsa",
            "timeout": 30,
            "control_persist": 300,
        },
        "paths": context["paths"],
        "env": context["env"],
        "ecosystem": context["ecosystem"],
    }


def export_cluster_yaml(cluster_id, path=None):
    context = build_cluster_context(cluster_id)
    if not path:
        path = os.path.join(data_dir(), "clusters", str(cluster_id), "cluster.yaml")
    parent = os.path.dirname(path)
    if parent and not os.path.exists(parent):
        os.makedirs(parent)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        _dump_yaml(context_to_yaml_data(context), fh)
    return path


def write_job_snapshot(cluster_id, job_id):
    context = build_cluster_context(cluster_id)
    job_dir = os.path.join(data_dir(), "jobs", str(job_id))
    if not os.path.exists(job_dir):
        os.makedirs(job_dir)
    snapshot_path = os.path.join(job_dir, "config_snapshot.json")
    yaml_path = os.path.join(job_dir, "cluster.yaml")
    with open(snapshot_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(context, fh, ensure_ascii=False, indent=2)
    with open(yaml_path, "w", encoding="utf-8", newline="\n") as fh:
        _dump_yaml(context_to_yaml_data(context), fh)
    return context, snapshot_path, yaml_path


def import_cluster_yaml(cluster_id, yaml_path=None, yaml_text=None):
    if yaml_text is None:
        if not yaml_path:
            raise ValueError("path or content is required")
        with open(yaml_path, "r", encoding="utf-8") as fh:
            yaml_text = fh.read()
    data = _load_yaml(yaml_text) or {}
    repo = Repository()
    cluster_data = data.get("cluster") or {}
    registry = data.get("registry") or {}
    network = data.get("network") or {}
    repo.update_cluster(cluster_id, {
        "name": cluster_data.get("name"),
        "k8s_version": cluster_data.get("k8s_version"),
        "pod_subnet": cluster_data.get("pod_subnet"),
        "service_subnet": cluster_data.get("service_subnet"),
        "api_server_port": network.get("api_server_port"),
        "registry_hostname": registry.get("hostname"),
        "registry_ip": registry.get("ip"),
        "registry_port": registry.get("port"),
    })

    for node in repo.list_nodes(cluster_id):
        repo.delete_node(node["id"])
    for item in data.get("control_plane") or []:
        item = dict(item)
        item["role"] = "control_plane"
        repo.create_node(cluster_id, item)
    for item in data.get("workers") or []:
        item = dict(item)
        item["role"] = "worker"
        repo.create_node(cluster_id, item)

    ssh = data.get("ssh") or {}
    repo.upsert_ssh_credentials(cluster_id, {
        "username": ssh.get("user") or ssh.get("username") or "root",
        "private_key_path": ssh.get("key_path") or ssh.get("private_key_path") or "~/.ssh/id_rsa",
        "auth_type": "key",
    })
    return build_cluster_context(cluster_id)


def _dump_yaml(data, fh):
    if yaml is not None:
        yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
        return
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")


def _load_yaml(text):
    if yaml is not None:
        return yaml.safe_load(text)
    try:
        return json.loads(text)
    except ValueError:
        raise RuntimeError("PyYAML is required to import YAML content")


def _first_node_ssh_port(nodes):
    if nodes:
        return nodes[0].get("ssh_port") or 22
    return 22
