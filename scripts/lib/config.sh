#!/bin/bash

#===============================================================================
# 脚本名称：config.sh
# 功能：配置文件解析函数库
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 配置文件路径（相对于项目根目录）
CONFIG_FILE="config/cluster.yaml"

#===============================================================================
# 函数：config_get()
# 功能：从配置文件中获取单个配置值
# 参数：
#   $1 - YAML 路径（如 .cluster.k8s_version）
#   $2 - 默认值（可选）
# 返回值：
#   配置值（字符串）
#===============================================================================
config_get() {
    local path="$1"
    local default="$2"

    # 检查配置文件是否存在
    if [ ! -f "${CONFIG_FILE}" ]; then
        log_error "配置文件不存在: ${CONFIG_FILE}"
        echo "$default"
        return 1
    fi

    # 使用 yq 获取配置值
    local value
    value=$(yq eval "${path}" "${CONFIG_FILE}" 2>/dev/null)

    # 处理空值或 null
    if [ "$value" = "null" ] || [ -z "$value" ]; then
        if [ -n "$default" ]; then
            echo "$default"
        else
            echo ""
        fi
    else
        echo "$value"
    fi
}

#===============================================================================
# 函数：config_get_array()
# 功能：从配置文件中获取数组
# 参数：
#   $1 - YAML 路径（如 .control_plane）
# 返回值：
#   数组（每行一个元素）
#===============================================================================
config_get_array() {
    local path="$1"

    # 检查配置文件是否存在
    if [ ! -f "${CONFIG_FILE}" ]; then
        log_error "配置文件不存在: ${CONFIG_FILE}"
        return 1
    fi

    # 使用 yq 获取数组
    yq eval "${path}[]" "${CONFIG_FILE}" 2>/dev/null
}

#===============================================================================
# 函数：config_get_length()
# 功能：获取数组长度
# 参数：
#   $1 - YAML 路径（如 .control_plane）
# 返回值：
#   数组长度（数字）
#===============================================================================
config_get_length() {
    local path="$1"

    # 检查配置文件是否存在
    if [ ! -f "${CONFIG_FILE}" ]; then
        log_error "配置文件不存在: ${CONFIG_FILE}"
        return 1
    fi

    # 使用 yq 获取数组长度
    local length
    length=$(yq eval "${path} | length" "${CONFIG_FILE}" 2>/dev/null)

    if [ -z "$length" ] || [ "$length" = "null" ]; then
        echo "0"
    else
        echo "$length"
    fi
}

#===============================================================================
# 函数：config_get_node()
# 功能：根据节点索引获取节点配置
# 参数：
#   $1 - 节点类型（control_plane 或 workers）
#   $2 - 节点索引（从 0 开始）
#   $3 - 配置字段（如 ip, hostname, ipv6）
# 返回值：
#   节点配置值
#===============================================================================
config_get_node() {
    local node_type="$1"
    local index="$2"
    local field="$3"

    local path=".${node_type}[${index}].${field}"

    config_get "$path"
}

#===============================================================================
# 函数：get_node_hostname()
# 功能：根据节点 IP 地址获取主机名
# 参数：
#   $1 - 节点 IP 地址
# 返回值：
#   节点主机名
#===============================================================================
get_node_hostname() {
    local node_ip="$1"

    # 在控制节点中查找
    local control_plane_count
    control_plane_count=$(config_get_length '.control_plane')

    for ((i = 0; i < control_plane_count; i++)); do
        local ip
        ip=$(config_get_node 'control_plane' "$i" 'ip')

        if [ "$ip" = "$node_ip" ]; then
            config_get_node 'control_plane' "$i" 'hostname'
            return 0
        fi
    done

    # 在工作节点中查找
    local worker_count
    worker_count=$(config_get_length '.workers')

    for ((i = 0; i < worker_count; i++)); do
        local ip
        ip=$(config_get_node 'workers' "$i" 'ip')

        if [ "$ip" = "$node_ip" ]; then
            config_get_node 'workers' "$i" 'hostname'
            return 0
        fi
    done

    # 检查镜像仓库节点
    local registry_ip
    registry_ip=$(config_get '.registry.ip')

    if [ "$registry_ip" = "$node_ip" ]; then
        config_get '.registry.hostname'
        return 0
    fi

    # 未找到，返回 IP
    echo "$node_ip"
    return 1
}

#===============================================================================
# 函数：get_node_ip()
# 功能：根据节点主机名获取 IP 地址
# 参数：
#   $1 - 节点主机名
# 返回值：
#   节点 IP 地址
#===============================================================================
get_node_ip() {
    local node_hostname="$1"

    # 在控制节点中查找
    local control_plane_count
    control_plane_count=$(config_get_length '.control_plane')

    for ((i = 0; i < control_plane_count; i++)); do
        local hostname
        hostname=$(config_get_node 'control_plane' "$i" 'hostname')

        if [ "$hostname" = "$node_hostname" ]; then
            config_get_node 'control_plane' "$i" 'ip'
            return 0
        fi
    done

    # 在工作节点中查找
    local worker_count
    worker_count=$(config_get_length '.workers')

    for ((i = 0; i < worker_count; i++)); do
        local hostname
        hostname=$(config_get_node 'workers' "$i" 'hostname')

        if [ "$hostname" = "$node_hostname" ]; then
            config_get_node 'workers' "$i" 'ip'
            return 0
        fi
    done

    # 检查镜像仓库节点
    local registry_hostname
    registry_hostname=$(config_get '.registry.hostname')

    if [ "$registry_hostname" = "$node_hostname" ]; then
        config_get '.registry.ip'
        return 0
    fi

    # 未找到，返回主机名
    echo "$node_hostname"
    return 1
}

