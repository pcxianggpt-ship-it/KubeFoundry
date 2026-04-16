#!/bin/bash

#===============================================================================
# 脚本名称：verify-30-create-namespace.sh
# 功能：验证kubemate-system命名空间创建
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

log_info "===== 验证：命名空间创建 ====="

primary_cp=$(get_all_control_plane_ips | head -1)

# 1. kubemate-system 命名空间存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get ns kubemate-system --no-headers 2>/dev/null | grep -c 'Active' || echo 0")
if [ "$result" -ge 1 ]; then
    check_pass "kubemate-system 命名空间存在且为 Active"
else
    check_fail "kubemate-system 命名空间不存在或非 Active"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "命名空间创建验证通过"
    exit 0
else
    log_error "命名空间创建验证失败"
    exit 1
fi
