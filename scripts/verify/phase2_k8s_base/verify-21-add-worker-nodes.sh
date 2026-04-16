#!/bin/bash

#===============================================================================
# 脚本名称：verify-21-add-worker-nodes.sh
# 功能：验证工作节点加入集群
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

log_info "===== 验证：工作节点加入集群 ====="

primary_cp=$(get_all_control_plane_ips | head -1)
worker_count=$(config_get_length '.workers')

# 1. 所有工作节点都在集群中
for ((i = 0; i < worker_count; i++)); do
    expected_hn=$(config_get_node 'workers' "$i" 'hostname')

    result=$(ssh_exec_capture "$primary_cp" \
        "kubectl get nodes --no-headers 2>/dev/null | grep -c '${expected_hn}' || true" | tr -d '[:space:]')
    if [ "$result" -ge 1 ]; then
        check_pass "工作节点已加入集群: ${expected_hn}"
    else
        check_fail "工作节点未在集群中: ${expected_hn}"
    fi
done

# 2. 工作节点无 control-plane 角色（纯工作节点）
for ((i = 0; i < worker_count; i++)); do
    expected_hn=$(config_get_node 'workers' "$i" 'hostname')

    result=$(ssh_exec_capture "$primary_cp" \
        "kubectl get nodes --no-headers 2>/dev/null | grep '${expected_hn}' | grep -c 'control-plane' || true" | tr -d '[:space:]')
    if [ "$result" -eq 0 ]; then
        check_pass "工作节点无control-plane角色: ${expected_hn}"
    else
        check_fail "工作节点被标记为control-plane: ${expected_hn}"
    fi
done

# 3. 集群总节点数
total_expected=$((control_count + worker_count))
control_count=$(config_get_length '.control_plane')
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get nodes --no-headers 2>/dev/null | wc -l")
if [ "$result" -ge "$total_expected" ]; then
    check_pass "集群节点总数正确 (期望 >=${total_expected}, 实际 ${result})"
else
    check_fail "集群节点数不足 (期望 >=${total_expected}, 实际 ${result})"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "工作节点加入集群验证通过"
    exit 0
else
    log_error "工作节点加入集群验证失败"
    exit 1
fi
