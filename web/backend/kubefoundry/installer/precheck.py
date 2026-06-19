import os
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

from kubefoundry.installer.context import build_cluster_context, write_job_snapshot
from kubefoundry.installer.events import append_log, emit
from kubefoundry.installer.ssh import run_ssh
from kubefoundry.store.db import data_dir
from kubefoundry.store.repository import Repository


CHECK_COMMAND = r"""
set -o pipefail
echo "__KF__USER=$(id -u)"
echo "__KF__OS=$(cat /etc/os-release 2>/dev/null | head -n 1 || uname -a)"
echo "__KF__CPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 0)"
echo "__KF__MEM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
echo "__KF__DISK=$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)"
echo "__KF__SWAP=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
echo "__KF__HOSTNAME=$(hostname 2>/dev/null || echo unknown)"
for p in 6443 2379 2380 10250 10257 10259; do
  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}$" && echo "__KF__PORT_${p}=used" || echo "__KF__PORT_${p}=free"
  else
    netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}$" && echo "__KF__PORT_${p}=used" || echo "__KF__PORT_${p}=free"
  fi
done
"""


def start_precheck_job(cluster_id):
    context = build_cluster_context(cluster_id)
    job_dir = os.path.join(data_dir(), "jobs", "pending")
    repo = Repository()
    job = repo.create_job(cluster_id, "precheck", context, "", job_dir)
    context, snapshot_path, yaml_path = write_job_snapshot(cluster_id, job["id"])
    job_dir = os.path.join(data_dir(), "jobs", str(job["id"]))
    log_dir = os.path.join(job_dir, "logs")
    repo.update_job(job["id"], log_dir=log_dir, config_snapshot=_read(snapshot_path), config_yaml_path=yaml_path)
    thread = threading.Thread(target=run_precheck_job, args=(job["id"], cluster_id), daemon=True)
    thread.start()
    return repo.get_job(job["id"])


def run_precheck_job(job_id, cluster_id):
    try:
        _run_precheck_job(job_id, cluster_id)
    except Exception as exc:
        _fail_job(job_id, exc)


def _run_precheck_job(job_id, cluster_id):
    repo = Repository()
    context = build_cluster_context(cluster_id)
    log_dir = os.path.join(data_dir(), "jobs", str(job_id), "logs")
    repo.update_job(job_id, status="running", started_at=_now())
    emit(job_id, "job.status", {"status": "running"})
    append_log(job_id, log_dir, "预检查任务启动")
    step = repo.create_job_step(job_id, {
        "key": "web-precheck-node-env",
        "name": "节点环境预检查",
        "phase": "precheck",
        "target_scope": "all_nodes",
    })
    repo.update_job_step(step["id"], status="running", started_at=_now())
    emit(job_id, "step.status", {"step_key": step["step_key"], "status": "running"})

    nodes = context.get("nodes") or []
    failed = False
    max_workers = min(5, max(1, len(nodes)))
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(_check_node, job_id, cluster_id, step["id"], context, node, log_dir) for node in nodes]
        for future in as_completed(futures):
            ok = future.result()
            if not ok:
                failed = True

    status = "failed" if failed else "success"
    repo.update_job_step(step["id"], status=status, finished_at=_now(), exit_code=1 if failed else 0)
    repo.update_job(job_id, status=status, finished_at=_now(), current_step_key=step["step_key"])
    append_log(job_id, log_dir, "预检查任务完成，状态: %s" % status, "job.status", {"status": status})


def _fail_job(job_id, exc):
    repo = Repository()
    log_dir = os.path.join(data_dir(), "jobs", str(job_id), "logs")
    message = "预检查任务异常: %s" % exc
    repo.update_job(job_id, status="failed", finished_at=_now())
    append_log(job_id, log_dir, message, "job.status", {"status": "failed"})


