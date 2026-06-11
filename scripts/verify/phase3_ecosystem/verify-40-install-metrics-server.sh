#!/bin/bash

#===============================================================================
# 脚本名称：verify-40-install-metrics-server.sh
# 功能：验证Metrics Server安装
# 执行机器：管理节点（远程验证主控制节点）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

PASS=0
FAIL=0

check_pass() { PASS=$((PASS + 1)); log_success "[PASS] $1"; }
check_fail() { FAIL=$((FAIL + 1)); log_error  "[FAIL] $1"; }

log_info "===== 验证：Metrics Server安装 ====="


# 等待metrics-server Pod就绪（最多120秒）
log_info "等待metrics-server Pod启动（最多120秒）..."
wait_count=0
while [ $wait_count -lt 12 ]; do
    running=$(ssh_exec_capture "$primary_cp" \
        "kubectl get pods -n kube-system --no-headers 2>/dev/null | grep 'metrics-server' | grep -c 'Running' || true" | tr -d '[:space:]')
    if [ "$running" -ge 1 ]; then
        log_success "metrics-server Pod已就绪 (${running} 个)"
        break
    fi
    log_info "metrics-server Pod启动中... (${running:-0} 个已Running)"
    sleep 10
    wait_count=$((wait_count + 1))
done

# 1. metrics-server Pod 运行
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kube-system --no-headers 2>/dev/null | grep 'metrics-server' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "metrics-server Pod 运行中"
else
    check_fail "metrics-server Pod 未运行"
fi

# 2. kubectl top nodes 可用
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl top nodes --no-headers 2>/dev/null | wc -l")
if [ "$result" -ge 1 ]; then
    check_pass "kubectl top nodes 可用 (${result} 个节点)"
else
    check_fail "kubectl top nodes 不可用"
fi

# 3. kubectl top pods 可用
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl top pods -A --no-headers 2>/dev/null | wc -l")
if [ "$result" -ge 1 ]; then
    check_pass "kubectl top pods 可用"
else
    check_fail "kubectl top pods 不可用"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "Metrics Server验证通过"
    exit 0
else
    log_error "Metrics Server验证失败"
    exit 1
fi
