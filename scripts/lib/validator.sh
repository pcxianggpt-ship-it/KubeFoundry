#!/bin/bash

#===============================================================================
# 脚本名称：validator.sh
# 功能：验证函数库
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

#===============================================================================
# 函数：validate_ip()
# 功能：验证 IPv4 地址格式
# 参数：
#   $1 - IP 地址
# 返回值：
#   0 - 有效
#   1 - 无效
#===============================================================================
validate_ip() {
    local ip="$1"

    # 使用正则表达式验证 IPv4 格式
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # 检查每个段是否在 0-255 范围内
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi

    return 1
}

#===============================================================================
# 函数：validate_ipv6()
# 功能：验证 IPv6 地址格式
# 参数：
#   $1 - IPv6 地址
# 返回值：
#   0 - 有效
#   1 - 无效
#===============================================================================
validate_ipv6() {
    local ipv6="$1"

    # 简化的 IPv6 验证
    if [[ $ipv6 =~ ^([0-9a-fA-F]{0,4}:){7}[0-9a-fA-F]{0,4}$ ]] || \
       [[ $ipv6 =~ ^([0-9a-fA-F]{0,4}:){0,6}::([0-9a-fA-F]{0,4}:){0,5}[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    fi

    return 1
}

#===============================================================================
# 函数：validate_port()
# 功能：验证端口号有效性
# 参数：
#   $1 - 端口号
# 返回值：
#   0 - 有效
#   1 - 无效
#===============================================================================
validate_port() {
    local port="$1"

    # 检查是否为数字且在有效范围内（1-65535）
    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi

    return 1
}

#===============================================================================
# 函数：validate_command()
# 功能：验证命令是否存在
# 参数：
#   $1 - 命令名称
# 返回值：
#   0 - 命令存在
#   1 - 命令不存在
#===============================================================================
validate_command() {
    local command="$1"

    if command -v "$command" &>/dev/null; then
        return 0
    fi

    return 1
}

#===============================================================================
# 函数：validate_file()
# 功能：验证文件是否存在
# 参数：
#   $1 - 文件路径
# 返回值：
#   0 - 文件存在
#   1 - 文件不存在
#===============================================================================
validate_file() {
    local file_path="$1"

    if [ -f "$file_path" ]; then
        return 0
    fi

    return 1
}

#===============================================================================
# 函数：validate_directory()
# 功能：验证目录是否存在
# 参数：
#   $1 - 目录路径
# 返回值：
#   0 - 目录存在
#   1 - 目录不存在
#===============================================================================
validate_directory() {
    local dir_path="$1"

    if [ -d "$dir_path" ]; then
        return 0
    fi

    return 1
}

#===============================================================================
# 函数：validate_hostname()
# 功能：验证主机名格式
# 参数：
#   $1 - 主机名
# 返回值：
#   0 - 有效
#   1 - 无效
#===============================================================================
validate_hostname() {
    local hostname="$1"

    # 主机名规则：
    # - 长度不超过 63 个字符
    # - 只能包含字母、数字和连字符
    # - 不能以连字符开头或结尾
    # - 不能包含点号（FQDN 可以包含点号，这里简化处理）

    if [ ${#hostname} -eq 0 ] || [ ${#hostname} -gt 63 ]; then
        return 1
    fi

    if [[ $hostname =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        return 0
    fi

    return 1
}

#===============================================================================
# 函数：validate_ssh()
# 功能：验证 SSH 连接
# 参数：
#   $1 - 节点 IP 地址或 hostname
# 返回值：
#   0 - 连接成功
#   1 - 连接失败
#===============================================================================
validate_ssh() {
    local node="$1"

    if check_ssh_connection "$node"; then
        return 0
    fi

    return 1
}

#===============================================================================
# 函数：validate_node_config()
# 功能：验证节点配置的完整性
# 参数：
#   $1 - 节点 IP 地址
#   $2 - 节点类型（control_plane 或 workers）
# 返回值：
#   0 - 配置有效
#   1 - 配置无效
#===============================================================================
validate_node_config() {
    local node_ip="$1"
    local node_type="$2"

    # 验证 IP 格式
    if ! validate_ip "$node_ip"; then
        log_error "节点 IP 地址格式无效: ${node_ip}"
        return 1
    fi

    # 获取并验证 hostname
    local hostname
    hostname=$(get_node_hostname "$node_ip" 2>/dev/null)

    if [ -z "$hostname" ] || [ "$hostname" = "$node_ip" ]; then
        log_error "节点缺少主机名配置: ${node_ip}"
        return 1
    fi

    # 验证 hostname 格式
    if ! validate_hostname "$hostname"; then
        log_error "节点主机名格式无效: ${hostname}"
        return 1
    fi

    # 验证 SSH 连接
    if ! validate_ssh "$node_ip"; then
        log_error "节点 SSH 连接失败: ${hostname} (${node_ip})"
        return 1
    fi

    log_success "节点配置验证通过: ${hostname} (${node_ip})"
    return 0
}

#===============================================================================
# 函数：validate_all_nodes()
# 功能：验证所有节点配置
# 返回值：
#   0 - 所有节点配置有效
#   1 - 至少一个节点配置无效
#===============================================================================
validate_all_nodes() {
    local success=true

    log_info "验证所有节点配置..."

    # 验证控制节点
    local control_plane_ips
    control_plane_ips=$(get_all_control_plane_ips)

    while IFS= read -r node_ip; do
        if ! validate_node_config "$node_ip" "control_plane"; then
            success=false
        fi
    done <<< "$control_plane_ips"

    # 验证工作节点
    local worker_ips
    worker_ips=$(get_all_worker_ips)

    while IFS= read -r node_ip; do
        if ! validate_node_config "$node_ip" "workers"; then
            success=false
        fi
    done <<< "$worker_ips"

    # 验证镜像仓库节点（如果与控制节点不同）
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

        # 如果不在控制节点，验证配置
        if [ "$found" = false ]; then
            if ! validate_node_config "$registry_ip" "registry"; then
                success=false
            fi
        fi
    fi

    if [ "$success" = true ]; then
        log_success "所有节点配置验证通过"
        return 0
    else
        log_error "部分节点配置验证失败"
        return 1
    fi
}
