#!/bin/bash

#===============================================================================
# 脚本名称：verify-11b-setup-hostname.sh
# 功能：验证主机名和hosts解析配置
# 执行机器：管理节点
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

log_info "===== 验证：主机名和hosts解析 ====="

HOSTS_BEGIN="# >>>KubeFoundry>>>"

# 1. 验证控制节点主机名
control_count=$(config_get_length '.control_plane')
for ((i = 0; i < control_count; i++)); do
    ip=$(config_get_node 'control_plane' "$i" 'ip')
    expected_hn=$(config_get_node 'control_plane' "$i" 'hostname')

    actual_hn=$(ssh_exec_capture "$ip" "hostname" 2>/dev/null)
    if [ "$actual_hn" = "$expected_hn" ]; then
        check_pass "控制节点[$i] 主机名正确: ${expected_hn}"
    else
        check_fail "控制节点[$i] 主机名不匹配 (期望: ${expected_hn}, 实际: ${actual_hn})"
    fi
done

# 2. 验证工作节点主机名
worker_count=$(config_get_length '.workers')
for ((i = 0; i < worker_count; i++)); do
    ip=$(config_get_node 'workers' "$i" 'ip')
    expected_hn=$(config_get_node 'workers' "$i" 'hostname')

    actual_hn=$(ssh_exec_capture "$ip" "hostname" 2>/dev/null)
    if [ "$actual_hn" = "$expected_hn" ]; then
        check_pass "工作节点[$i] 主机名正确: ${expected_hn}"
    else
        check_fail "工作节点[$i] 主机名不匹配 (期望: ${expected_hn}, 实际: ${actual_hn})"
    fi
done

# 3. 验证镜像仓库节点主机名
registry_ip=$(config_get '.registry.ip')
registry_hn=$(config_get '.registry.hostname')
if [ -n "$registry_ip" ]; then
    actual_hn=$(ssh_exec_capture "$registry_ip" "hostname" 2>/dev/null)
    if [ "$actual_hn" = "$registry_hn" ]; then
        check_pass "镜像仓库节点主机名正确: ${registry_hn}"
    else
        log_warn "[WARN] 镜像仓库节点主机名不匹配 (期望: ${registry_hn}, 实际: ${actual_hn})，可能与其他节点同机部署"
    fi
fi

# 4. 验证 /etc/hosts 中有 KubeFoundry 标记
all_ips=$(get_all_node_ips)
while IFS= read -r node_ip; do
    [ -z "$node_ip" ] && continue
    node_display=$(get_node_hostname "$node_ip" 2>/dev/null)
    node_display="${node_display:-$node_ip}"

    result=$(ssh_exec_capture "$node_ip" "grep -c '${HOSTS_BEGIN}' /etc/hosts 2>/dev/null || true" | tr -d '[:space:]')
    if [ "$result" -ge 1 ]; then
        check_pass "/etc/hosts 包含集群解析: ${node_display}"
    else
        check_fail "/etc/hosts 缺少集群解析标记: ${node_display}"
    fi
done <<< "$all_ips"

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "主机名和hosts解析验证通过"
    exit 0
else
    log_error "主机名和hosts解析验证失败"
    exit 1
fi
