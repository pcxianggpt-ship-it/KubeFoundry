#!/bin/bash

#===============================================================================
# 脚本名称：verify-14-replace-kubeadm.sh
# 功能：验证kubeadm替换为支持100年证书版本
# 执行机器：管理节点（远程验证控制节点）
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

log_info "===== 验证：kubeadm替换 ====="

k8s_version=$(get_k8s_version)

# 1. 验证kubeadm二进制文件存在
control_ips=$(get_all_control_plane_ips)
while IFS= read -r node_ip; do
    [ -z "$node_ip" ] && continue
    node_display=$(get_node_hostname "$node_ip" 2>/dev/null)
    node_display="${node_display:-$node_ip}"

    # 检查kubeadm版本
    result=$(ssh_exec_capture "$node_ip" "kubeadm version -o short 2>/dev/null")
    if [ -n "$result" ]; then
        check_pass "kubeadm 版本: ${result} (${node_display})"
    else
        check_fail "kubeadm 版本获取失败: ${node_display}"
    fi

    # 检查备份文件存在
    result=$(ssh_exec_capture "$node_ip" \
        "test -f /tmp/k8s/kubeadm_bak && echo 'OK' || echo 'MISSING'" 2>/dev/null)
    if [ "$result" = "OK" ]; then
        check_pass "原始kubeadm备份存在: ${node_display}"
    else
        check_fail "原始kubeadm备份不存在: ${node_display}"
    fi

    # 验证kubeadm可执行
    result=$(ssh_exec_capture "$node_ip" \
        "kubeadm version 2>/dev/null | grep -c 'gitVersion' || echo 0")
    if [ "$result" -ge 1 ]; then
        check_pass "kubeadm 可正常执行: ${node_display}"
    else
        check_fail "kubeadm 执行异常: ${node_display}"
    fi
done <<< "$control_ips"

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "kubeadm替换验证通过"
    exit 0
else
    log_error "kubeadm替换验证失败"
    exit 1
fi
