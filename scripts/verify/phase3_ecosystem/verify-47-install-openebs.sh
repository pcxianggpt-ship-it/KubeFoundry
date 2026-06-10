#!/bin/bash

#===============================================================================
# 脚本名称：verify-47-install-openebs.sh
# 功能：验证OpenEBS存储系统安装
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

log_info "===== 验证：OpenEBS存储系统安装 ====="

primary_cp=$(get_all_control_plane_ips | head -1)

# 等待openebs Pod就绪（最多120秒）
log_info "等待openebs Pod启动（最多120秒）..."
wait_count=0
while [ $wait_count -lt 12 ]; do
    running=$(ssh_exec_capture "$primary_cp" \
        "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'openebs' | grep -c 'Running' || true" | tr -d '[:space:]')
    if [ "$running" -ge 2 ]; then
        log_success "openebs Pod已就绪 (${running} 个)"
        break
    fi
    log_info "openebs Pod启动中... (${running:-0} 个已Running)"
    sleep 10
    wait_count=$((wait_count + 1))
done

# 1. openebs 相关 Pod 存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'openebs' | wc -l")
if [ "$result" -ge 1 ]; then
    check_pass "openebs Pod 存在 (共 ${result} 个)"
else
    check_fail "openebs Pod 不存在"
fi

# 2. openebs Pod 运行状态
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'openebs' | grep -c 'Running' || true" | tr -d '[:space:]")
if [ "$result" -ge 2 ]; then
    check_pass "openebs Pod 运行中 (${result} 个)"
else
    check_fail "openebs Pod 未正常运行"
fi

# 3. openebs StorageClass 存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get sc --no-headers 2>/dev/null | grep -c 'openebs' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "openebs StorageClass 已部署 (${result} 个)"
else
    check_fail "openebs StorageClass 未找到"
fi

# 4. openebs Helm Release 存在
result=$(ssh_exec_capture "$primary_cp" \
    "helm list -n kubemate-system --no-headers 2>/dev/null | grep -c 'openebs' || true" | tr -d '[:space:]")
if [ "$result" -ge 1 ]; then
    check_pass "openebs Helm Release 已安装"
else
    check_fail "openebs Helm Release 未找到"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "OpenEBS安装验证通过"
    exit 0
else
    log_error "OpenEBS安装验证失败"
    exit 1
fi
