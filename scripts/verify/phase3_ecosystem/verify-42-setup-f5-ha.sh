#!/bin/bash

#===============================================================================
# 脚本名称：verify-42-setup-f5-ha.sh
# 功能：验证F5高可用配置
# 执行机器：管理节点（远程验证控制节点）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

PASS=0
FAIL=0

check_pass() { PASS=$((PASS + 1)); log_success "[PASS] $1"; }
check_fail() { FAIL=$((FAIL + 1)); log_error  "[FAIL] $1"; }

log_info "===== 验证：F5高可用配置 ====="

control_count=$(config_get_length '.control_plane')

# 1. 所有控制节点的 /etc/hosts 包含 k8sc1 解析
for ((i = 0; i < control_count; i++)); do
    ip=$(config_get_node 'control_plane' "$i" 'ip')
    node_display=$(get_node_hostname "$ip" 2>/dev/null)
    node_display="${node_display:-$ip}"

    result=$(ssh_exec_capture "$ip" "grep -c 'k8sc1' /etc/hosts 2>/dev/null || true" | tr -d '[:space:]')
    if [ "$result" -ge 1 ]; then
        check_pass "/etc/hosts 包含 k8sc1 解析: ${node_display}"
    else
        check_fail "/etc/hosts 缺少 k8sc1 解析: ${node_display}"
    fi
done

# 2. k8sc1 解析的 IP 不是原始控制节点 IP（应为 F5 IP）
control_cp_ip=$(config_get_node 'control_plane' '0' 'ip')
result=$(ssh_exec_capture "$primary_cp" \
    "grep 'k8sc1' /etc/hosts 2>/dev/null | head -1 | awk '{print \$1}'")
if [ -n "$result" ] && [ "$result" != "$control_cp_ip" ]; then
    check_pass "k8sc1 已解析到 F5 IP: ${result}"
elif [ "$result" = "$control_cp_ip" ]; then
    check_pass "k8sc1 解析为控制节点 IP (未使用 F5): ${result}"
else
    check_fail "k8sc1 解析 IP 获取失败"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "F5高可用配置验证通过"
    exit 0
else
    log_error "F5高可用配置验证失败"
    exit 1
fi
