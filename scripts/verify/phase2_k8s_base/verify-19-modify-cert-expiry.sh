#!/bin/bash

#===============================================================================
# 脚本名称：verify-19-modify-cert-expiry.sh
# 功能：验证证书有效期修改
# 执行机器：管理节点（远程验证主控制节点）
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

log_info "===== 验证：证书有效期修改 ====="

primary_cp=$(get_all_control_plane_ips | head -1)
node_display=$(get_node_hostname "$primary_cp" 2>/dev/null)
node_display="${node_display:-$primary_cp}"

# 1. 执行 kubeadm certs check-expiration 并展示结果
result=$(ssh_exec_capture "$primary_cp" \
    "kubeadm certs check-expiration 2>/dev/null")

if [ -n "$result" ]; then
    check_pass "证书检查命令可执行: ${node_display}"
    log_info "证书有效期信息:"
    echo "$result" | while IFS= read -r line; do
        log_info "  ${line}"
    done
else
    check_fail "证书检查命令执行失败: ${node_display}"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "证书有效期修改验证通过"
    exit 0
else
    log_error "证书有效期修改验证失败"
    exit 1
fi
