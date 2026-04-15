#!/bin/bash

#===============================================================================
# 脚本名称：02-validate-config.sh
# 功能：检查配置文件完整性
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 加载必要的库
source "$(dirname "$0")/../../lib/logger.sh"
source "$(dirname "$0")/../../lib/config.sh"
source "$(dirname "$0")/../../lib/validator.sh"

# 1. 检查配置文件是否存在
log_info "检查配置文件..."
if [ ! -f "config/cluster.yaml" ]; then
    log_error "配置文件不存在: config/cluster.yaml"
    exit 1
fi

log_success "配置文件检查通过"

# 2. 加载配置文件
log_info "加载配置文件..."
if ! load_config "config/cluster.yaml"; then
    log_error "配置文件加载失败"
    exit 1
fi

log_success "配置文件加载成功"

# 3. 验证必需的配置项
log_info "验证必需的配置项..."

# 验证集群配置
cluster_name=$(get_cluster_name)
if [ -z "$cluster_name" ]; then
    log_error "集群名称未配置"
    exit 1
fi

k8s_version=$(get_k8s_version)
if [ -z "$k8s_version" ]; then
    log_error "K8S 版本未配置"
    exit 1
fi

log_success "必需参数检查通过"

# 4. 验证节点配置（IP 和 hostname）
log_info "验证节点 IP 地址格式..."

# 验证控制节点
control_plane_count=$(config_get_length '.control_plane')

if [ "$control_plane_count" -eq 0 ]; then
    log_error "未找到控制节点配置"
    exit 1
fi

for ((i = 0; i < control_plane_count; i++)); do
    node_ip=$(config_get_node 'control_plane' "$i" 'ip')
    node_hostname=$(config_get_node 'control_plane' "$i" 'hostname')

    # 验证 IP 格式
    if ! validate_ip "$node_ip"; then
        log_error "控制节点 [$i] 的 IP 地址格式错误: $node_ip"
        exit 1
    fi

    # 验证 hostname 格式
    if ! validate_hostname "$node_hostname"; then
        log_error "控制节点 [$i] 的 hostname 格式错误: $node_hostname"
        exit 1
    fi

    log_debug "控制节点 [$i]: $node_hostname ($node_ip)"
done

log_success "控制节点 IP 和 hostname 验证通过"

# 验证工作节点
worker_count=$(config_get_length '.workers')

if [ "$worker_count" -eq 0 ]; then
    log_warn "未找到工作节点配置"
else
    for ((i = 0; i < worker_count; i++)); do
        node_ip=$(config_get_node 'workers' "$i" 'ip')
        node_hostname=$(config_get_node 'workers' "$i" 'hostname')

        # 验证 IP 格式
        if ! validate_ip "$node_ip"; then
            log_error "工作节点 [$i] 的 IP 地址格式错误: $node_ip"
            exit 1
        fi

        # 验证 hostname 格式
        if ! validate_hostname "$node_hostname"; then
            log_error "工作节点 [$i] 的 hostname 格式错误: $node_hostname"
            exit 1
        fi

        log_debug "工作节点 [$i]: $node_hostname ($node_ip)"
    done

    log_success "工作节点 IP 和 hostname 验证通过"
fi

# 验证镜像仓库节点
registry_hostname=$(get_registry_hostname)
registry_ip=$(get_registry_ip)

if [ -n "$registry_ip" ]; then
    # 验证 IP 格式
    if ! validate_ip "$registry_ip"; then
        log_error "镜像仓库节点的 IP 地址格式错误: $registry_ip"
        exit 1
    fi

    # 验证 hostname 格式
    if ! validate_hostname "$registry_hostname"; then
        log_error "镜像仓库节点的 hostname 格式错误: $registry_hostname"
        exit 1
    fi

    log_debug "镜像仓库节点: $registry_hostname ($registry_ip)"
    log_success "镜像仓库节点 IP 和 hostname 验证通过"
fi

# 5. 验证端口号有效性
log_info "验证端口号..."
api_server_port=$(config_get '.network.api_server_port' '6443')
if ! validate_port "$api_server_port"; then
    log_error "API Server 端口号无效: $api_server_port"
    exit 1
fi

log_success "端口号验证通过"

# 6. 验证文件路径可访问性
log_info "验证文件路径..."
repo_source=$(config_get '.paths.repo_source')
if [ -n "$repo_source" ] && [ ! -f "$repo_source" ]; then
    log_warn "YUM 源文件不存在: $repo_source"
fi

k8s_install_path=$(config_get '.paths.k8s_install')
if [ ! -d "$k8s_install_path" ]; then
    log_warn "K8S 安装目录不存在: $k8s_install_path"
fi

log_success "配置文件完整性检查完成"

# 7. 验证结果
log_success "配置文件完整性验证通过"
echo ""
log_info "验证摘要:"
log_info "  - 控制节点数量: $control_plane_count"
log_info "  - 工作节点数量: $worker_count"
log_info "  - 集群名称: $cluster_name"
log_info "  - K8S 版本: $k8s_version"

