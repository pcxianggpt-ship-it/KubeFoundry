#!/bin/bash

#===============================================================================
# 脚本名称：verify-41-setup-kubectl-permission.sh
# 功能：验证普通用户kubectl权限配置
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

log_info "===== 验证：普通用户kubectl权限 ====="

primary_cp=$(get_all_control_plane_ips | head -1)

# 1. appusr 用户存在
result=$(ssh_exec_capture "$primary_cp" "id appusr 2>/dev/null")
if [ -n "$result" ]; then
    check_pass "appusr 用户存在"
else
    check_fail "appusr 用户不存在"
fi

# 2. appusr 的 .kube 目录存在
result=$(ssh_exec_capture "$primary_cp" \
    "test -d /home/appusr/.kube && echo 'OK' || echo 'MISSING'" 2>/dev/null)
if [ "$result" = "OK" ]; then
    check_pass "appusr .kube 目录存在"
else
    check_fail "appusr .kube 目录不存在"
fi

# 3. appusr 的 kubeconfig 文件存在
result=$(ssh_exec_capture "$primary_cp" \
    "test -f /home/appusr/.kube/config && echo 'OK' || echo 'MISSING'" 2>/dev/null)
if [ "$result" = "OK" ]; then
    check_pass "appusr kubeconfig 文件存在"
else
    check_fail "appusr kubeconfig 文件不存在"
fi

# 4. kubeconfig 文件属主正确
result=$(ssh_exec_capture "$primary_cp" \
    "stat -c '%U:%G' /home/appusr/.kube/config 2>/dev/null")
if [ "$result" = "appusr:appusr" ]; then
    check_pass "kubeconfig 文件属主正确: appusr:appusr"
else
    check_fail "kubeconfig 文件属主不正确: ${result}"
fi

# 5. appusr 可执行 kubectl get nodes
result=$(ssh_exec_capture "$primary_cp" \
    "su - appusr -c 'kubectl get nodes --no-headers 2>/dev/null' | wc -l")
if [ "$result" -ge 1 ]; then
    check_pass "appusr 可执行 kubectl get nodes"
else
    check_fail "appusr 无法执行 kubectl"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "普通用户kubectl权限验证通过"
    exit 0
else
    log_error "普通用户kubectl权限验证失败"
    exit 1
fi
