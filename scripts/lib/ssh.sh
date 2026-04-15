#!/bin/bash

#===============================================================================
# 脚本名称：ssh.sh
# 功能：SSH/SCP 操作函数库
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 防止重复加载
[ -n "$_SSH_LOADED" ] && return 0
_SSH_LOADED=1

# 从配置文件加载 SSH 参数
_SSH_USER=$(config_get '.ssh.user' 'root' 2>/dev/null)
_SSH_PORT=$(config_get '.ssh.port' '22' 2>/dev/null)
_SSH_KEY=$(config_get '.ssh.key_path' '~/.ssh/id_rsa' 2>/dev/null)
_SSH_TIMEOUT=$(config_get '.ssh.timeout' '30' 2>/dev/null)

#===============================================================================
# 函数：_get_ssh_target()
# 功能：获取 SSH 连接目标（优先使用 hostname，fallback 到 IP）
# 参数：
#   $1 - 节点 IP 地址或 hostname
# 返回值：
#   hostname（如果可用），否则返回 IP
#===============================================================================
_get_ssh_target() {
    local node_ip="$1"
    local hostname

    # 尝试从配置文件获取 hostname
    hostname=$(get_node_hostname "$node_ip" 2>/dev/null)

    # hostname 存在且可解析时才使用，否则回退到 IP
    if [ -n "$hostname" ] && [ "$hostname" != "$node_ip" ] && getent hosts "$hostname" >/dev/null 2>&1; then
        echo "$hostname"
    else
        echo "$node_ip"
    fi
}

#===============================================================================
# 函数：check_ssh_connection()
# 功能：检查 SSH 连接是否可用（支持 hostname 和 IP）
# 参数：
#   $1 - 节点 IP 地址或 hostname
#   $2 - SSH 用户名（可选，默认从配置文件读取）
#   $3 - SSH 端口（可选，默认从配置文件读取）
#   $4 - SSH 密钥路径（可选，默认从配置文件读取）
#   $5 - 连接超时时间（可选，默认从配置文件读取）
# 返回值：
#   0 - 连接成功
#   1 - 连接失败
#===============================================================================
check_ssh_connection() {
    local node="$1"
    local ssh_user="${2:-$_SSH_USER}"
    local ssh_port="${3:-$_SSH_PORT}"
    local ssh_key="${4:-$_SSH_KEY}"
    local ssh_timeout="${5:-$_SSH_TIMEOUT}"

    # 获取连接目标（优先 hostname）
    local target
    target=$(_get_ssh_target "$node")

    log_info "检查 SSH 连接: ${target} (user: ${ssh_user}, port: ${ssh_port})"

    # 展开路径中的 ~
    ssh_key="${ssh_key/#\~/$HOME}"

    # 使用 ssh 测试连接
    if ssh -i "${ssh_key}" -p "${ssh_port}" -o ConnectTimeout="${ssh_timeout}" \
        -o StrictHostKeyChecking=no -o BatchMode=yes \
        "${ssh_user}@${target}" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        log_success "SSH 连接成功: ${target}"
        return 0
    else
        log_error "SSH 连接失败: ${target}"
        return 1
    fi
}

#===============================================================================
# 函数：ssh_exec()
# 功能：在远程节点执行单个命令（支持 hostname 和 IP）
# 参数：
#   $1 - 节点 IP 地址或 hostname
#   $2 - 要执行的命令
# 返回值：
#   0 - 执行成功
#   非 0 - 执行失败
#===============================================================================
ssh_exec() {
    local node="$1"
    local command="$2"

    # 获取连接目标（优先 hostname）
    local target
    target=$(_get_ssh_target "$node")

    # 展开路径中的 ~
    local ssh_key="${_SSH_KEY/#\~/$HOME}"

    log_info "在节点 ${target} 执行命令: ${command}"

    # 执行 SSH 命令
    if ssh -i "${ssh_key}" -p "${_SSH_PORT}" -o ConnectTimeout="${_SSH_TIMEOUT}" \
        -o StrictHostKeyChecking=no \
        "${_SSH_USER}@${target}" "${command}"; then
        log_success "命令执行成功: ${target}"
        return 0
    else
        log_error "命令执行失败: ${target}, 命令: ${command}"
        return 1
    fi
}

#===============================================================================
# 函数：scp_exec()
# 功能：传输文件到远程节点（支持 hostname 和 IP）
# 参数：
#   $1 - 本地文件路径
#   $2 - 远程目标路径
#   $3 - 目标节点 IP 地址或 hostname
# 返回值：
#   0 - 传输成功
#   非 0 - 传输失败
#===============================================================================
scp_exec() {
    local local_file="$1"
    local remote_path="$2"
    local node="$3"

    # 检查本地文件是否存在
    if [ ! -f "$local_file" ]; then
        log_error "本地文件不存在: ${local_file}"
        return 1
    fi

    # 获取连接目标（优先 hostname）
    local target
    target=$(_get_ssh_target "$node")

    # 展开路径中的 ~
    local ssh_key="${_SSH_KEY/#\~/$HOME}"

    log_info "传输文件: ${local_file} -> ${target}:${remote_path}"

    # 执行 SCP 命令
    if scp -i "${ssh_key}" -P "${_SSH_PORT}" -o ConnectTimeout="${_SSH_TIMEOUT}" \
        -o StrictHostKeyChecking=no \
        "${local_file}" "${_SSH_USER}@${target}:${remote_path}"; then
        log_success "文件传输成功: ${target}"
        return 0
    else
        log_error "文件传输失败: ${target}, 源文件: ${local_file}"
        return 1
    fi
}

