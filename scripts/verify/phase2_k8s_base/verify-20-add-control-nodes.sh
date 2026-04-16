#!/bin/bash

#===============================================================================
# 脚本名称：verify-20-add-control-nodes.sh
# 功能：验证控制节点加入集群
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

log_info "===== 验证：控制节点加入集群 ====="

primary_cp=$(get_all_control_plane_ips | head -1)
control_count=$(config_get_length '.control_plane')

# 1. 所有控制节点都在集群中
for ((i = 0; i < control_count; i++)); do
    expected_hn=$(config_get_node 'control_plane' "$i" 'hostname')

    result=$(ssh_exec_capture "$primary_cp" \
        "kubectl get nodes --no-headers 2>/dev/null | grep -c '${expected_hn}' || echo 0")
    if [ "$result" -ge 1 ]; then
        check_pass "控制节点已加入集群: ${expected_hn}"
    else
        check_fail "控制节点未在集群中: ${expected_hn}"
    fi
done

# 2. 控制节点角色标记
for ((i = 0; i < control_count; i++)); do
    expected_hn=$(config_get_node 'control_plane' "$i" 'hostname')

    result=$(ssh_exec_capture "$primary_cp" \
        "kubectl get nodes --no-headers 2>/dev/null | grep '${expected_hn}' | grep -c 'control-plane' || echo 0")
    if [ "$result" -ge 1 ]; then
        check_pass "控制节点角色标记正确: ${expected_hn}"
    else
        check_fail "控制节点角色标记缺失: ${expected_hn}"
    fi
done

# 3. etcd 集群成员
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c 'etcd' || echo 0")
if [ "$result" -ge "$control_count" ]; then
    check_pass "etcd Pod 数量正确 (期望 >=${control_count}, 实际 ${result})"
else
    check_fail "etcd Pod 数量不足 (期望 >=${control_count}, 实际 ${result})"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "控制节点加入集群验证通过"
    exit 0
else
    log_error "控制节点加入集群验证失败"
    exit 1
fi
