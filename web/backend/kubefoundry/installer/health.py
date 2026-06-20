from kubefoundry.installer.ssh import run_ssh


KUBECTL_NODES_COMMAND = (
    "KUBECONFIG=/etc/kubernetes/admin.conf "
    "kubectl get nodes --no-headers"
)
KUBECTL_PODS_COMMAND = (
    "KUBECONFIG=/etc/kubernetes/admin.conf "
    "kubectl get pods -A --no-headers"
)


def evaluate_cluster_health(
    expected_nodes,
    ready_nodes,
    not_ready_nodes,
    failed_pods,
    flannel_ready,
):
    expected = set(expected_nodes)
    observed = set(ready_nodes) | set(not_ready_nodes)
    missing = sorted(expected - observed)
    problems = []
    if not_ready_nodes:
        problems.append(
            "NotReady nodes: %s" % ", ".join(sorted(not_ready_nodes))
        )
    if missing:
        problems.append("missing nodes: %s" % ", ".join(missing))
    if failed_pods:
        problems.append(
            "failed pods: %s" % ", ".join(sorted(failed_pods))
        )
    if flannel_ready < len(expected_nodes):
        problems.append(
            "flannel ready %s/%s"
            % (flannel_ready, len(expected_nodes))
        )
    return {
        "ok": not problems,
        "message": (
            "; ".join(problems)
            if problems
            else "cluster health check passed"
        ),
    }


def check_cluster_health(node, context):
    node_code, node_output, node_error = run_ssh(
        node,
        context,
        KUBECTL_NODES_COMMAND,
        timeout=120,
    )
    if node_code != 0:
        return node_code, node_output, node_error

    pod_code, pod_output, pod_error = run_ssh(
        node,
        context,
        KUBECTL_PODS_COMMAND,
        timeout=120,
    )
    if pod_code != 0:
        return pod_code, node_output, pod_error

    ready_nodes, not_ready_nodes = _parse_nodes(node_output)
    failed_pods, flannel_ready = _parse_pods(pod_output)
    expected_nodes = [
        item.get("hostname")
        for item in (
            (context.get("control_plane") or [])
            + (context.get("workers") or [])
        )
        if item.get("hostname")
    ]
    result = evaluate_cluster_health(
        expected_nodes,
        ready_nodes,
        not_ready_nodes,
        failed_pods,
        flannel_ready,
    )
    output = "\n".join([
        "=== kubectl get nodes ===",
        (node_output or "").rstrip(),
        "=== kubectl get pods -A ===",
        (pod_output or "").rstrip(),
        "=== health result ===",
        result["message"],
        "",
    ])
    return (0 if result["ok"] else 1), output, ""


def _parse_nodes(output):
    ready = []
    not_ready = []
    for line in (output or "").splitlines():
        fields = line.split()
        if len(fields) < 2:
            continue
        hostname = fields[0]
        status = fields[1]
        if status == "Ready":
            ready.append(hostname)
        else:
            not_ready.append(hostname)
    return ready, not_ready


def _parse_pods(output):
    failed = []
    flannel_ready = 0
    for line in (output or "").splitlines():
        fields = line.split()
        if len(fields) < 4:
            continue
        namespace, name, ready, status = fields[:4]
        if status not in ("Running", "Completed", "Succeeded"):
            failed.append("%s/%s:%s" % (namespace, name, status))
        if (
            namespace == "kube-flannel"
            and status == "Running"
            and _ready_count_matches(ready)
        ):
            flannel_ready += 1
    return failed, flannel_ready


def _ready_count_matches(value):
    try:
        ready, total = value.split("/", 1)
        return int(total) > 0 and int(ready) == int(total)
    except (AttributeError, TypeError, ValueError):
        return False
