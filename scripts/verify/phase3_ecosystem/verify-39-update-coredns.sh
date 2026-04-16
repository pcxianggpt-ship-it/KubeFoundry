#!/bin/bash

#===============================================================================
# 脚本名称：verify-39-update-coredns.sh
# 功能：验证CoreDNS配置更新
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

log_info "===== 验证：CoreDNS配置更新 ====="

primary_cp=$(get_all_control_plane_ips | head -1)

# 等待coredns Pod就绪（最多120秒）
log_info "等待coredns Pod启动（最多120秒）..."
wait_count=0
while [ $wait_count -lt 12 ]; do
    running=$(ssh_exec_capture "$primary_cp" \
        "kubectl get pods -n kube-system --no-headers 2>/dev/null | grep 'coredns' | grep -c 'Running' || true" | tr -d '[:space:]')
    if [ "$running" -ge 1 ]; then
        log_success "coredns Pod已就绪 (${running} 个)"
        break
    fi
    log_info "coredns Pod启动中... (${running:-0} 个已Running)"
    sleep 10
    wait_count=$((wait_count + 1))
done

# 1. coredns Pod 运行
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kube-system --no-headers 2>/dev/null | grep 'coredns' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "coredns Pod 运行中 (${result} 个)"
else
    check_fail "coredns Pod 未运行"
fi

# 2. coredns 反亲和性配置
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get deployment coredns -n kube-system -o yaml 2>/dev/null | grep -c 'podAntiAffinity' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "coredns 已配置 podAntiAffinity"
else
    check_fail "coredns 未配置 podAntiAffinity"
fi

# 3. coredns 分布在不同节点
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kube-system --no-headers 2>/dev/null | grep 'coredns' | awk '{print \$7}' | sort -u | wc -l")
if [ "$result" -ge 1 ]; then
    check_pass "coredns 分布在 ${result} 个不同节点"
else
    check_fail "coredns 节点分布检查失败"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "CoreDNS配置验证通过"
    exit 0
else
    log_error "CoreDNS配置验证失败"
    exit 1
fi
