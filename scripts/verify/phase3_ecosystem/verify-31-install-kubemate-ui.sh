#!/bin/bash

#===============================================================================
# 脚本名称：verify-31-install-kubemate-ui.sh
# 功能：验证kubemate管理界面安装
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

log_info "===== 验证：kubemate管理界面安装 ====="

primary_cp=$(get_all_control_plane_ips | head -1)

# 1. kubemate-system 命名空间中有 Pod
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | wc -l")
if [ "$result" -gt 0 ]; then
    check_pass "kubemate-system 中有 Pod (共 ${result} 个)"
else
    check_fail "kubemate-system 中无 Pod"
fi

# 2. 所有 Pod 状态为 Running
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep -cv 'Running' || true" | tr -d '[:space:]')
if [ "$result" -eq 0 ]; then
    check_pass "所有 kubemate Pod 状态为 Running"
else
    check_fail "存在非 Running 的 kubemate Pod (${result} 个)"
fi

# 3. NodePort 服务可访问（30088）
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get svc -n kubemate-system --no-headers 2>/dev/null | grep -c '30088' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "kubemate UI NodePort 服务存在 (30088)"
else
    check_fail "kubemate UI NodePort 服务未找到"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "kubemate管理界面验证通过"
    exit 0
else
    log_error "kubemate管理界面验证失败"
    exit 1
fi
