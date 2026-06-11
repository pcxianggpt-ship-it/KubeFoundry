#!/bin/bash

#===============================================================================
# 脚本名称：verify-36-install-traefik.sh
# 功能：验证Traefik网关安装（3.3版本）
# 执行机器：管理节点（远程验证主控制节点）
# 作者：KubeFoundry Team
# 版本：1.1.0
#===============================================================================

source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"
source "${PROJECT_ROOT}/scripts/lib/ssh.sh"

PASS=0
FAIL=0

check_pass() { PASS=$((PASS + 1)); log_success "[PASS] $1"; }
check_fail() { FAIL=$((FAIL + 1)); log_error  "[FAIL] $1"; }

log_info "===== 验证：Traefik网关安装（3.3版本） ====="

primary_cp=$(get_all_control_plane_ips | head -1)

# 等待traefik Pod就绪（最多120秒）
log_info "等待traefik Pod启动（最多120秒）..."
wait_count=0
while [ $wait_count -lt 12 ]; do
    running=$(ssh_exec_capture "$primary_cp" "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'traefik' | grep -v 'mesh' | grep -c 'Running' || true" | tr -d '[:space:]')
    if [ "$running" -ge 1 ]; then
        log_success "traefik Pod已就绪 (${running} 个)"
        break
    fi
    log_info "traefik Pod启动中... (${running:-0} 个已Running)"
    sleep 10
    wait_count=$((wait_count + 1))
done

# 1. traefik 相关 Pod 存在
result=$(ssh_exec_capture "$primary_cp" "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'traefik' | wc -l")
if [ "$result" -ge 1 ]; then
    check_pass "traefik Pod 存在 (共 ${result} 个)"
else
    check_fail "traefik Pod 不存在"
fi

# 2. traefik Pod 运行状态（排除 traefik-mesh 的 Pod）
result=$(ssh_exec_capture "$primary_cp" "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'traefik' | grep -v 'mesh' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "traefik Pod 运行中 (${result} 个)"
else
    check_fail "traefik Pod 未运行"
fi

# 3. traefik Service 存在
result=$(ssh_exec_capture "$primary_cp" "kubectl get svc -n kubemate-system --no-headers 2>/dev/null | grep -c 'traefik' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "traefik Service 已部署"
else
    check_fail "traefik Service 未找到"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "Traefik网关验证通过"
    exit 0
else
    log_error "Traefik网关验证失败"
    exit 1
fi
