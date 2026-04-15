#!/bin/bash

#===============================================================================
# 脚本名称：exec_script.sh
# 功能：批量执行脚本函数库
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

#===============================================================================
# 函数：exec_script_on_single_node()
# 功能：在单个节点上通过 SSH 管道直接执行本地脚本（底层实现函数）
# 参数：
#   $1 - 节点 IP 地址
#   $2 - 本地脚本路径
#   $3...$N - 传递给脚本的参数（可选，支持多个）
# 返回值：
#   0 - 执行成功
#   非 0 - 执行失败
# 说明：
#   - 通过 ssh ... 'bash -s' < script 直接执行，无需 SCP 传输
#   - 远程节点不留残余文件
#   - 使用配置文件中的 SSH 参数（用户、端口、密钥、超时）
#===============================================================================
exec_script_on_single_node() {
    local node_ip="$1"
    local script_path="$2"
    shift 2  # 移除前两个参数，剩余为脚本参数

    # 获取节点信息
    local node_hostname
    node_hostname=$(get_node_hostname "$node_ip" 2>/dev/null)

    # 检查脚本文件是否存在
    if [ ! -f "$script_path" ]; then
        log_error "脚本文件不存在: ${script_path}"
        return 1
    fi

    log_node "control_plane" "${node_hostname}" "执行脚本: ${script_path}"

    # 构建 bash -s 命令（支持透传参数）
    local bash_command="bash -s"
    if [ $# -gt 0 ]; then
        bash_command="bash -s -- $(printf '%q ' "$@")"
    fi

    # 获取 SSH 连接参数
    local target
    target=$(_get_ssh_target "$node_ip")
    local ssh_key="${_SSH_KEY/#\~/$HOME}"

    log_debug "通过SSH管道执行脚本，参数: $*"

    # 预解析脚本可能需要的配置值（避免远程依赖 yq 和配置文件）
    local _inj_k8s_soft _inj_kubelet_root _inj_k8s_version
    local _inj_registry_ip _inj_registry_hn
    local _inj_ssh_user _inj_ssh_password _inj_ssh_port
    _inj_k8s_soft=$(config_get '.paths.k8s_home' '/data/k8s_install' 2>/dev/null)
    _inj_arch=$(config_get '.paths.arch' 'amd64' 2>/dev/null)
    _inj_kubelet_root=$(config_get '.env.kubelet_root' '/data/kubelet_root' 2>/dev/null)
    _inj_k8s_version=$(config_get '.cluster.k8s_version' '1.30.14' 2>/dev/null)
    _inj_registry_ip=$(config_get '.registry.ip' '' 2>/dev/null)
    _inj_registry_hn=$(config_get '.registry.hostname' '' 2>/dev/null)
    _inj_ssh_user=$(config_get '.ssh.user' 'root' 2>/dev/null)
    _inj_ssh_password=$(config_get '.ssh.password' '' 2>/dev/null)
    _inj_ssh_port=$(config_get '.ssh.port' '22' 2>/dev/null)

    # 构建注入头：环境变量 + 内联简化日志函数 + 预解析配置值
    local inject_header
    inject_header=$(cat <<INJECT_EOF
export PROJECT_ROOT="${PROJECT_ROOT}"
export CONFIG_FILE="${CONFIG_FILE}"
export LOG_FILE="${LOG_FILE}"
export K8S_SOFT="${_inj_k8s_soft}"
export K8S_HOME="${_inj_k8s_soft}"
export ARCH="${_inj_arch}"
export KUBELET_ROOT="${_inj_kubelet_root}"
export K8S_VERSION="${_inj_k8s_version}"
export REGISTRY_IP="${_inj_registry_ip}"
export REGISTRY_HOSTNAME="${_inj_registry_hn}"
export SSH_USER="${_inj_ssh_user}"
export SSH_PASSWORD="${_inj_ssh_password}"
export SSH_PORT="${_inj_ssh_port}"

# 内联日志函数（不依赖远程文件）
log_info()    { echo -e "\033[0;34m[INFO]\033[0m \$*"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m \$*"; }
log_warn()    { echo -e "\033[0;33m[WARN]\033[0m \$*"; }
log_error()   { echo -e "\033[0;31m[ERROR]\033[0m \$*" >&2; }

# 预解析的配置值快捷函数（避免远程依赖 yq）
get_k8s_soft() { echo "${_inj_k8s_soft}"; }
config_get() {
    local path="\$1"
    local default="\$2"
    case "\$path" in
        .paths.k8s_soft|.paths.k8s_home) echo "${_inj_k8s_soft}" ;;
        .env.kubelet_root)     echo "${_inj_kubelet_root}" ;;
        .cluster.k8s_version)  echo "${_inj_k8s_version}" ;;
        .registry.ip)          echo "${_inj_registry_ip}" ;;
        .registry.hostname)    echo "${_inj_registry_hn}" ;;
        .ssh.user)             echo "${_inj_ssh_user}" ;;
        .ssh.password)         echo "${_inj_ssh_password}" ;;
        .ssh.port)             echo "${_inj_ssh_port}" ;;
        *)                     echo "\$default" ;;
    esac
}
INJECT_EOF
    )

    # 拼接：注入头 + 脚本内容（跳过脚本中的 source 行），通过管道传给远程 bash
    {
        echo "$inject_header"
        # 跳过脚本中对本地库文件的 source 行（日志和配置函数已通过注入头提供）
        sed '/^source.*\/scripts\/lib\/logger\.sh$/d; /^source.*\/scripts\/lib\/config\.sh$/d' "$script_path"
    } | ssh -i "${ssh_key}" -p "${_SSH_PORT}" -o ConnectTimeout="${_SSH_TIMEOUT}" \
        -o StrictHostKeyChecking=no \
        "${_SSH_USER}@${target}" "$bash_command"
}

