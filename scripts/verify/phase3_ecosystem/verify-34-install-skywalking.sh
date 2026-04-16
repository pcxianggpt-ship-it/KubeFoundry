#!/bin/bash

#===============================================================================
# 脚本名称：verify-34-install-skywalking.sh
# 功能：验证Skywalking安装
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

log_info "===== 验证：Skywalking安装 ====="

primary_cp=$(get_all_control_plane_ips | head -1)

# 等待skywalking Pod就绪（最多300秒，OAP启动较慢）
log_info "等待skywalking Pod启动（最多300秒）..."
wait_count=0
while [ $wait_count -lt 30 ]; do
    running=$(ssh_exec_capture "$primary_cp" \
        "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'skywalking' | grep -c 'Running' || true" | tr -d '[:space:]')
    if [ "$running" -ge 1 ]; then
        log_success "skywalking Pod已就绪 (${running} 个)"
        break
    fi
    log_info "skywalking Pod启动中... (${running:-0} 个已Running)"
    sleep 10
    wait_count=$((wait_count + 1))
done

# 1. skywalking 相关 Pod 存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'skywalking' | wc -l")
if [ "$result" -ge 1 ]; then
    check_pass "skywalking Pod 存在 (共 ${result} 个)"
else
    check_fail "skywalking Pod 不存在"
fi

# 2. skywalking-oap Pod 运行
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'skywalking' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "skywalking Pod 运行中 (${result} 个)"
else
    check_fail "skywalking Pod 未运行（OAP 启动较慢，请稍后重试）"
fi

# 3. ES secret 可访问
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get secret es-skywalking-es-elastic-user -n kubemate-system --no-headers 2>/dev/null | grep -c 'es-skywalking' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "Elasticsearch 用户 Secret 存在"
else
    check_fail "Elasticsearch 用户 Secret 不存在"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "Skywalking安装验证通过"
    exit 0
else
    log_error "Skywalking安装验证失败"
    exit 1
fi
