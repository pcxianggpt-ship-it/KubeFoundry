#!/bin/bash

#===============================================================================
# 脚本名称：verify-44-setup-etcd-backup.sh
# 功能：验证ETCD定时备份配置
# 执行机器：管理节点（远程验证控制节点）
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

log_info "===== 验证：ETCD定时备份配置 ====="

primary_cp=$(get_all_control_plane_ips | head -1)
node_display=$(get_node_hostname "$primary_cp" 2>/dev/null)
node_display="${node_display:-$primary_cp}"

# 1. crontab 中包含 etcdbak 任务
result=$(ssh_exec_capture "$primary_cp" \
    "crontab -l 2>/dev/null | grep -c 'etcdbak' || echo 0")
if [ "$result" -ge 1 ]; then
    check_pass "crontab 包含 ETCD 备份任务: ${node_display}"
else
    check_fail "crontab 未找到 ETCD 备份任务: ${node_display}"
fi

# 2. 备份脚本存在
k8s_soft=$(get_k8s_soft)
result=$(ssh_exec_capture "$primary_cp" \
    "test -f ${k8s_soft}/05.crontab/etcdbak.sh && echo 'OK' || echo 'MISSING'" 2>/dev/null)
if [ "$result" = "OK" ]; then
    check_pass "ETCD 备份脚本存在: ${k8s_soft}/05.crontab/etcdbak.sh"
else
    check_fail "ETCD 备份脚本不存在"
fi

# 3. 备份目录存在
result=$(ssh_exec_capture "$primary_cp" \
    "test -d /data/crontab_task/etcdbak && echo 'OK' || echo 'MISSING'" 2>/dev/null)
if [ "$result" = "OK" ]; then
    check_pass "ETCD 备份日志目录存在: /data/crontab_task/etcdbak"
else
    check_fail "ETCD 备份日志目录不存在"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "ETCD定时备份验证通过"
    exit 0
else
    log_error "ETCD定时备份验证失败"
    exit 1
fi
