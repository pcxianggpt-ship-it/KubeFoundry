#!/bin/bash

#===============================================================================
# 脚本名称：exec_script.sh
# 功能：批量执行脚本函数库
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

#===============================================================================
# 函数：exec_script_on_single_node()
# 功能：在单个节点上执行本地脚本（底层实现函数）
# 参数：
#   $1 - 节点 IP 地址
#   $2 - 本地脚本路径
#   $3...$N - 传递给脚本的参数（可选，支持多个）
# 返回值：
#   0 - 执行成功
#   非 0 - 执行失败
# 说明：
#   - 自动将脚本传输到远程节点的 /tmp/ 目录
#   - 执行失败时会保留远程脚本用于调试
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

    # 检查脚本是否可执行
    if [ ! -x "$script_path" ]; then
        log_warn "脚本文件不可执行: ${script_path}，尝试添加执行权限"
        chmod +x "$script_path"
    fi

    log_node "control_plane" "${node_hostname}" "执行脚本: ${script_path}"

    # 生成远程脚本路径
    local script_name
    script_name=$(basename "$script_path")
    local remote_script="/tmp/${script_name}.$$"

    # 传输脚本到远程节点
    log_debug "传输脚本到远程节点: ${node_hostname}:${remote_script}"
    if ! scp_exec "$script_path" "$remote_script" "$node_ip"; then
        log_error "脚本传输失败: ${script_path}"
        return 1
    fi

    # 在远程节点添加执行权限
    log_debug "添加脚本执行权限"
    ssh_exec "$node_ip" "chmod +x ${remote_script}"

    # 执行脚本
    log_debug "执行远程脚本，参数: $*"
    local result
    result=$(ssh_exec "$node_ip" "${remote_script} $*" 2>&1)
    local exit_code=$?

    # 打印脚本输出
    if [ -n "$result" ]; then
        echo "$result"
    fi

    # 清理远程脚本（成功时）
    if [ $exit_code -eq 0 ]; then
        log_debug "清理远程脚本: ${remote_script}"
        ssh_exec "$node_ip" "rm -f ${remote_script}"
    else
        log_error "脚本执行失败，保留远程脚本用于调试: ${remote_script}"
    fi

    return $exit_code
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
