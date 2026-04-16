#!/bin/bash

#===============================================================================
# 脚本名称：verify-15-environment-config.sh
# 功能：验证环境配置（swap/防火墙/sysctl/modules等）
# 执行机器：管理节点（远程验证所有节点）
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

log_info "===== 验证：环境配置 ====="

all_ips=$(get_all_node_ips)
while IFS= read -r node_ip; do
    [ -z "$node_ip" ] && continue
    node_display=$(get_node_hostname "$node_ip" 2>/dev/null)
    node_display="${node_display:-$node_ip}"

    # 1. swap已关闭
    result=$(ssh_exec_capture "$node_ip" "swapon --show 2>/dev/null | wc -l")
    if [ "$result" -eq 0 ]; then
        check_pass "swap 已关闭: ${node_display}"
    else
        check_fail "swap 未关闭: ${node_display}"
    fi

    # 2. fstab中无swap条目
    result=$(ssh_exec_capture "$node_ip" "grep -c swap /etc/fstab 2>/dev/null || true" | tr -d '[:space:]')
    if [ "$result" -eq 0 ]; then
        check_pass "fstab 已移除swap: ${node_display}"
    else
        check_fail "fstab 仍包含swap: ${node_display}"
    fi

    # 3. 防火墙已关闭
    result=$(ssh_exec_capture "$node_ip" "systemctl is-active firewalld 2>/dev/null")
    if [ "$result" = "inactive" ] || [ "$result" = "unknown" ]; then
        check_pass "防火墙已关闭: ${node_display}"
    else
        check_fail "防火墙仍在运行: ${node_display}"
    fi

    # 4. 内核模块 overlay 已加载
    result=$(ssh_exec_capture "$node_ip" "lsmod | grep -c '^overlay' 2>/dev/null || true" | tr -d '[:space:]')
    if [ "$result" -ge 1 ]; then
        check_pass "overlay 模块已加载: ${node_display}"
    else
        check_fail "overlay 模块未加载: ${node_display}"
    fi

    # 5. 内核模块 br_netfilter 已加载
    result=$(ssh_exec_capture "$node_ip" "lsmod | grep -c '^br_netfilter' 2>/dev/null || true" | tr -d '[:space:]')
    if [ "$result" -ge 1 ]; then
        check_pass "br_netfilter 模块已加载: ${node_display}"
    else
        check_fail "br_netfilter 模块未加载: ${node_display}"
    fi

    # 6. sysctl ip_forward 已开启
    result=$(ssh_exec_capture "$node_ip" "sysctl -n net.ipv4.ip_forward 2>/dev/null")
    if [ "$result" = "1" ]; then
        check_pass "ipv4.ip_forward=1: ${node_display}"
    else
        check_fail "ipv4.ip_forward 未开启 (值: ${result}): ${node_display}"
    fi

    # 7. sysctl bridge-nf-call-iptables 已开启
    result=$(ssh_exec_capture "$node_ip" "sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null")
    if [ "$result" = "1" ]; then
        check_pass "bridge-nf-call-iptables=1: ${node_display}"
    else
        check_fail "bridge-nf-call-iptables 未开启 (值: ${result}): ${node_display}"
    fi

    # 8. modules-load.d/k8s.conf 存在
    result=$(ssh_exec_capture "$node_ip" \
        "test -f /etc/modules-load.d/k8s.conf && echo 'OK' || echo 'MISSING'" 2>/dev/null)
    if [ "$result" = "OK" ]; then
        check_pass "/etc/modules-load.d/k8s.conf 存在: ${node_display}"
    else
        check_fail "/etc/modules-load.d/k8s.conf 不存在: ${node_display}"
    fi

    # 9. IPv6 转发已开启
    result=$(ssh_exec_capture "$node_ip" "sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null")
    if [ "$result" = "1" ]; then
        check_pass "ipv6.conf.all.forwarding=1: ${node_display}"
    else
        check_fail "IPv6 转发未开启 (值: ${result}): ${node_display}"
    fi

    # 10. open files 参数
    result=$(ssh_exec_capture "$node_ip" \
        "grep -c '65535' /etc/security/limits.conf 2>/dev/null || true" | tr -d '[:space:]')
    if [ "$result" -ge 1 ]; then
        check_pass "nofile 65535 已配置: ${node_display}"
    else
        check_fail "nofile 参数未配置: ${node_display}"
    fi
done <<< "$all_ips"

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "环境配置验证通过"
    exit 0
else
    log_error "环境配置验证失败"
    exit 1
fi
