#!/bin/bash

#===============================================================================
# 脚本名称：verify-13-install-k8s-deps.sh
# 功能：验证K8S依赖包安装
# 执行机器：管理节点（远程验证所有节点）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"
source "${PROJECT_ROOT}/scripts/lib/ssh.sh"

PASS=0
FAIL=0

check_pass() { PASS=$((PASS + 1)); log_success "[PASS] $1"; }
check_fail() { FAIL=$((FAIL + 1)); log_error  "[FAIL] $1"; }

log_info "===== 验证：K8S依赖包安装 ====="

REQUIRED_COMMANDS="kubeadm kubectl kubelet crictl"

# 逐节点验证
all_ips=$(get_all_node_ips)
while IFS= read -r node_ip; do
    [ -z "$node_ip" ] && continue
    node_display=$(get_node_hostname "$node_ip" 2>/dev/null)
    node_display="${node_display:-$node_ip}"

    for cmd in $REQUIRED_COMMANDS; do
        result=$(ssh_exec_capture "$node_ip" "command -v $cmd 2>/dev/null")
        if [ -n "$result" ]; then
            check_pass "${cmd} 已安装: ${node_display}"
        else
            check_fail "${cmd} 未安装: ${node_display}"
        fi
    done

    # 验证kubelet版本
    result=$(ssh_exec_capture "$node_ip" "kubelet --version 2>/dev/null")
    if [ -n "$result" ]; then
        check_pass "kubelet 版本: ${result} (${node_display})"
    else
        check_fail "kubelet 版本获取失败: ${node_display}"
    fi

    # 验证kubelet是否已启用
    result=$(ssh_exec_capture "$node_ip" "systemctl is-enabled kubelet 2>/dev/null" | tr -d '[:space:]')
    if [ "$result" = "enabled" ]; then
        check_pass "kubelet 已启用: ${node_display}"
    else
        check_fail "kubelet 未启用: ${node_display}"
    fi
done <<< "$all_ips"

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "K8S依赖包安装验证通过"
    exit 0
else
    log_error "K8S依赖包安装验证失败"
    exit 1
fi
