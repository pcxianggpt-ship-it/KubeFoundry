#!/bin/bash

#===============================================================================
# 脚本名称：verify-16-install-containerd.sh
# 功能：验证containerd安装
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

log_info "===== 验证：containerd安装 ====="

all_ips=$(get_all_node_ips)
while IFS= read -r node_ip; do
    [ -z "$node_ip" ] && continue
    node_display=$(get_node_hostname "$node_ip" 2>/dev/null)
    node_display="${node_display:-$node_ip}"

    # 1. containerd 服务运行中
    result=$(ssh_exec_capture "$node_ip" "systemctl is-active containerd 2>/dev/null")
    if [ "$result" = "active" ]; then
        check_pass "containerd 服务运行中: ${node_display}"
    else
        check_fail "containerd 服务未运行 (状态: ${result}): ${node_display}"
    fi

    # 2. containerd 开机自启
    result=$(ssh_exec_capture "$node_ip" "systemctl is-enabled containerd 2>/dev/null")
    if [ "$result" = "enabled" ]; then
        check_pass "containerd 已设置开机自启: ${node_display}"
    else
        check_fail "containerd 未设置开机自启: ${node_display}"
    fi

    # 3. containerd 配置文件存在
    result=$(ssh_exec_capture "$node_ip" \
        "test -f /etc/containerd/config.toml && echo 'OK' || echo 'MISSING'" 2>/dev/null)
    if [ "$result" = "OK" ]; then
        check_pass "containerd 配置文件存在: ${node_display}"
    else
        check_fail "containerd 配置文件不存在: ${node_display}"
    fi

    # 4. runc 已安装
    result=$(ssh_exec_capture "$node_ip" "command -v runc 2>/dev/null")
    if [ -n "$result" ]; then
        check_pass "runc 已安装: ${node_display}"
    else
        check_fail "runc 未安装: ${node_display}"
    fi

    # 5. CNI 插件已安装
    result=$(ssh_exec_capture "$node_ip" \
        "test -d /opt/cni/bin && ls /opt/cni/bin | wc -l" 2>/dev/null)
    if [ "$result" -gt 0 ] 2>/dev/null; then
        check_pass "CNI 插件已安装 (${result} 个): ${node_display}"
    else
        check_fail "CNI 插件未安装: ${node_display}"
    fi

    # 6. buildkit 服务
    result=$(ssh_exec_capture "$node_ip" "systemctl is-active buildkit 2>/dev/null")
    if [ "$result" = "active" ]; then
        check_pass "buildkit 服务运行中: ${node_display}"
    else
        check_fail "buildkit 服务未运行: ${node_display}"
    fi

    # 7. nerdctl 已安装
    result=$(ssh_exec_capture "$node_ip" "command -v nerdctl 2>/dev/null")
    if [ -n "$result" ]; then
        check_pass "nerdctl 已安装: ${node_display}"
    else
        check_fail "nerdctl 未安装: ${node_display}"
    fi

    # 8. 镜像仓库 hosts.toml 配置
    result=$(ssh_exec_capture "$node_ip" \
        "test -f /etc/containerd/certs.d/registry:5000/hosts.toml && echo 'OK' || echo 'MISSING'" 2>/dev/null)
    if [ "$result" = "OK" ]; then
        check_pass "镜像仓库 hosts.toml 配置存在: ${node_display}"
    else
        check_fail "镜像仓库 hosts.toml 配置不存在: ${node_display}"
    fi
done <<< "$all_ips"

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "containerd安装验证通过"
    exit 0
else
    log_error "containerd安装验证失败"
    exit 1
fi
