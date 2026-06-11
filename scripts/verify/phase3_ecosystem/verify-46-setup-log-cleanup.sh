#!/bin/bash

#===============================================================================
# 脚本名称：verify-46-setup-log-cleanup.sh
# 功能：验证应用日志定时清理配置
# 执行机器：管理节点（远程验证工作节点）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

PASS=0
FAIL=0

check_pass() { PASS=$((PASS + 1)); log_success "[PASS] $1"; }
check_fail() { FAIL=$((FAIL + 1)); log_error  "[FAIL] $1"; }

log_info "===== 验证：应用日志定时清理配置 ====="

worker_ips=$(get_all_worker_ips)
k8s_soft=$(get_k8s_soft)

if [ -z "$worker_ips" ]; then
    log_info "无工作节点配置，跳过验证"
else
    while IFS= read -r node_ip; do
        [ -z "$node_ip" ] && continue
        node_display=$(get_node_hostname "$node_ip" 2>/dev/null)
        node_display="${node_display:-$node_ip}"

        # 1. crontab 中包含 logback 任务
        result=$(ssh_exec_capture "$node_ip" \
            "crontab -l 2>/dev/null | grep -c 'logback' || true" | tr -d '[:space:]')
        if [ "$result" -ge 1 ]; then
            check_pass "crontab 包含日志清理任务: ${node_display}"
        else
            check_fail "crontab 未找到日志清理任务: ${node_display}"
        fi

        # 2. 清理脚本存在
        result=$(ssh_exec_capture "$node_ip" \
            "test -f ${k8s_soft}/05.crontab/logback.sh && echo 'OK' || echo 'MISSING'" 2>/dev/null)
        if [ "$result" = "OK" ]; then
            check_pass "日志清理脚本存在: ${node_display}"
        else
            check_fail "日志清理脚本不存在: ${node_display}"
        fi
    done <<< "$worker_ips"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "应用日志定时清理验证通过"
    exit 0
else
    log_error "应用日志定时清理验证失败"
    exit 1
fi
