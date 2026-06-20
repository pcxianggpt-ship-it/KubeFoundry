import os
import shutil
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

from kubefoundry.installer.context import build_cluster_context, write_job_snapshot
from kubefoundry.installer.events import append_log, emit
from kubefoundry.installer.health import check_cluster_health
from kubefoundry.installer.plan import (
    resolve_targets,
    validate_selected_plan,
    validate_step_resources,
)
from kubefoundry.installer.runtime import write_runtime_env
from kubefoundry.installer.ssh import copy_path_to_node, run_ssh, scp_to_node, shell_quote
from kubefoundry.installer.validator import validate_cluster_context
from kubefoundry.store.db import data_dir
from kubefoundry.store.repository import Repository


def start_install_job(cluster_id, selected_steps=None):
    context = build_cluster_context(cluster_id)
    validate_cluster_context(context, require_worker=True, require_registry_node=True)
    plan = validate_selected_plan(selected_steps)
    validate_step_resources(plan, context)
    job_dir = os.path.join(data_dir(), "jobs", "pending")
    repo = Repository()
    job = repo.create_job(cluster_id, "install", context, "", job_dir)
    context, snapshot_path, yaml_path = write_job_snapshot(cluster_id, job["id"])
    log_dir = os.path.join(data_dir(), "jobs", str(job["id"]), "logs")
    repo.update_job(job["id"], config_snapshot=_read(snapshot_path), config_yaml_path=yaml_path, log_dir=log_dir)
    thread = threading.Thread(target=run_install_job, args=(job["id"], context, plan), daemon=True)
    thread.start()
    return repo.get_job(job["id"])


def run_install_job(job_id, context, plan):
    try:
        _run_install_job(job_id, context, plan)
    except Exception as exc:
        _fail_job(job_id, exc)


def _run_install_job(job_id, context, plan):
    repo = Repository()
    log_dir = os.path.join(data_dir(), "jobs", str(job_id), "logs")
    repo.update_job(job_id, status="running", started_at=_now())
    append_log(job_id, log_dir, "安装任务启动", "job.status", {"status": "running"})
    failed = False
    artifacts = {}
    for step in plan:
        repo.update_job(job_id, current_step_key=step["key"])
        if not _run_step(job_id, context, step, log_dir, artifacts):
            failed = True
            break
    status = "failed" if failed else "success"
    repo.update_job(job_id, status=status, finished_at=_now())
    append_log(job_id, log_dir, "安装任务完成，状态: %s" % status, "job.status", {"status": status})


def _fail_job(job_id, exc):
    repo = Repository()
    log_dir = os.path.join(data_dir(), "jobs", str(job_id), "logs")
    message = "安装任务异常: %s" % exc
    repo.update_job(job_id, status="failed", finished_at=_now())
    append_log(job_id, log_dir, message, "job.status", {"status": "failed"})


def _run_step(job_id, context, step, log_dir, artifacts):
    repo = Repository()
    step_row = repo.create_job_step(job_id, step)
    repo.update_job_step(step_row["id"], status="running", started_at=_now())
    append_log(job_id, log_dir, "开始步骤: %s" % step["key"], "step.status", {"step_key": step["key"], "status": "running"})
    targets = resolve_targets(step, context)
    if not step.get("builtin") and not os.path.exists(step["script"]):
        message = "脚本不存在: %s" % step["script"]
        repo.update_job_step(step_row["id"], status="failed", finished_at=_now(), exit_code=127, message=message)
        append_log(job_id, log_dir, message, "step.status", {"step_key": step["key"], "status": "failed"})
        repo.close()
        return False
    if not targets:
        repo.update_job_step(step_row["id"], status="success", finished_at=_now(), exit_code=0, message="无目标节点，跳过")
        append_log(job_id, log_dir, "步骤无目标节点，跳过: %s" % step["key"])
        repo.close()
        return True

    failed = False
    failure_messages = []
    if step.get("mode") == "parallel":
        max_workers = min(int(step.get("max_workers") or 5), len(targets))
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [
                executor.submit(_run_step_on_node, job_id, context, step, step_row["id"], node, log_dir, artifacts)
                for node in targets
            ]
            for future in as_completed(futures):
                try:
                    result = future.result()
                except Exception as exc:
                    failed = True
                    failure_messages.append(str(exc))
                    continue
                if not _result_ok(result):
                    failed = True
    else:
        for node in targets:
            result = _run_step_on_node(
                job_id, context, step, step_row["id"], node, log_dir, artifacts
            )
            if not _result_ok(result):
                failed = True
                if step.get("fail_fast", True):
                    break

    status = "failed" if failed else "success"
    if not failed:
        try:
            _collect_step_outputs(job_id, context, step, targets, artifacts)
        except ValueError as exc:
            failed = True
            status = "failed"
            failure_messages.append(str(exc))
    message = "; ".join(failure_messages)
    repo.update_job_step(
        step_row["id"],
        status=status,
        finished_at=_now(),
        exit_code=1 if failed else 0,
        message=message,
    )
    append_log(job_id, log_dir, "步骤完成: %s status=%s" % (step["key"], status), "step.status", {"step_key": step["key"], "status": status})
    repo.close()
    return not failed


