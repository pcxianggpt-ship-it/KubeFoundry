#!/bin/bash

#===============================================================================
# 脚本名称：verify-37-install-traefik-mesh.sh
# 功能：验证Traefik Mesh服务网格安装
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

log_info "===== 验证：Traefik Mesh服务网格安装 ====="


# 等待traefik-mesh Pod就绪（最多120秒）
log_info "等待traefik-mesh Pod启动（最多120秒）..."
wait_count=0
while [ $wait_count -lt 12 ]; do
    running=$(ssh_exec_capture "$primary_cp" \
        "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'traefik-mesh' | grep -c 'Running' || true" | tr -d '[:space:]')
    if [ "$running" -ge 1 ]; then
        log_success "traefik-mesh Pod已就绪 (${running} 个)"
        break
    fi
    log_info "traefik-mesh Pod启动中... (${running:-0} 个已Running)"
    sleep 10
    wait_count=$((wait_count + 1))
done

# 1. traefik-mesh 相关 Pod 存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'traefik-mesh' | wc -l")
if [ "$result" -ge 1 ]; then
    check_pass "traefik-mesh Pod 存在 (共 ${result} 个)"
else
    check_fail "traefik-mesh Pod 不存在"
fi

# 2. traefik-mesh Pod 运行状态
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'traefik-mesh' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "traefik-mesh Pod 运行中 (${result} 个)"
else
    check_fail "traefik-mesh Pod 未运行"
fi

# 3. traefik-mesh controller 运行
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'traefik-mesh-controller' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "traefik-mesh-controller 运行中"
else
    check_fail "traefik-mesh-controller 未运行"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "Traefik Mesh验证通过"
    exit 0
else
    log_error "Traefik Mesh验证失败"
    exit 1
fi