#===============================================================================
# 函数：scp_dir_to_node()
# 功能：传输本地目录到远程节点（支持 hostname 和 IP）
# 参数：
#   $1 - 本地目录路径
#   $2 - 远程目标父目录（目录将放置在此路径下）
#   $3 - 目标节点 IP 地址或 hostname
# 返回值：
#   0 - 传输成功
#   非 0 - 传输失败
#===============================================================================
scp_dir_to_node() {
    local local_dir="$1"
    local remote_parent="$2"
    local node="$3"

    # 检查本地目录是否存在
    if [ ! -d "$local_dir" ]; then
        log_error "本地目录不存在: ${local_dir}"
        return 1
    fi

    # 获取连接目标（优先 hostname）
    local target
    target=$(_get_ssh_target "$node")

    # 展开路径中的 ~
    local ssh_key="${_SSH_KEY/#\~/$HOME}"

    log_info "传输目录: ${local_dir} -> ${target}:${remote_parent}/"

    # 远程创建父目录
    ssh -n -i "${ssh_key}" -p "${_SSH_PORT}" -o ConnectTimeout="${_SSH_TIMEOUT}" \
        -o StrictHostKeyChecking=no \
        "${_SSH_USER}@${target}" "mkdir -p ${remote_parent}" || return 1

    # 执行 scp -r 传输目录
    if scp -r -i "${ssh_key}" -P "${_SSH_PORT}" -o ConnectTimeout="${_SSH_TIMEOUT}" \
        -o StrictHostKeyChecking=no \
        "${local_dir}" "${_SSH_USER}@${target}:${remote_parent}/"; then
        log_success "目录传输成功: ${target}"
        return 0
    else
        log_error "目录传输失败: ${target}, 源目录: ${local_dir}"
        return 1
    fi
}

#===============================================================================
# 函数：scp_dir_to_all_nodes()
# 功能：传输本地目录到所有节点
# 参数：
#   $1 - 本地目录路径
#   $2 - 远程目标父目录
# 返回值：
#   0 - 所有节点传输成功
#   非 0 - 至少一个节点传输失败
#===============================================================================
scp_dir_to_all_nodes() {
    local local_dir="$1"
    local remote_parent="$2"
    local success=true

    log_info "分发目录到所有节点: ${local_dir} -> ${remote_parent}/"

    # 分发到控制节点
    local control_plane_ips
    control_plane_ips=$(get_all_control_plane_ips)
    while IFS= read -r node_ip; do
        if ! scp_dir_to_node "$local_dir" "$remote_parent" "$node_ip"; then
            success=false
        fi
    done <<< "$control_plane_ips"

    # 分发到工作节点
    local worker_ips
    worker_ips=$(get_all_worker_ips)
    while IFS= read -r node_ip; do
        if ! scp_dir_to_node "$local_dir" "$remote_parent" "$node_ip"; then
            success=false
        fi
    done <<< "$worker_ips"

    # 分发到镜像仓库节点（如果与控制节点不同）
    local registry_ip
    registry_ip=$(get_registry_ip)
    if [ -n "$registry_ip" ]; then
        local found=false
        while IFS= read -r ip; do
            if [ "$ip" = "$registry_ip" ]; then
                found=true
                break
            fi
        done <<< "$control_plane_ips"
        if [ "$found" = false ]; then
            if ! scp_dir_to_node "$local_dir" "$remote_parent" "$registry_ip"; then
                success=false
            fi
        fi
    fi

    if [ "$success" = true ]; then
        log_success "所有节点目录分发成功"
        return 0
    else
        log_error "部分节点目录分发失败"
        return 1
    fi
}

#===============================================================================
# 函数：ssh_exec_capture()
# 功能：在远程节点执行命令并捕获输出（支持 hostname 和 IP）
# 参数：
#   $1 - 节点 IP 地址或 hostname
#   $2 - 要执行的命令
# 返回值：
#   标准输出
#===============================================================================
ssh_exec_capture() {
    local node="$1"
    local command="$2"

    # 获取连接目标（优先 hostname）
    local target
    target=$(_get_ssh_target "$node")

    # 展开路径中的 ~
    local ssh_key="${_SSH_KEY/#\~/$HOME}"

    # 执行 SSH 命令并捕获输出
    ssh -i "${ssh_key}" -p "${_SSH_PORT}" -o ConnectTimeout="${_SSH_TIMEOUT}" \
        -o StrictHostKeyChecking=no \
        "${_SSH_USER}@${target}" "${command}" 2>/dev/null
}
