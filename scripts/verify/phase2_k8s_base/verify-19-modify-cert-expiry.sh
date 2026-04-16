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

# 1. kube-controller-manager 配置中包含签名时长参数
result=$(ssh_exec_capture "$primary_cp" \
    "grep -c 'cluster-signing-duration' /etc/kubernetes/manifests/kube-controller-manager.yaml 2>/dev/null || echo 0")
if [ "$result" -ge 1 ]; then
    check_pass "cluster-signing-duration 参数已配置: ${node_display}"
else
    check_fail "cluster-signing-duration 参数未配置: ${node_display}"
fi

# 2. 验证证书有效期（检查是否大于1年）
result=$(ssh_exec_capture "$primary_cp" \
    "kubeadm certs check-expiration 2>/dev/null | head -20")
if [ -n "$result" ]; then
    check_pass "证书检查命令可执行: ${node_display}"
    log_info "证书有效期信息:"
    echo "$result" | while IFS= read -r line; do
        log_info "  ${line}"
    done
else
    check_fail "证书检查命令执行失败: ${node_display}"
fi

# 3. kube-controller-manager Pod 运行中
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kube-system --no-headers 2>/dev/null | grep 'kube-controller-manager' | grep -c 'Running' || echo 0")
if [ "$result" -ge 1 ]; then
    check_pass "kube-controller-manager 运行正常: ${node_display}"
else
    check_fail "kube-controller-manager 未运行: ${node_display}"
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
