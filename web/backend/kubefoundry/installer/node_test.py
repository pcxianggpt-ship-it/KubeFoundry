import os
import subprocess
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

from kubefoundry.installer.events import append_log, emit
from kubefoundry.installer.ssh import shell_quote
from kubefoundry.security.credentials import decrypt_text, redact_sensitive
from kubefoundry.store.db import data_dir
from kubefoundry.store.repository import Repository


OS_ARCH_COMMAND = r"""
cat /etc/os-release
printf "__KF_ARCH=%s\n" "$(uname -m)"
"""


def normalize_arch(value):
    arch = (value or "").strip()
    mapping = {
        "x86_64": "amd64",
        "aarch64": "arm64",
    }
    return mapping.get(arch, arch)


def parse_os_release(text):
    values = {}
    for raw_line in (text or "").splitlines():
        line = raw_line.strip()
        if not line or "=" not in line or line.startswith("__KF_ARCH="):
            continue
        key, value = line.split("=", 1)
        values[key] = value.strip().strip('"').strip("'")
    version = values.get("VERSION_ID") or values.get("VERSION") or ""
    return {
        "os_type": values.get("ID", ""),
        "os_name": values.get("NAME", values.get("ID", "")),
        "os_version": version,
        "os_major": _major_version(version),
    }


def start_node_test_job(cluster_id):
    repo = Repository()
    try:
        problems = repo.validate_node_configuration(cluster_id)
        if problems:
            raise ValueError(_format_problems(problems))
        active = repo.find_active_job(cluster_id, "node_test")
        if active:
            error = ValueError("cluster already has an active node test job")
            error.job_id = active["id"]
            raise error
        cluster = repo.get_cluster_private(cluster_id)
        config_version = cluster.get("node_config_version") or 1
        job = repo.create_job(
            cluster_id,
            "node_test",
            {"cluster_id": cluster_id, "node_config_version": config_version},
            "",
            os.path.join(data_dir(), "jobs", "pending"),
        )
        repo.update_cluster_node_test_state(cluster_id, "running", job_id=job["id"])
        thread = threading.Thread(
            target=run_node_test_job,
            args=(job["id"], cluster_id, config_version),
            daemon=True,
        )
        thread.start()
        return repo.get_job(job["id"])
    finally:
        repo.close()


def run_node_test_job(job_id, cluster_id, config_version):
    try:
        _run_node_test_job(job_id, cluster_id, config_version)
    except Exception as exc:
        repo = Repository()
        log_dir = os.path.join(data_dir(), "jobs", str(job_id), "logs")
        repo.update_job(job_id, status="failed", finished_at=_now(), failure_reason=redact_sensitive(str(exc)))
        repo.update_cluster_node_test_state(cluster_id, "failed", job_id=job_id)
        append_log(job_id, log_dir, "节点测试任务异常: %s" % redact_sensitive(str(exc)), "job.status", {"status": "failed"})
        repo.close()


def ensure_cluster_key(cluster_id):
    cluster_dir = os.path.join(data_dir(), "credentials", "clusters", str(cluster_id))
    if not os.path.exists(cluster_dir):
        os.makedirs(cluster_dir)
    _chmod(cluster_dir, 0o700)
    private_key = os.path.join(cluster_dir, "id_rsa")
    public_key = private_key + ".pub"
    if not os.path.exists(private_key) or not os.path.exists(public_key):
        command = ["ssh-keygen", "-t", "rsa", "-b", "4096", "-N", "", "-f", private_key]
        proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        out, err = proc.communicate(timeout=60)
        if proc.returncode != 0:
            raise ValueError("ssh-keygen failed: %s" % redact_sensitive(err or out))
    _chmod(private_key, 0o600)
    _chmod(public_key, 0o644)
    with Repository() as repo:
        repo.upsert_ssh_credentials(
            cluster_id,
            {
                "auth_type": "key",
                "username": "root",
                "private_key_path": private_key,
            },
        )
    return private_key, public_key


def run_password_ssh(node, password, command, timeout=60):
    user = node.get("ssh_user") or "root"
    port = str(node.get("ssh_port") or 22)
    cmd = [
        "sshpass",
        "-e",
        "ssh",
        "-p",
        port,
        "-o",
        "ConnectTimeout=30",
        "-o",
        "StrictHostKeyChecking=no",
        "%s@%s" % (user, node.get("ip")),
        command,
    ]
    env = os.environ.copy()
    env["SSHPASS"] = password or ""
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            env=env,
        )
        out, err = proc.communicate(timeout=timeout)
        return proc.returncode, redact_sensitive(out), redact_sensitive(err)
    except subprocess.TimeoutExpired:
        proc.kill()
        out, err = proc.communicate()
        return 124, redact_sensitive(out), redact_sensitive((err or "") + "\ncommand timeout")
    except OSError as exc:
        return 127, "", redact_sensitive(str(exc))