def _run_step_on_node(job_id, context, step, step_id, node, log_dir, artifacts):
    repo = Repository()
    node_dir = os.path.join(log_dir, step["key"])
    os.makedirs(node_dir, exist_ok=True)
    node_log_path = os.path.join(node_dir, "%s.log" % node["hostname"])
    node_row = repo.create_job_step_node(step_id, node["id"], node_log_path)
    repo.update_job_step_node(node_row["id"], status="running", started_at=_now())
    emit(job_id, "node.status", {"step_key": step["key"], "node_id": node["id"], "hostname": node["hostname"], "status": "running"})

    code = 1
    out = ""
    err = ""
    try:
        if step.get("builtin") == "cluster_health":
            code, out, err = check_cluster_health(node, context)
        else:
            work_dir = os.path.join(data_dir(), "jobs", str(job_id), "work", step["key"], node["hostname"])
            if not os.path.exists(work_dir):
                os.makedirs(work_dir)
            runtime_path = write_runtime_env(os.path.join(work_dir, "runtime.env"), context, node)
            script_copy = os.path.join(work_dir, "step.sh")
            _write_step_script(script_copy, step, context, node)

            remote_dir = "/tmp/kubefoundry/%s/%s/%s" % (job_id, step["key"], node["hostname"])
            code, out, err = run_ssh(node, context, "mkdir -p %s" % shell_quote(remote_dir), timeout=60)
            if code == 0:
                code, out, err = _copy_step_resources(step, context, node, artifacts)
            if code == 0:
                for local_name in [runtime_path, script_copy]:
                    code, out, err = scp_to_node(local_name, remote_dir + "/" + os.path.basename(local_name), node, context)
                    if code != 0:
                        break
            if code == 0:
                args = " ".join(shell_quote(item) for item in _resolve_step_args(step, context))
                inner_command = "source runtime.env && bash step.sh"
                if args:
                    inner_command += " " + args
                verify_command = _format_verify_command(step.get("verify_command"), context, node)
                if verify_command:
                    inner_command += " && { %s; }" % verify_command
                command = "cd %s && chmod +x step.sh && bash -lc %s" % (
                    shell_quote(remote_dir),
                    shell_quote(inner_command),
                )
                code, out, err = run_ssh(node, context, command, timeout=3600)
    except Exception as exc:
        code = 1
        out = ""
        err = str(exc)

    try:
        with open(node_log_path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(out or "")
            fh.write(err or "")
        ok = code == 0
        status = "success" if ok else "failed"
        message = "执行成功" if ok else "执行失败，退出码: %s" % code
        repo.update_job_step_node(node_row["id"], status=status, finished_at=_now(), exit_code=code, message=message)
        append_log(job_id, log_dir, "%s %s %s" % (step["key"], node["hostname"], message), "node.status", {
            "step_key": step["key"],
            "node_id": node["id"],
            "hostname": node["hostname"],
            "status": status,
            "exit_code": code,
            "log_path": node_log_path,
        })
        return _node_result(ok, code, message, out, err)
    finally:
        repo.close()


def _node_result(ok, exit_code, message, stdout="", stderr=""):
    return {
        "ok": bool(ok),
        "exit_code": int(exit_code),
        "message": message,
        "stdout": stdout or "",
        "stderr": stderr or "",
    }


def _result_ok(result):
    if isinstance(result, dict):
        return bool(result.get("ok"))
    return bool(result)


def _copy_step_resources(step, context, node, artifacts):
    paths = context.get("paths") or {}
    for resource in step.get("resources") or []:
        if resource.get("artifact_key"):
            source = artifacts.get(resource.get("artifact_key"))
        else:
            source = paths.get(resource.get("path_key"))
        if not source or not os.path.exists(source):
            return 2, "", "step resource is unavailable: %s" % (
                resource.get("artifact_key") or resource.get("path_key")
            )
        remote_path = _format_remote_path(resource.get("remote_path"), context)
        code, out, err = copy_path_to_node(source, remote_path, node, context)
        if code != 0:
            return code, out, err
    return 0, "", ""


def _write_step_script(path, step, context, node):
    if step.get("builtin") == "setup_hostname":
        content = _render_hostname_script(context)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(content)
        return
    shutil.copyfile(step["script"], path)


def _render_hostname_script(context):
    registry = context.get("registry") or {}
    lines = ["#!/bin/bash", "set -e", 'hostnamectl set-hostname "$KF_NODE_HOSTNAME"']
    lines.append("sed -i '/^# >>>KubeFoundry>>>$/,/^# <<<KubeFoundry<<</d' /etc/hosts")
    lines.append("cat >> /etc/hosts <<'KF_HOSTS_EOF'")
    lines.append("# >>>KubeFoundry>>>")
    host_nodes = (
        (context.get("control_plane") or [])
        + (context.get("workers") or [])
        + (context.get("registry_nodes") or [])
    )
    seen_ips = set()
    for item in host_nodes:
        if item.get("ip") in seen_ips:
            continue
        seen_ips.add(item.get("ip"))
        aliases = [item.get("hostname")]
        if item.get("ip") == registry.get("ip") and registry.get("hostname") not in aliases:
            aliases.append(registry.get("hostname"))
        lines.append("%s    %s" % (item.get("ip"), "    ".join(filter(None, aliases))))
    registry_ip = registry.get("ip")
    known_ips = set(item.get("ip") for item in context.get("nodes") or [])
    if registry_ip and registry_ip not in known_ips:
        lines.append("%s    %s" % (registry_ip, registry.get("hostname")))
    lines.extend(["# <<<KubeFoundry<<<", "KF_HOSTS_EOF", 'log_success "主机名和 hosts 配置完成"'])
    return "\n".join(lines) + "\n"


def _resolve_step_args(step, context):
    result = []
    primary = (context.get("control_plane") or [{}])[0]
    context_values = {
        "primary_control_ip": primary.get("ip", ""),
        "primary_control_hostname": primary.get("hostname", ""),
    }
    for spec in step.get("args") or []:
        if "literal" in spec:
            result.append(spec["literal"])
        elif "context" in spec:
            result.append(context_values.get(spec["context"], ""))
    return result


def _format_remote_path(path, context):
    return str(path).format(k8s_home=(context.get("paths") or {}).get("k8s_home", "/data/k8s_install"))


def _format_verify_command(command, context, node):
    if not command:
        return ""
    primary = (context.get("control_plane") or [{}])[0]
    values = {
        "node_hostname": shell_quote(node.get("hostname", "")),
        "node_ip": shell_quote(node.get("ip", "")),
        "primary_control_ip": shell_quote(primary.get("ip", "")),
        "primary_control_hostname": shell_quote(primary.get("hostname", "")),
    }
    return str(command).format(**values)


def _collect_step_outputs(job_id, context, step, targets, artifacts):
    outputs = step.get("outputs") or []
    if not outputs:
        return
    if not targets:
        raise ValueError("step output target is unavailable")
    node = targets[0]
    artifact_dir = os.path.join(data_dir(), "jobs", str(job_id), "artifacts")
    if not os.path.exists(artifact_dir):
        os.makedirs(artifact_dir)
    for output in outputs:
        code, out, err = run_ssh(
            node,
            context,
            "cat %s" % shell_quote(output["remote_path"]),
            timeout=60,
        )
        if code != 0 or not (out or "").strip():
            raise ValueError(
                "failed to collect step output %s: %s" % (output["key"], err or "empty output")
            )
        local_path = os.path.join(artifact_dir, output["key"])
        with open(local_path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(out)
        artifacts[output["key"]] = local_path


def _read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def _now():
    import datetime
    return datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