#===============================================================================
# 函数：exec_script_on_control_plane()
# 功能：在所有控制节点执行脚本并传递参数
# 参数：
#   $1 - 本地脚本路径
#   $2...$N - 传递给脚本的参数（可选，支持多个）
# 返回值：
#   0 - 所有节点执行成功
#   非 0 - 至少一个节点执行失败
#===============================================================================
exec_script_on_control_plane() {
    local script_path="$1"
    shift  # 移除脚本路径，剩余为参数

    local success=true

    log_info "在所有控制节点执行脚本: ${script_path}"

    # 获取所有控制节点 IP
    local control_plane_ips
    control_plane_ips=$(get_all_control_plane_ips)

    if [ -z "$control_plane_ips" ]; then
        log_error "未找到控制节点配置"
        return 1
    fi

    # 在每个控制节点执行脚本
    while IFS= read -r node_ip; do
        if ! exec_script_on_single_node "$node_ip" "$script_path" "$@"; then
            success=false
        fi
    done <<< "$control_plane_ips"

    if [ "$success" = true ]; then
        log_success "所有控制节点脚本执行成功"
        return 0
    else
        log_error "部分控制节点脚本执行失败"
        return 1
    fi
}

#===============================================================================
# 函数：exec_script_on_workers()
# 功能：在所有工作节点执行脚本并传递参数
# 参数：
#   $1 - 本地脚本路径
#   $2...$N - 传递给脚本的参数（可选，支持多个）
# 返回值：
#   0 - 所有节点执行成功
#   非 0 - 至少一个节点执行失败
#===============================================================================
exec_script_on_workers() {
    local script_path="$1"
    shift  # 移除脚本路径，剩余为参数

    local success=true

    log_info "在所有工作节点执行脚本: ${script_path}"

    # 获取所有工作节点 IP
    local worker_ips
    worker_ips=$(get_all_worker_ips)

    if [ -z "$worker_ips" ]; then
        log_error "未找到工作节点配置"
        return 1
    fi

    # 在每个工作节点执行脚本
    while IFS= read -r node_ip; do
        if ! exec_script_on_single_node "$node_ip" "$script_path" "$@"; then
            success=false
        fi
    done <<< "$worker_ips"

    if [ "$success" = true ]; then
        log_success "所有工作节点脚本执行成功"
        return 0
    else
        log_error "部分工作节点脚本执行失败"
        return 1
    fi
}

#===============================================================================
# 函数：exec_script_on_registry()
# 功能：在镜像仓库节点执行脚本并传递参数
# 参数：
#   $1 - 本地脚本路径
#   $2...$N - 传递给脚本的参数（可选，支持多个）
# 返回值：
#   0 - 执行成功
#   非 0 - 执行失败
#===============================================================================
exec_script_on_registry() {
    local script_path="$1"
    shift  # 移除脚本路径，剩余为参数

    log_info "在镜像仓库节点执行脚本: ${script_path}"

    # 获取镜像仓库节点 IP
    local registry_ip
    registry_ip=$(get_registry_ip)

    if [ -z "$registry_ip" ]; then
        log_error "未找到镜像仓库节点配置"
        return 1
    fi

    # 执行脚本
    if exec_script_on_single_node "$registry_ip" "$script_path" "$@"; then
        log_success "镜像仓库节点脚本执行成功"
        return 0
    else
        log_error "镜像仓库节点脚本执行失败"
        return 1
    fi
}