def _run_node_test_job(job_id, cluster_id, config_version):
    repo = Repository()
    job_dir = os.path.join(data_dir(), "jobs", str(job_id))
    log_dir = os.path.join(job_dir, "logs")
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
    repo.update_job(job_id, status="running", started_at=_now())
    append_log(job_id, log_dir, "节点测试任务启动", "job.status", {"status": "running"})
    private_key, public_key = ensure_cluster_key(cluster_id)
    step = repo.create_job_step(
        job_id,
        {
            "key": "node-test-ssh-and-system",
            "name": "测试 SSH 连通性并识别系统",
            "phase": "node_test",
            "target_scope": "all_nodes",
        },
    )
    repo.update_job_step(step["id"], status="running", started_at=_now())
    nodes = repo.list_nodes_private(cluster_id)
    results = []
    with ThreadPoolExecutor(max_workers=min(5, max(1, len(nodes)))) as executor:
        futures = [
            executor.submit(_test_one_node, job_id, step["id"], node, public_key, private_key, config_version, log_dir)
            for node in nodes
        ]
        for future in as_completed(futures):
            results.append(future.result())
    homogeneity_error = _check_homogeneity([item for item in results if item.get("ok")])
    failed = any(not item.get("ok") for item in results) or bool(homogeneity_error)
    if homogeneity_error:
        append_log(job_id, log_dir, homogeneity_error)
    status = "failed" if failed else "success"
    repo.update_job_step(step["id"], status=status, finished_at=_now(), exit_code=1 if failed else 0, message=homogeneity_error or "")
    repo.update_job(job_id, status=status, finished_at=_now(), current_step_key=step["step_key"])
    repo.update_cluster_node_test_state(cluster_id, status, job_id=job_id)
    append_log(job_id, log_dir, "节点测试任务完成，状态: %s" % status, "job.status", {"status": status})
    repo.close()


def _test_one_node(job_id, step_id, node, public_key, private_key, config_version, log_dir):
    repo = Repository()
    node_dir = os.path.join(log_dir, "node-test-ssh-and-system")
    if not os.path.exists(node_dir):
        os.makedirs(node_dir)
    node_log_path = os.path.join(node_dir, "%s.log" % node["hostname"])
    item = repo.create_job_step_node(step_id, node["id"], node_log_path)
    repo.update_job_step_node(item["id"], status="running", started_at=_now())
    emit(job_id, "node.status", {"node_id": node["id"], "hostname": node["hostname"], "status": "running"})
    status = "failed"
    message = ""
    code = 1
    out = ""
    err = ""
    os_info = {}
    arch = ""
    try:
        password = decrypt_text(node.get("login_password_encrypted") or "")
        with open(public_key, "r", encoding="utf-8") as fh:
            public_key_text = fh.read().strip()
        setup_command = (
            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && "
            "touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && "
            "grep -qxF %s ~/.ssh/authorized_keys || echo %s >> ~/.ssh/authorized_keys"
            % (shell_quote(public_key_text), shell_quote(public_key_text))
        )
        code, out, err = run_password_ssh(node, password, setup_command, timeout=60)
        if code == 0:
            context = {"ssh": {"username": node.get("ssh_user") or "root", "private_key_path": private_key}}
            from kubefoundry.installer.ssh import run_ssh

            code, out, err = run_ssh(node, context, OS_ARCH_COMMAND, timeout=60)
        if code == 0:
            os_info = parse_os_release(out)
            arch = normalize_arch(_parse_arch(out))
            if not os_info.get("os_type") or not arch:
                raise ValueError("操作系统或架构识别失败")
            status = "success"
            message = "测试成功"
        else:
            message = "测试失败，退出码: %s" % code
    except Exception as exc:
        message = redact_sensitive(str(exc))
    with open(node_log_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(redact_sensitive(out or ""))
        fh.write(redact_sensitive(err or ""))
        if message:
            fh.write("\n%s\n" % redact_sensitive(message))
    repo.update_node_test_result(
        node["id"],
        status,
        message,
        os_type=os_info.get("os_type", ""),
        os_version=os_info.get("os_version", ""),
        arch=arch,
        config_version=config_version,
    )
    repo.update_job_step_node(item["id"], status=status, finished_at=_now(), exit_code=0 if status == "success" else 1, message=message)
    emit(job_id, "node.status", {"node_id": node["id"], "hostname": node["hostname"], "status": status})
    repo.close()
    return {
        "ok": status == "success",
        "node_id": node["id"],
        "hostname": node["hostname"],
        "os_type": os_info.get("os_type", ""),
        "os_major": os_info.get("os_major", ""),
        "arch": arch,
    }


def _format_problems(problems):
    return "；".join("%s：%s" % (item.get("hostname") or item.get("node_id"), item.get("message")) for item in problems)


def _parse_arch(text):
    for line in (text or "").splitlines():
        if line.startswith("__KF_ARCH="):
            return line.split("=", 1)[1].strip()
    return ""


def _major_version(version):
    value = str(version or "").strip()
    if not value:
        return ""
    return value.split(".", 1)[0]


def _check_homogeneity(results):
    if not results:
        return ""
    first = results[0]
    for item in results[1:]:
        if item.get("arch") != first.get("arch"):
            return "集群内节点架构不一致"
        if item.get("os_type") != first.get("os_type") or item.get("os_major") != first.get("os_major"):
            return "集群内节点操作系统发行版或主版本不一致"
    return ""


def _chmod(path, mode):
    try:
        os.chmod(path, mode)
    except OSError:
        pass


def _now():
    import datetime
    return datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
