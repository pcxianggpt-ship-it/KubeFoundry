import yaml


def build_cluster_context(cluster):
    nodes = cluster.get("nodes") or []
    control_plane = []
    workers = []
    registry_nodes = []

    for node in nodes:
        item = {
            "hostname": node.get("hostname", ""),
            "ip": node.get("ip", ""),
        }
        if node.get("ipv6"):
            item["ipv6"] = node.get("ipv6")
        if node.get("role") == "control_plane":
            control_plane.append(item)
        elif node.get("role") == "worker":
            workers.append(item)
        elif node.get("role") == "registry":
            registry_nodes.append(item)

    ssh = cluster.get("ssh") or {}
    registry_ip = cluster.get("registry_ip") or ""
    if not registry_ip and registry_nodes:
        registry_ip = registry_nodes[0].get("ip", "")

    return {
        "cluster": {
            "name": cluster.get("name", ""),
            "k8s_version": cluster.get("k8s_version", ""),
            "pod_subnet": cluster.get("pod_subnet", ""),
            "service_subnet": cluster.get("service_subnet", ""),
        },
        "control_plane": control_plane,
        "workers": workers,
        "registry": {
            "hostname": cluster.get("registry_hostname", "registry"),
            "ip": registry_ip,
            "port": cluster.get("registry_port", 5000),
        },
        "ssh": {
            "user": ssh.get("username") or "root",
            "port": _first_node_ssh_port(nodes),
            "key_path": ssh.get("private_key_path") or "~/.ssh/id_rsa",
        },
    }


def dump_cluster_yaml(cluster):
    context = build_cluster_context(cluster)
    return yaml.safe_dump(context, allow_unicode=True, sort_keys=False)


def _first_node_ssh_port(nodes):
    if nodes:
        return nodes[0].get("ssh_port") or 22
    return 22
