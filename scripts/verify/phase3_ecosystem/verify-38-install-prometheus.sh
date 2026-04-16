#!/bin/bash

#===============================================================================
# 脚本名称：verify-38-install-prometheus.sh
# 功能：验证Prometheus监控系统安装
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

log_info "===== 验证：Prometheus监控系统安装 ====="

primary_cp=$(get_all_control_plane_ips | head -1)
MONITORING_NS="kubemate-monitoring-system"

# 1. 监控命名空间存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get ns ${MONITORING_NS} --no-headers 2>/dev/null | grep -c 'Active' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "${MONITORING_NS} 命名空间存在"
else
    check_fail "${MONITORING_NS} 命名空间不存在"
fi

# 等待prometheus-operator Pod就绪（最多120秒）
log_info "等待prometheus-operator Pod启动（最多120秒）..."
wait_count=0
while [ $wait_count -lt 12 ]; do
    running=$(ssh_exec_capture "$primary_cp" \
        "kubectl get pods -n ${MONITORING_NS} --no-headers 2>/dev/null | grep 'prometheus-operator' | grep -c 'Running' || true" | tr -d '[:space:]')
    if [ "$running" -ge 1 ]; then
        log_success "prometheus-operator Pod已就绪 (${running} 个)"
        break
    fi
    log_info "prometheus-operator Pod启动中... (${running:-0} 个已Running)"
    sleep 10
    wait_count=$((wait_count + 1))
done

# 2. prometheus-operator Pod 运行
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n ${MONITORING_NS} --no-headers 2>/dev/null | grep 'prometheus-operator' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "prometheus-operator 运行中"
else
    check_fail "prometheus-operator 未运行"
fi

# 3. prometheus Pod 运行
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n ${MONITORING_NS} --no-headers 2>/dev/null | grep 'prometheus-prometheus' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "prometheus 运行中 (${result} 个)"
else
    check_fail "prometheus 未运行"
fi

# 4. alertmanager Pod 运行
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n ${MONITORING_NS} --no-headers 2>/dev/null | grep 'alertmanager' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "alertmanager 运行中"
else
    check_fail "alertmanager 未运行"
fi

# 5. node-exporter 运行
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n ${MONITORING_NS} --no-headers 2>/dev/null | grep 'node-exporter' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "node-exporter 运行中 (${result} 个)"
else
    check_fail "node-exporter 未运行"
fi

# 6. kube-state-metrics 运行
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n ${MONITORING_NS} --no-headers 2>/dev/null | grep 'kube-state-metrics' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "kube-state-metrics 运行中"
else
    check_fail "kube-state-metrics 未运行"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "Prometheus监控系统验证通过"
    exit 0
else
    log_error "Prometheus监控系统验证失败"
    exit 1
fi
