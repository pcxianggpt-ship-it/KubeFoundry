#!/bin/bash

#===============================================================================
# 脚本名称：01-init-config.sh
# 功能：初始化参数配置
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 加载必要的库
source "$(dirname "$0")/../../lib/logger.sh"
source "$(dirname "$0")/../../lib/config.sh"

# 1. 加载配置文件
log_info "加载配置文件..."
if ! load_config "config/cluster.yaml"; then
    log_error "配置文件加载失败"
    exit 1
fi

log_success "配置文件加载成功"

# 2. 验证配置文件格式
log_info "验证配置文件格式..."

# 检查必需的配置项
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

log_success "配置文件格式验证通过"

# 3. 初始化全局变量
log_info "初始化全局变量..."

# 从配置文件读取参数
pod_subnet=$(get_pod_subnet)

service_subnet=$(get_service_subnet)

control_node_count=$(config_get_length '.control_plane')

worker_node_count=$(config_get_length '.workers')

log_success "全局变量初始化完成"

# 4. 显示配置摘要
log_separator
log_info "K8S 集群部署配置"
log_separator
log_info "K8S 版本: ${k8s_version}"
log_info "Pod 网段: ${pod_subnet}"
log_info "Service 网段: ${service_subnet}"
log_info "控制节点数量: ${control_node_count}"
log_info "工作节点数量: ${worker_node_count}"
log_separator

# 5. 验证安装结果
# 检查配置文件是否成功加载
if [ -z "${k8s_version}" ]; then
    log_error "配置文件加载失败"
    exit 1
fi

log_success "配置参数初始化完成"
