#!/bin/bash

#===============================================================================
# 脚本名称：01-check-tools.sh
# 功能：检查工具安装 + SSH 连接
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 加载必要的库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${SCRIPT_DIR}/../../lib/logger.sh"
source "${SCRIPT_DIR}/../../lib/config.sh"
source "${SCRIPT_DIR}/../../lib/ssh.sh"
source "${SCRIPT_DIR}/../../lib/validator.sh"

# 1. 工具检查与安装（复用 lib 中的逻辑）
bash "${SCRIPT_DIR}/../../lib/tools.sh"
if [ $? -ne 0 ]; then
    exit 1
fi

# 2. 检查 SSH 连接（到所有节点）
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

# 3. 生成检查报告
log_info ""
log_separator
log_info "前置检查报告"
log_separator
log_info "本地工具: ✓ 通过"
log_info "yq:      ✓ 通过"
log_info "helm:    ✓ 通过"
log_info "SSH 连接: ✓ 通过"
log_separator
log_success "前置检查全部通过，可以开始部署"
