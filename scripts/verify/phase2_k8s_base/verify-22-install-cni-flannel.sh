#!/bin/bash

#===============================================================================
# 脚本名称：verify-22-install-cni-flannel.sh
# 功能：验证CNI插件Flannel安装
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

log_info "===== 验证：CNI插件Flannel ====="

primary_cp=$(get_all_control_plane_ips | head -1)
node_display=$(get_node_hostname "$primary_cp" 2>/dev/null)
node_display="${node_display:-$primary_cp}"

# 1. flannel 命名空间存在
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get ns kube-flannel --no-headers 2>/dev/null | grep -c 'Active' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "kube-flannel 命名空间存在"
else
    check_fail "kube-flannel 命名空间不存在"
fi

# 2. flannel DaemonSet Pod 运行
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep 'kube-flannel-ds' | grep -c 'Running' || true" | tr -d '[:space:]')
all_node_count=$(( $(config_get_length '.control_plane') + $(config_get_length '.workers') ))
if [ "$result" -ge "$all_node_count" ]; then
    check_pass "flannel Pod 全部Running (${result}/${all_node_count})"
else
    check_fail "flannel Pod 运行不足 (${result}/${all_node_count})"
fi

# 3. 所有节点状态为 Ready
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get nodes --no-headers 2>/dev/null | grep -c 'NotReady' || true" | tr -d '[:space:]')
if [ "$result" -eq 0 ]; then
    check_pass "所有节点状态为 Ready"
else
    check_fail "存在 NotReady 节点 (${result} 个)"
fi

# 4. coredns Pod 状态
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kube-system --no-headers 2>/dev/null | grep 'coredns' | grep -c 'Running' || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "coredns Pod 运行正常 (${result} 个)"
else
    check_fail "coredns Pod 未运行"
fi

# 5. ClusterCIDR 配置（flannel）
pod_subnet=$(get_pod_subnet)
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2>/dev/null")
if [ -n "$result" ]; then
    check_pass "PodCIDR 已分配: ${result}"
else
    check_fail "PodCIDR 未分配"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "Flannel CNI安装验证通过"
    exit 0
else
    log_error "Flannel CNI安装验证失败"
    exit 1
fi
