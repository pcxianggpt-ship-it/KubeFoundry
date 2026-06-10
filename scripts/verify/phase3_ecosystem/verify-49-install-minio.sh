#!/bin/bash

#===============================================================================
# 脚本名称：verify-49-install-minio.sh
# 功能：验证MinIO对象存储系统安装
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

log_info "===== 验证：MinIO对象存储系统安装 ====="

primary_cp=$(get_all_control_plane_ips | head -1)

# 等待minio-operator Pod就绪（最多180秒）
log_info "等待minio-operator Pod启动（最多180秒）..."
wait_count=0
while [ $wait_count -lt 18 ]; do
    running=$(ssh_exec_capture "$primary_cp" \
        "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'minio' | grep -c 'Running' || true" | tr -d '[:space:]')
    if [ "$running" -ge 1 ]; then
        log_success "minio-operator Pod已就绪 (${running} 个)"
        break
    fi
    log_info "minio-operator Pod启动中... (${running:-0} 个已Running)"
    sleep 10
    wait_count=$((wait_count + 1))
done

# 1. minio-operator 相关 Pod 存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'minio' | wc -l")
if [ "$result" -ge 1 ]; then
    check_pass "minio-operator Pod 存在 (共 ${result} 个)"
else
    check_fail "minio-operator Pod 不存在"
fi

# 2. minio-operator Pod 运行状态
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kubemate-system --no-headers 2>/dev/null | grep 'minio-operator' | grep -c 'Running' || true" | tr -d '[:space:]")
if [ "$result" -ge 1 ]; then
    check_pass "minio-operator Pod 运行中 (${result} 个)"
else
    check_fail "minio-operator Pod 未运行"
fi

# 3. minio-console Deployment 存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get deployment -n kubemate-system --no-headers 2>/dev/null | grep -c 'console' || true" | tr -d '[:space:]")
if [ "$result" -ge 1 ]; then
    check_pass "minio-console Deployment 已部署"
else
    check_fail "minio-console Deployment 未找到"
fi

# 4. minio Secret 存在（console-sa-secret）
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get secret -n kubemate-system --no-headers 2>/dev/null | grep -c 'console-sa-secret' || true" | tr -d '[:space:]")
if [ "$result" -ge 1 ]; then
    check_pass "minio-console Secret 存在"
else
    check_fail "minio-console Secret 不存在"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "MinIO安装验证通过"
    exit 0
else
    log_error "MinIO安装验证失败"
    exit 1
fi
