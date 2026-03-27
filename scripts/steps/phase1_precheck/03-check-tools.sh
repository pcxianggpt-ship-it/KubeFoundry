#!/bin/bash

#===============================================================================
# 脚本名称：03-check-tools.sh
# 功能：检查必要工具安装
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 加载必要的库
source "$(dirname "$0")/../../lib/logger.sh"
source "$(dirname "$0")/../../lib/config.sh"
source "$(dirname "$0")/../../lib/ssh.sh"
source "$(dirname "$0")/../../lib/validator.sh"

# 1. 检查本地必要工具
log_info "检查本地必要工具..."

local_tools=("ssh" "scp" "rsync" "yq" "bc")

for tool in "${local_tools[@]}"; do
    if ! validate_command "$tool"; then
        log_error "本地缺少必要工具: $tool"
        log_info "请先安装: yum install -y $tool"
        exit 1
    fi
    log_debug "✓ $tool 已安装"
done

log_success "本地工具检查通过"

# 2. 检查配置文件中指定的工具路径
log_info "检查配置文件中指定的工具..."

# 检查 helm 工具
helm_path=$(config_get '.tools.helm_path' '/usr/local/bin/helm')
if [ -n "$helm_path" ] && [ ! -f "$helm_path" ]; then
    log_warn "helm 未找到: $helm_path"
fi

log_success "工具路径检查完成"

# 3. 检查 SSH 连接（到所有节点）
log_info "检查 SSH 连接..."
failed_nodes=()

# 检查控制节点
while IFS= read -r node_ip; do
    local node_hostname
    node_hostname=$(get_node_hostname "$node_ip" 2>/dev/null)

    if ! check_ssh_connection "$node_ip"; then
        log_error "无法连接到控制节点: ${node_hostname} (${node_ip})"
        failed_nodes+=("${node_hostname}")
    else
        log_debug "✓ 控制节点 ${node_hostname} (${node_ip}) SSH 连接正常"
    fi
done <<< "$(get_all_control_plane_ips)"

# 检查工作节点
while IFS= read -r node_ip; do
    local node_hostname
    node_hostname=$(get_node_hostname "$node_ip" 2>/dev/null)

    if ! check_ssh_connection "$node_ip"; then
        log_error "无法连接到工作节点: ${node_hostname} (${node_ip})"
        failed_nodes+=("${node_hostname}")
    else
        log_debug "✓ 工作节点 ${node_hostname} (${node_ip}) SSH 连接正常"
    fi
done <<< "$(get_all_worker_ips)"

# 检查镜像仓库节点（如果与控制节点不同）
local registry_ip
registry_ip=$(get_registry_ip)
if [ -n "$registry_ip" ]; then
    # 检查是否与控制节点同机
    local found=false
    while IFS= read -r ip; do
        if [ "$ip" = "$registry_ip" ]; then
            found=true
            break
        fi
    done <<< "$(get_all_control_plane_ips)"

    # 如果不在控制节点，检查连接
    if [ "$found" = false ]; then
        local registry_hostname
        registry_hostname=$(get_registry_hostname)

        if ! check_ssh_connection "$registry_ip"; then
            log_error "无法连接到镜像仓库节点: ${registry_hostname} (${registry_ip})"
            failed_nodes+=("${registry_hostname}")
        else
            log_debug "✓ 镜像仓库节点 ${registry_hostname} (${registry_ip}) SSH 连接正常"
        fi
    fi
fi

if [ ${#failed_nodes[@]} -gt 0 ]; then
    log_error "以下节点 SSH 连接失败:"
    printf '%s\n' "${failed_nodes[@]}"
    log_error "请检查:"
    log_error "1. 节点是否启动"
    log_error "2. SSH 服务是否运行"
    log_error "3. 网络连通性"
    log_error "4. SSH 密钥是否配置"
    log_error "5. /etc/hosts 是否配置了 hostname 解析（如果使用 hostname）"
    exit 1
fi

log_success "SSH 连接检查通过"

# 4. 生成检查报告
log_info ""
log_separator
log_info "前置检查报告"
log_separator
log_info "配置文件: ✓ 通过"
log_info "本地工具: ✓ 通过"
log_info "SSH 连接: ✓ 通过"
log_separator
log_success "前置检查全部通过，可以开始部署"