#===============================================================================
# 函数：get_all_control_plane_ips()
# 功能：获取所有控制节点的 IP 地址列表
# 返回值：
#   IP 地址列表（每行一个）
#===============================================================================
get_all_control_plane_ips() {
    local control_plane_count
    control_plane_count=$(config_get_length '.control_plane')

    for ((i = 0; i < control_plane_count; i++)); do
        config_get_node 'control_plane' "$i" 'ip'
    done
}

#===============================================================================
# 函数：get_all_worker_ips()
# 功能：获取所有工作节点的 IP 地址列表
# 返回值：
#   IP 地址列表（每行一个）
#===============================================================================
get_all_worker_ips() {
    local worker_count
    worker_count=$(config_get_length '.workers')

    for ((i = 0; i < worker_count; i++)); do
        config_get_node 'workers' "$i" 'ip'
    done
}

#===============================================================================
# 函数：get_all_node_ips()
# 功能：获取所有节点的 IP 地址列表（控制节点 + 工作节点 + 镜像仓库）
# 返回值：
#   IP 地址列表（每行一个）
#===============================================================================
get_all_node_ips() {
    # 控制节点
    get_all_control_plane_ips

    # 工作节点
    get_all_worker_ips

    # 镜像仓库节点（如果不在控制节点或工作节点中）
    local registry_ip
    registry_ip=$(config_get '.registry.ip')

    # 检查 registry 是否与控制节点同机
    local found=false
    local control_plane_count
    control_plane_count=$(config_get_length '.control_plane')

    for ((i = 0; i < control_plane_count; i++)); do
        local ip
        ip=$(config_get_node 'control_plane' "$i" 'ip')

        if [ "$ip" = "$registry_ip" ]; then
            found=true
            break
        fi
    done

    # 如果不在控制节点，添加到列表
    if [ "$found" = false ]; then
        echo "$registry_ip"
    fi
}

#===============================================================================
# 函数：get_registry_ip()
# 功能：获取镜像仓库节点的 IP 地址
# 返回值：
#   镜像仓库 IP 地址
#===============================================================================
get_registry_ip() {
    config_get '.registry.ip'
}

#===============================================================================
# 函数：get_registry_hostname()
# 功能：获取镜像仓库节点的主机名
# 返回值：
#   镜像仓库主机名
#===============================================================================
get_registry_hostname() {
    config_get '.registry.hostname'
}

#===============================================================================
# 函数：load_config()
# 功能：加载并验证配置文件
# 参数：
#   $1 - 配置文件路径（可选，默认使用 CONFIG_FILE）
# 返回值：
#   0 - 成功
#   1 - 失败
#===============================================================================
load_config() {
    local config_path="${1:-$CONFIG_FILE}"

    # 检查配置文件是否存在
    if [ ! -f "$config_path" ]; then
        log_error "配置文件不存在: ${config_path}"
        return 1
    fi

    # 检查 yq 命令是否可用
    if ! command -v yq &>/dev/null; then
        log_error "缺少必要工具: yq"
        log_error "请安装 yq: https://github.com/mikefarah/yq"
        return 1
    fi

    # 验证配置文件格式
    if ! yq eval '.' "$config_path" >/dev/null 2>&1; then
        log_error "配置文件格式错误: ${config_path}"
        return 1
    fi

    log_success "配置文件加载成功: ${config_path}"

    # 更新全局配置文件路径
    CONFIG_FILE="$config_path"

    return 0
}

#===============================================================================
# 函数：get_cluster_name()
# 功能：获取集群名称
# 返回值：
#   集群名称
#===============================================================================
get_cluster_name() {
    config_get '.cluster.name' 'k8s-cluster'
}

#===============================================================================
# 函数：get_k8s_version()
# 功能：获取 Kubernetes 版本
# 返回值：
#   K8S 版本号
#===============================================================================
get_k8s_version() {
    config_get '.cluster.k8s_version' '1.29.0'
}

#===============================================================================
# 函数：get_pod_subnet()
# 功能：获取 Pod 网络网段
# 返回值：
#   Pod 网络网段
#===============================================================================
get_pod_subnet() {
    config_get '.cluster.pod_subnet' '10.244.0.0/16'
}

#===============================================================================
# 函数：get_service_subnet()
# 功能：获取 Service 网络网段
# 返回值：
#   Service 网络网段
#===============================================================================
get_service_subnet() {
    config_get '.cluster.service_subnet' '10.96.0.0/16'
}
