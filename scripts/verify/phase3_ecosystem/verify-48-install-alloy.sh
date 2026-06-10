#!/bin/bash

#===============================================================================
# 脚本名称：verify-48-install-alloy.sh
# 功能：验证Grafana Alloy可观测性代理安装
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

log_info "===== 验证：Grafana Alloy可观测性代理安装 ====="

primary_cp=$(get_all_control_plane_ips | head -1)

# 等待alloy Pod就绪（最多120秒）
log_info "等待alloy Pod启动（最多120秒）..."
wait_count=0
while [ $wait_count -lt 12 ]; do
    running=$(ssh_exec_capture "$primary_cp" \
        "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'alloy' | grep -c 'Running' || true" | tr -d '[:space:]')
    if [ "$running" -ge 1 ]; then
        log_success "alloy Pod已就绪 (${running} 个)"
        break
    fi
    log_info "alloy Pod启动中... (${running:-0} 个已Running)"
    sleep 10
    wait_count=$((wait_count + 1))
done

# 1. alloy 相关 Pod 存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'alloy' | wc -l")
if [ "$result" -ge 1 ]; then
    check_pass "alloy Pod 存在 (共 ${result} 个)"
else
    check_fail "alloy Pod 不存在"
fi

# 2. alloy Pod 运行状态
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'alloy' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "alloy Pod 运行中 (${result} 个)"
else
    check_fail "alloy Pod 未运行"
fi

# 3. alloy ConfigMap 存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get cm -n kubemate-system --no-headers 2>/dev/null | grep -c 'alloy' || true" | tr -d '[:space:]")
if [ "$result" -ge 1 ]; then
    check_pass "alloy ConfigMap 存在"
else
    check_fail "alloy ConfigMap 不存在"
fi

# 4. alloy Helm Release 存在
result=$(ssh_exec_capture "$primary_cp" \
    "helm list -n kubemate-system --no-headers 2>/dev/null | grep -c 'alloy' || true" | tr -d '[:space:]")
if [ "$result" -ge 1 ]; then
    check_pass "alloy Helm Release 已安装"
else
    check_fail "alloy Helm Release 未找到"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "Grafana Alloy安装验证通过"
    exit 0
else
    log_error "Grafana Alloy安装验证失败"
    exit 1
fi