#===============================================================================
# 函数：exec_script_on_all_nodes()
# 功能：在所有节点（控制节点 + 工作节点）执行脚本并传递参数
# 参数：
#   $1 - 本地脚本路径
#   $2...$N - 传递给脚本的参数（可选，支持多个）
# 返回值：
#   0 - 所有节点执行成功
#   非 0 - 至少一个节点执行失败
#===============================================================================
exec_script_on_all_nodes() {
    local script_path="$1"
    shift  # 移除脚本路径，剩余为参数

    local success=true

    log_info "在所有节点执行脚本: ${script_path}"

    # 在控制节点执行
    if ! exec_script_on_control_plane "$script_path" "$@"; then
        success=false
    fi

    # 在工作节点执行
    if ! exec_script_on_workers "$script_path" "$@"; then
        success=false
    fi

    # 在镜像仓库节点执行（如果与控制节点不同）
    local registry_ip
    registry_ip=$(get_registry_ip)

    if [ -n "$registry_ip" ]; then
        # 检查是否与控制节点同机
        local found=false
        local control_plane_ips
        control_plane_ips=$(get_all_control_plane_ips)

        while IFS= read -r ip; do
            if [ "$ip" = "$registry_ip" ]; then
                found=true
                break
            fi
        done <<< "$control_plane_ips"

        # 如果不在控制节点，执行脚本
        if [ "$found" = false ]; then
            if ! exec_script_on_single_node "$registry_ip" "$script_path" "$@"; then
                success=false
            fi
        fi
    fi

    if [ "$success" = true ]; then
        log_success "所有节点脚本执行成功"
        return 0
    else
        log_error "部分节点脚本执行失败"
        return 1
    fi
}

#===============================================================================
# 函数：exec_remote_script()
# 功能：远程执行本地 shell 脚本的统一入口函数
# 参数：
#   $1 - 目标节点类型或 IP/hostname
#     - control_plane - 所有控制节点
#     - workers - 所有工作节点
#     - registry - 镜像仓库节点
#     - all - 所有节点
#     - 具体地址（IP 或 hostname）- 单个节点
#   $2 - 本地脚本路径
#   $3...$N - 传递给脚本的参数（可选，支持多个）
# 返回值：
#   0 - 所有节点执行成功
#   非 0 - 至少一个节点执行失败
# 说明：
#   - 这是远程脚本执行的主要入口函数
#   - 根据目标类型自动路由到相应的执行函数
#   - 支持脚本文件存在性和可执行性验证
#   - 提供统一的错误处理和日志记录
#   - 支持 hostname 和 IP 作为目标标识
#===============================================================================
exec_remote_script() {
    local target="$1"
    local script_path="$2"
    shift 2  # 移除前两个参数，剩余为脚本参数

    # 检查脚本文件是否存在
    if [ ! -f "$script_path" ]; then
        log_error "脚本文件不存在: ${script_path}"
        return 1
    fi

    # 根据目标类型路由到相应的执行函数
    case "$target" in
        control_plane)
            exec_script_on_control_plane "$script_path" "$@"
            ;;
        workers)
            exec_script_on_workers "$script_path" "$@"
            ;;
        registry)
            exec_script_on_registry "$script_path" "$@"
            ;;
        all)
            exec_script_on_all_nodes "$script_path" "$@"
            ;;
        *)
            # 判断是 IP 还是 hostname
            if [[ $target =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                # 是 IP，直接使用
                exec_script_on_single_node "$target" "$script_path" "$@"
            else
                # 是 hostname，先获取 IP
                local node_ip
                node_ip=$(get_node_ip "$target" 2>/dev/null)

                if [ -z "$node_ip" ] || [ "$node_ip" = "$target" ]; then
                    log_error "无法解析节点标识: ${target}"
                    return 1
                fi

                exec_script_on_single_node "$node_ip" "$script_path" "$@"
            fi
            ;;
    esac
}
