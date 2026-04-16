#!/bin/bash

#===============================================================================
# 脚本名称：verify-11-setup-ssh-login.sh
# 功能：验证SSH免密登录配置
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

log_info "===== 验证：SSH免密登录配置 ====="

# 1. 验证SSH密钥对存在
if [ -f "$HOME/.ssh/id_rsa" ] && [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    check_pass "SSH密钥对存在: ~/.ssh/id_rsa"
else
    check_fail "SSH密钥对不存在"
fi

# 2. 验证sshpass已安装
if command -v sshpass &>/dev/null; then
    check_pass "sshpass 已安装"
else
    check_fail "sshpass 未安装"
fi

# 3. 逐节点验证免密登录
all_ips=$(get_all_node_ips)
ssh_port=$(config_get '.ssh.port' '22')
ssh_user=$(config_get '.ssh.user' 'root')

while IFS= read -r node_ip; do
    [ -z "$node_ip" ] && continue

    node_hostname=$(get_node_hostname "$node_ip" 2>/dev/null)
    node_display="${node_hostname:-$node_ip}"

    # 使用密钥方式验证免密登录
    if ssh -n -i "$HOME/.ssh/id_rsa" -p "$ssh_port" -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no -o BatchMode=yes \
        "${ssh_user}@${node_ip}" "echo 'OK'" >/dev/null 2>&1; then
        check_pass "免密登录成功: ${node_display} (${node_ip})"
    else
        check_fail "免密登录失败: ${node_display} (${node_ip})"
    fi
done <<< "$all_ips"

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "SSH免密登录验证通过"
    exit 0
else
    log_error "SSH免密登录验证失败"
    exit 1
fi
