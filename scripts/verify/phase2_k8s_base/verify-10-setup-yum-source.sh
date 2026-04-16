#!/bin/bash

#===============================================================================
# 脚本名称：verify-10-setup-yum-source.sh
# 功能：验证本地YUM源配置
# 执行机器：管理节点（本地验证）
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

log_info "===== 验证：本地YUM源配置 ====="

# 1. 验证YUM repo文件存在
result=$(ssh_exec_capture "$(get_all_control_plane_ips | head -1)" \
    "test -f /etc/yum.repos.d/k8s.repo && echo 'OK' || echo 'MISSING'" 2>/dev/null)
if [ "$result" = "OK" ]; then
    check_pass "/etc/yum.repos.d/k8s.repo 文件存在"
else
    check_fail "/etc/yum.repos.d/k8s.repo 文件不存在"
fi

# 2. 验证repo文件内容
result=$(ssh_exec_capture "$(get_all_control_plane_ips | head -1)" \
    "grep -c 'k8s-yum' /etc/yum.repos.d/k8s.repo 2>/dev/null || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "k8s-yum repo 段配置正确"
else
    check_fail "k8s-yum repo 段未找到"
fi

# 3. 验证/var/www/html/repo/目录存在
result=$(ssh_exec_capture "$(get_all_control_plane_ips | head -1)" \
    "test -d /var/www/html/repo && echo 'OK' || echo 'MISSING'" 2>/dev/null)
if [ "$result" = "OK" ]; then
    check_pass "/var/www/html/repo/ 目录存在"
else
    check_fail "/var/www/html/repo/ 目录不存在"
fi

# 4. 验证kubelet包可搜索
result=$(ssh_exec_capture "$(get_all_control_plane_ips | head -1)" \
    "yum -q search kubelet 2>/dev/null | wc -l")
if [ "$result" -gt 0 ]; then
    check_pass "kubelet 包可通过yum搜索到"
else
    check_fail "kubelet 包无法通过yum搜索到"
fi

# 5. 验证httpd服务状态
result=$(ssh_exec_capture "$(get_all_control_plane_ips | head -1)" \
    "systemctl is-active httpd 2>/dev/null")
if [ "$result" = "active" ]; then
    check_pass "httpd 服务运行中"
else
    check_fail "httpd 服务未运行 (状态: ${result})"
fi

# 6. 验证httpd开机自启
result=$(ssh_exec_capture "$(get_all_control_plane_ips | head -1)" \
    "systemctl is-enabled httpd 2>/dev/null")
if [ "$result" = "enabled" ]; then
    check_pass "httpd 已设置为开机自启"
else
    check_fail "httpd 未设置开机自启 (状态: ${result})"
fi

# 7. 验证防火墙已关闭
result=$(ssh_exec_capture "$(get_all_control_plane_ips | head -1)" \
    "systemctl is-active firewalld 2>/dev/null")
if [ "$result" = "inactive" ] || [ "$result" = "unknown" ]; then
    check_pass "防火墙已关闭"
else
    check_fail "防火墙仍在运行"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "YUM源配置验证通过"
    exit 0
else
    log_error "YUM源配置验证失败"
    exit 1
fi