def _check_node(job_id, cluster_id, step_id, context, node, log_dir):
    repo = Repository()
    node_log_dir = os.path.join(log_dir, "web-precheck-node-env")
    if not os.path.exists(node_log_dir):
        os.makedirs(node_log_dir)
    node_log_path = os.path.join(node_log_dir, "%s.log" % node["hostname"])
    item = repo.create_job_step_node(step_id, node["id"], node_log_path)
    repo.update_job_step_node(item["id"], status="running", started_at=_now())
    emit(job_id, "node.status", {"node_id": node["id"], "hostname": node["hostname"], "status": "running"})
    code, out, err = run_ssh(node, context, CHECK_COMMAND, timeout=60)
    with open(node_log_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(out or "")
        fh.write(err or "")
    if code != 0:
        repo.add_precheck_result(cluster_id, job_id, node["id"], "ssh", "SSH 连通性", "error", "fail", "SSH 连接失败", err or out)
        repo.update_job_step_node(item["id"], status="failed", finished_at=_now(), exit_code=code, message="SSH 连接失败")
        emit(job_id, "precheck.result", {"node_id": node["id"], "check_key": "ssh", "status": "fail"})
        return False

    values = _parse(out)
    results = _build_results(values)
    ok = True
    for result in results:
        repo.add_precheck_result(cluster_id, job_id, node["id"], *result)
        emit(job_id, "precheck.result", {
            "node_id": node["id"],
            "hostname": node["hostname"],
            "check_key": result[0],
            "status": result[3],
            "message": result[4],
        })
        if result[3] == "fail":
            ok = False
    repo.update_job_step_node(item["id"], status="success" if ok else "failed", finished_at=_now(), exit_code=0 if ok else 1)
    emit(job_id, "node.status", {"node_id": node["id"], "hostname": node["hostname"], "status": "success" if ok else "failed"})
    return ok


def _parse(text):
    result = {}
    for line in (text or "").splitlines():
        if line.startswith("__KF__") and "=" in line:
            key, value = line.split("=", 1)
            result[key.replace("__KF__", "")] = value.strip()
    return result


def _build_results(values):
    results = []
    results.append(("ssh", "SSH 连通性", "error", "pass", "SSH 连接成功", ""))
    user_status = "pass" if values.get("USER") == "0" else "warning"
    results.append(("user", "用户权限", "warning", user_status, "root 用户" if user_status == "pass" else "非 root 用户", values.get("USER", "")))
    results.append(("os", "操作系统版本", "info", "pass", values.get("OS", "unknown"), values.get("OS", "")))
    cpu = _int(values.get("CPU"))
    results.append(("cpu", "CPU", "error", "pass" if cpu >= 2 else "fail", "CPU 核数: %s" % cpu, "建议至少 2 核"))
    mem = _int(values.get("MEM"))
    results.append(("memory", "内存", "error", "pass" if mem >= 2048 else "fail", "内存: %s MB" % mem, "建议至少 2048 MB"))
    disk = _int(values.get("DISK"))
    results.append(("disk", "磁盘", "warning", "pass" if disk >= 10240 else "warning", "根分区可用: %s MB" % disk, "建议至少 10240 MB"))
    swap = _int(values.get("SWAP"))
    results.append(("swap", "Swap", "warning", "pass" if swap == 0 else "warning", "Swap: %s MB" % swap, "Kubernetes 建议关闭 swap"))
    results.append(("hostname", "Hostname", "info", "pass", values.get("HOSTNAME", "unknown"), ""))
    used = []
    for port in ["6443", "2379", "2380", "10250", "10257", "10259"]:
        if values.get("PORT_%s" % port) == "used":
            used.append(port)
    results.append(("ports", "关键端口", "error", "fail" if used else "pass", "端口占用: %s" % ",".join(used) if used else "关键端口未占用", ""))
    return results


def _int(value):
    try:
        return int(value)
    except Exception:
        return 0


def _now():
    import datetime
    return datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")


def _read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()
