#!/bin/bash

#===============================================================================
# 脚本名称：exec.sh
# 功能：批量执行命令函数库
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

#===============================================================================
# 函数：exec_on_node()
# 功能：在单个节点执行命令（底层实现函数）
# 参数：
#   $1 - 节点 IP 地址
#   $2 - 要执行的命令
# 返回值：
#   0 - 执行成功
#   非 0 - 执行失败
#===============================================================================
exec_on_node() {
    local node_ip="$1"
    local command="$2"

    # 获取节点信息
    local node_hostname
    node_hostname=$(get_node_hostname "$node_ip" 2>/dev/null)

    log_node "control_plane" "${node_hostname}" "执行命令: ${command}"

    # 执行 SSH 命令
    ssh_exec "$node_ip" "$command"
}

#===============================================================================
# 函数：exec_on_control_plane()
# 功能：在所有控制节点执行命令
# 参数：
#   $1 - 要执行的命令
# 返回值：
#   0 - 所有节点执行成功
#   非 0 - 至少一个节点执行失败
#===============================================================================
exec_on_control_plane() {
    local command="$1"
    local success=true

    log_info "在所有控制节点执行命令..."

    # 获取所有控制节点 IP
    local control_plane_ips
    control_plane_ips=$(get_all_control_plane_ips)

    if [ -z "$control_plane_ips" ]; then
        log_error "未找到控制节点配置"
        return 1
    fi

    # 在每个控制节点执行命令
    while IFS= read -r node_ip; do
        if ! exec_on_node "$node_ip" "$command"; then
            success=false
        fi
    done <<< "$control_plane_ips"

    if [ "$success" = true ]; then
        log_success "所有控制节点命令执行成功"
        return 0
    else
        log_error "部分控制节点命令执行失败"
        return 1
    fi
}

#===============================================================================
# 函数：exec_on_workers()
# 功能：在所有工作节点执行命令
# 参数：
#   $1 - 要执行的命令
# 返回值：
#   0 - 所有节点执行成功
#   非 0 - 至少一个节点执行失败
#===============================================================================
exec_on_workers() {
    local command="$1"
    local success=true

    log_info "在所有工作节点执行命令..."

    # 获取所有工作节点 IP
    local worker_ips
    worker_ips=$(get_all_worker_ips)

    if [ -z "$worker_ips" ]; then
        log_error "未找到工作节点配置"
        return 1
    fi

    # 在每个工作节点执行命令
    while IFS= read -r node_ip; do
        if ! exec_on_node "$node_ip" "$command"; then
            success=false
        fi
    done <<< "$worker_ips"

    if [ "$success" = true ]; then
        log_success "所有工作节点命令执行成功"
        return 0
    else
        log_error "部分工作节点命令执行失败"
        return 1
    fi
}

#===============================================================================
# 函数：exec_on_registry()
# 功能：在镜像仓库节点执行命令
# 参数：
#   $1 - 要执行的命令
# 返回值：
#   0 - 执行成功
#   非 0 - 执行失败
#===============================================================================
exec_on_registry() {
    local command="$1"

    log_info "在镜像仓库节点执行命令..."

    # 获取镜像仓库节点 IP
    local registry_ip
    registry_ip=$(get_registry_ip)

    if [ -z "$registry_ip" ]; then
        log_error "未找到镜像仓库节点配置"
        return 1
    fi

    # 执行命令
    if exec_on_node "$registry_ip" "$command"; then
        log_success "镜像仓库节点命令执行成功"
        return 0
    else
        log_error "镜像仓库节点命令执行失败"
        return 1
    fi
}

#===============================================================================
# 函数：exec_on_all_nodes()
# 功能：在所有节点（控制节点 + 工作节点）执行命令
# 参数：
#   $1 - 要执行的命令
# 返回值：
#   0 - 所有节点执行成功
#   非 0 - 至少一个节点执行失败
#===============================================================================
exec_on_all_nodes() {
    local command="$1"
    local success=true

    log_info "在所有节点执行命令..."

    # 在控制节点执行
    if ! exec_on_control_plane "$command"; then
        success=false
    fi

    # 在工作节点执行
    if ! exec_on_workers "$command"; then
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

        # 如果不在控制节点，执行命令
        if [ "$found" = false ]; then
            if ! exec_on_node "$registry_ip" "$command"; then
                success=false
            fi
        fi
    fi

    if [ "$success" = true ]; then
        log_success "所有节点命令执行成功"
        return 0
    else
        log_error "部分节点命令执行失败"
        return 1
    fi
}

#===============================================================================
# 函数：exec_on_single_node()
# 功能：在单个节点执行命令（支持 hostname 和 IP）
# 参数：
#   $1 - 节点标识（IP 地址或 hostname）
#   $2 - 要执行的命令
# 返回值：
#   0 - 执行成功
#   非 0 - 执行失败
#===============================================================================
exec_on_single_node() {
    local node_id="$1"
    local command="$2"

    log_info "在节点 ${node_id} 执行命令..."

    # 判断是 IP 还是 hostname
    if [[ $node_id =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # 是 IP，直接使用
        exec_on_node "$node_id" "$command"
    else
        # 是 hostname，先获取 IP
        local node_ip
        node_ip=$(get_node_ip "$node_id" 2>/dev/null)

        if [ -z "$node_ip" ] || [ "$node_ip" = "$node_id" ]; then
            log_error "无法解析节点标识: ${node_id}"
            return 1
        fi

        exec_on_node "$node_ip" "$command"
    fi
}
