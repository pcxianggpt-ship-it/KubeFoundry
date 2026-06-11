#!/bin/bash

#===============================================================================
# 脚本名称：verify-32-install-nfs.sh
# 功能：验证NFS插件安装
# 执行机器：管理节点（本地执行）
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

log_info "===== 验证：NFS插件安装 ====="

# 1. nfs-server 服务运行（控制节点）
control_count=$(config_get_length '.control_plane')
for ((i = 0; i < control_count; i++)); do
    ip=$(config_get_node 'control_plane' "$i" 'ip')
    result=$(ssh_exec_capture "$ip" "systemctl is-active nfs-server 2>/dev/null")
    if [ "$result" = "active" ]; then
        check_pass "nfs-server 运行中: $(get_node_hostname "$ip")"
    else
        check_fail "nfs-server 未运行: $(get_node_hostname "$ip")"
    fi
done

# 2. helm 已安装
result=$(command -v helm 2>/dev/null)
if [ -n "$result" ]; then
    check_pass "helm 已安装"
else
    check_fail "helm 未安装"
fi

# 3. nfs-subdir-external-provisioner helm release
result=$(helm list 2>/dev/null | grep -c 'nfs-subdir-external-provisioner' || true)
if [ "$result" -ge 1 ]; then
    check_pass "nfs-subdir-external-provisioner helm release 存在"
else
    check_fail "nfs-subdir-external-provisioner helm release 未找到"
fi

# 等待nfs provisioner Pod就绪（最多120秒）
log_info "等待nfs provisioner Pod启动（最多120秒）..."
wait_count=0
while [ $wait_count -lt 12 ]; do
    running=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep 'nfs' | grep -c 'Running' || true)
    if [ "$running" -ge 1 ]; then
        log_success "nfs provisioner Pod已就绪 (${running} 个)"
        break
    fi
    log_info "nfs provisioner Pod启动中... (${running:-0} 个已Running)"
    sleep 10
    wait_count=$((wait_count + 1))
done

# 4. nfs provisioner Pod 运行
result=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep 'nfs' | grep -c 'Running' || true)
if [ "$result" -ge 1 ]; then
    check_pass "nfs provisioner Pod 运行中 (${result} 个)"
else
    check_fail "nfs provisioner Pod 未运行"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "NFS插件验证通过"
    exit 0
else
    log_error "NFS插件验证失败"
    exit 1
fi
