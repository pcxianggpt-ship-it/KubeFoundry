#!/bin/bash

#===============================================================================
# 脚本名称：verify-12-setup-k8s-repo.sh
# 功能：验证K8S HTTP repo源客户端配置
# 执行机器：管理节点（远程验证工作节点）
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

log_info "===== 验证：K8S HTTP repo源客户端 ====="

# 1. 验证工作节点上的repo文件
worker_ips=$(get_all_worker_ips)
if [ -z "$worker_ips" ]; then
    log_info "无工作节点配置，跳过验证"
else
    while IFS= read -r node_ip; do
        [ -z "$node_ip" ] && continue
        node_display=$(get_node_hostname "$node_ip" 2>/dev/null)
        node_display="${node_display:-$node_ip}"

        # 检查repo文件存在
        result=$(ssh_exec_capture "$node_ip" \
            "test -f /etc/yum.repos.d/k8s-http.repo && echo 'OK' || echo 'MISSING'" 2>/dev/null)
        if [ "$result" = "OK" ]; then
            check_pass "k8s-http.repo 存在: ${node_display}"
        else
            check_fail "k8s-http.repo 不存在: ${node_display}"
        fi

        # 检查repo内容
        result=$(ssh_exec_capture "$node_ip" \
            "grep -c 'k8s-repo' /etc/yum.repos.d/k8s-http.repo 2>/dev/null || true" | tr -d '[:space:]')
        if [ "$result" -ge 1 ]; then
            check_pass "k8s-repo 段配置正确: ${node_display}"
        else
            check_fail "k8s-repo 段未找到: ${node_display}"
        fi

        # 验证yum缓存是否正常
        result=$(ssh_exec_capture "$node_ip" \
            "yum -q search kubelet 2>/dev/null | wc -l")
        if [ "$result" -gt 0 ]; then
            check_pass "yum 可搜索到 kubelet: ${node_display}"
        else
            check_fail "yum 无法搜索 kubelet: ${node_display}"
        fi
    done <<< "$worker_ips"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "K8S HTTP repo源验证通过"
    exit 0
else
    log_error "K8S HTTP repo源验证失败"
    exit 1
fi
