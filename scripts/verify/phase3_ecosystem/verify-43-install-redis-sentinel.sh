#!/bin/bash

#===============================================================================
# 脚本名称：verify-43-install-redis-sentinel.sh
# 功能：验证Redis哨兵模式安装
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

log_info "===== 验证：Redis哨兵模式安装 ====="

primary_cp=$(get_all_control_plane_ips | head -1)

# 1. redis-sentinel 命名空间存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get ns redis-sentinel --no-headers 2>/dev/null | grep -c 'Active' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "redis-sentinel 命名空间存在"
else
    check_fail "redis-sentinel 命名空间不存在"
fi

# 2. redis Pod 运行
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n redis-sentinel --no-headers 2>/dev/null | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "redis Pod 运行中 (${result} 个)"
else
    check_fail "redis Pod 未运行"
fi

# 3. redis helm release 存在
result=$(ssh_exec_capture "$primary_cp" \
    "helm list -n redis-sentinel 2>/dev/null | grep -c 'redis' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "redis helm release 存在"
else
    check_fail "redis helm release 未找到"
fi

# 4. redis PV 已绑定
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pv --no-headers 2>/dev/null | grep 'redis' | grep -c 'Bound' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "redis PV 已绑定 (${result} 个)"
else
    check_fail "redis PV 未绑定"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "Redis哨兵模式验证通过"
    exit 0
else
    log_error "Redis哨兵模式验证失败"
    exit 1
fi
