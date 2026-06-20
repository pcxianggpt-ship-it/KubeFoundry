import os
import subprocess


def expand_user(path):
    if not path:
        return path
    return os.path.expanduser(path)


def ssh_base_command(node, context, batch_mode=True):
    ssh = context.get("ssh") or {}
    user = node.get("ssh_user") or ssh.get("username") or "root"
    port = str(node.get("ssh_port") or 22)
    key_path = expand_user(ssh.get("private_key_path") or "~/.ssh/id_rsa")
    target = "%s@%s" % (user, node.get("ip"))
    cmd = [
        "ssh",
        "-p", port,
        "-o", "ConnectTimeout=30",
        "-o", "StrictHostKeyChecking=no",
    ]
    if batch_mode:
        cmd.extend(["-o", "BatchMode=yes"])
    if key_path:
        cmd.extend(["-i", key_path])
    cmd.append(target)
    return cmd


def run_ssh(node, context, command, timeout=60):
    cmd = ssh_base_command(node, context)
    cmd.append(command)
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        out, err = proc.communicate(timeout=timeout)
        return proc.returncode, out, err
    except subprocess.TimeoutExpired:
        proc.kill()
        out, err = proc.communicate()
        return 124, out, (err or "") + "\ncommand timeout"
    except OSError as exc:
        return 127, "", str(exc)


def run_local_command(command, timeout=3600):
    try:
        proc = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
        out, _ = proc.communicate(timeout=timeout)
        return proc.returncode, out
    except subprocess.TimeoutExpired:
        proc.kill()
        out, _ = proc.communicate()
        return 124, (out or "") + "\ncommand timeout"
    except OSError as exc:
        return 127, str(exc)


def scp_to_node(local_path, remote_path, node, context, timeout=300, recursive=False):
    ssh = context.get("ssh") or {}
    user = node.get("ssh_user") or ssh.get("username") or "root"
    port = str(node.get("ssh_port") or 22)
    key_path = expand_user(ssh.get("private_key_path") or "~/.ssh/id_rsa")
    target = "%s@%s:%s" % (user, node.get("ip"), remote_path)
    cmd = ["scp", "-P", port, "-o", "StrictHostKeyChecking=no", "-o", "BatchMode=yes"]
    if recursive:
        cmd.append("-r")
    if key_path:
        cmd.extend(["-i", key_path])
    cmd.extend([local_path, target])
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        out, err = proc.communicate(timeout=timeout)
        return proc.returncode, out, err
    except subprocess.TimeoutExpired:
        proc.kill()
        out, err = proc.communicate()
        return 124, out, (err or "") + "\nscp timeout"
    except OSError as exc:
        return 127, "", str(exc)


def copy_path_to_node(local_path, remote_path, node, context, timeout=1800):
    if os.path.isdir(local_path):
        remote_parent = os.path.dirname(remote_path)
        code, out, err = run_ssh(
            node,
            context,
            "mkdir -p %s" % shell_quote(remote_parent),
            timeout=60,
        )
        if code != 0:
            return code, out, err
        return scp_to_node(
            local_path,
            remote_parent,
            node,
            context,
            timeout=timeout,
            recursive=True,
        )

    remote_parent = os.path.dirname(remote_path)
    if remote_parent:
        code, out, err = run_ssh(
            node,
            context,
            "mkdir -p %s" % shell_quote(remote_parent),
            timeout=60,
        )
        if code != 0:
            return code, out, err
    return scp_to_node(local_path, remote_path, node, context, timeout=timeout)


def shell_quote(value):
    import shlex
    return shlex.quote(str(value))
