import ipaddress


def validate_cluster_context(context, require_worker=False, require_registry_node=False):
    errors = []
    cluster = context.get("cluster") or {}
    nodes = context.get("nodes") or []
    control_planes = context.get("control_plane") or []
    workers = context.get("workers") or []

    if not control_planes:
        errors.append("at least one control_plane node is required")
    if require_worker and not workers:
        errors.append("at least one worker node is required")

    _validate_unique(nodes, "ip", "node IP", errors)
    _validate_unique(nodes, "hostname", "node hostname", errors)
    _validate_networks(cluster, errors)

    registry = context.get("registry") or {}
    if not registry.get("ip"):
        errors.append("registry IP is required")
    elif require_registry_node and registry.get("ip") not in set(node.get("ip") for node in nodes):
        errors.append("registry IP must match a configured node")

    if errors:
        raise ValueError("; ".join(errors))
    return True


def _validate_unique(nodes, field, label, errors):
    seen = {}
    for node in nodes:
        value = (node.get(field) or "").strip()
        if not value:
            errors.append("%s is required for every node" % label)
            continue
        if value in seen:
            errors.append("duplicate %s: %s" % (label, value))
        seen[value] = True


def _validate_networks(cluster, errors):
    pod_subnet = cluster.get("pod_subnet")
    service_subnet = cluster.get("service_subnet")
    try:
        pod_network = ipaddress.ip_network(str(pod_subnet), strict=False)
    except ValueError:
        errors.append("invalid Pod CIDR: %s" % pod_subnet)
        pod_network = None
    try:
        service_network = ipaddress.ip_network(str(service_subnet), strict=False)
    except ValueError:
        errors.append("invalid Service CIDR: %s" % service_subnet)
        service_network = None
    if pod_network and service_network:
        if pod_network.version != service_network.version:
            return
        if pod_network.overlaps(service_network):
            errors.append("Pod CIDR and Service CIDR must not overlap")
