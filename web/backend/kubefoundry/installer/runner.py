import os
import shutil
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

from kubefoundry.installer.context import build_cluster_context, write_job_snapshot
from kubefoundry.installer.events import append_log, emit
from kubefoundry.installer.plan import resolve_targets, selected_plan
from kubefoundry.installer.runtime import write_runtime_env
from kubefoundry.installer.ssh import run_ssh, scp_to_node
from kubefoundry.store.db import data_dir
from kubefoundry.store.repository import Repository


def start_install_job(cluster_id, selected_steps=None):
    context = build_cluster_context(cluster_id)
    job_dir = os.path.join(data_dir(), "jobs", "pending")
    repo = Repository()
    job = repo.create_job(cluster_id, "install", context, "", job_dir)
    context, snapshot_path, yaml_path = write_job_snapshot(cluster_id, job["id"])
    log_dir = os.path.join(data_dir(), "jobs", str(job["id"]), "logs")
    repo.update_job(job["id"], config_snapshot=_read(snapshot_path), config_yaml_path=yaml_path, log_dir=log_dir)
    thread = threading.Thread(target=run_install_job, args=(job["id"], cluster_id, selected_steps), daemon=True)
    thread.start()
    return repo.get_job(job["id"])


def run_install_job(job_id, cluster_id, selected_steps=None):
    try:
        _run_install_job(job_id, cluster_id, selected_steps)
    except Exception as exc:
        _fail_job(job_id, exc)


def _run_install_job(job_id, cluster_id, selected_steps=None):
    repo = Repository()
    context = build_cluster_context(cluster_id)
    log_dir = os.path.join(data_dir(), "jobs", str(job_id), "logs")
    repo.update_job(job_id, status="running", started_at=_now())
    append_log(job_id, log_dir, "安装任务启动", "job.status", {"status": "running"})
    failed = False
    for step in selected_plan(selected_steps):
        repo.update_job(job_id, current_step_key=step["key"])
        if not _run_step(job_id, context, step, log_dir):
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


def _run_step(job_id, context, step, log_dir):
    repo = Repository()
    step_row = repo.create_job_step(job_id, step)
    repo.update_job_step(step_row["id"], status="running", started_at=_now())
    append_log(job_id, log_dir, "开始步骤: %s" % step["key"], "step.status", {"step_key": step["key"], "status": "running"})
    targets = resolve_targets(step, context)
    if not os.path.exists(step["script"]):
        message = "脚本不存在: %s" % step["script"]
        repo.update_job_step(step_row["id"], status="failed", finished_at=_now(), exit_code=127, message=message)
        append_log(job_id, log_dir, message, "step.status", {"step_key": step["key"], "status": "failed"})
        return False
    if not targets:
        repo.update_job_step(step_row["id"], status="success", finished_at=_now(), exit_code=0, message="无目标节点，跳过")
        append_log(job_id, log_dir, "步骤无目标节点，跳过: %s" % step["key"])
        return True

    failed = False
    if step.get("mode") == "parallel":
        max_workers = min(int(step.get("max_workers") or 5), len(targets))
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [
                executor.submit(_run_step_on_node, job_id, context, step, step_row["id"], node, log_dir)
                for node in targets
            ]
            for future in as_completed(futures):
                if not future.result():
                    failed = True
    else:
        for node in targets:
            if not _run_step_on_node(job_id, context, step, step_row["id"], node, log_dir):
                failed = True
                if step.get("fail_fast", True):
                    break

    status = "failed" if failed else "success"
    repo.update_job_step(step_row["id"], status=status, finished_at=_now(), exit_code=1 if failed else 0)
    append_log(job_id, log_dir, "步骤完成: %s status=%s" % (step["key"], status), "step.status", {"step_key": step["key"], "status": status})
    return not failed


def _run_step_on_node(job_id, context, step, step_id, node, log_dir):
    repo = Repository()
    node_dir = os.path.join(log_dir, step["key"])
    if not os.path.exists(node_dir):
        os.makedirs(node_dir)
    node_log_path = os.path.join(node_dir, "%s.log" % node["hostname"])
    node_row = repo.create_job_step_node(step_id, node["id"], node_log_path)
    repo.update_job_step_node(node_row["id"], status="running", started_at=_now())
    emit(job_id, "node.status", {"step_key": step["key"], "node_id": node["id"], "hostname": node["hostname"], "status": "running"})

    work_dir = os.path.join(data_dir(), "jobs", str(job_id), "work", step["key"], node["hostname"])
    if not os.path.exists(work_dir):
        os.makedirs(work_dir)
    runtime_path = write_runtime_env(os.path.join(work_dir, "runtime.env"), context, node)
    script_copy = os.path.join(work_dir, "step.sh")
    shutil.copyfile(step["script"], script_copy)

    remote_dir = "/tmp/kubefoundry/%s/%s/%s" % (job_id, step["key"], node["hostname"])
    code, out, err = run_ssh(node, context, "mkdir -p %s" % remote_dir, timeout=60)
    if code == 0:
        for local_name in [runtime_path, script_copy]:
            code, out, err = scp_to_node(local_name, remote_dir + "/" + os.path.basename(local_name), node, context)
            if code != 0:
                break
    if code == 0:
        command = "cd %s && chmod +x step.sh && bash -lc 'source runtime.env && bash step.sh'" % remote_dir
        code, out, err = run_ssh(node, context, command, timeout=3600)

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
    return ok


def _read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def _now():
    import datetime
    return datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
