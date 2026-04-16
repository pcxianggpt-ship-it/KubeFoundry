#!/bin/bash

#===============================================================================
# 脚本名称：verify-17-install-registry.sh
# 功能：验证镜像仓库安装
# 执行机器：管理节点（远程验证镜像仓库节点）
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

log_info "===== 验证：镜像仓库安装 ====="

registry_ip=$(get_registry_ip)
if [ -z "$registry_ip" ]; then
    log_error "未配置镜像仓库节点"
    exit 1
fi

registry_hn=$(get_registry_hostname)
node_display="${registry_hn:-$registry_ip}"

# 1. registry 容器运行中
result=$(ssh_exec_capture "$registry_ip" \
    "nerdctl ps --format '{{.Names}}' 2>/dev/null | grep -c '^registry$' || \
     docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^registry$' || echo 0")
if [ "$result" -ge 1 ]; then
    check_pass "registry 容器运行中: ${node_display}"
else
    check_fail "registry 容器未运行: ${node_display}"
fi

# 2. registry 端口 5000 监听
result=$(ssh_exec_capture "$registry_ip" \
    "ss -tlnp 2>/dev/null | grep -c ':5000' || echo 0")
if [ "$result" -ge 1 ]; then
    check_pass "registry 端口 5000 已监听: ${node_display}"
else
    check_fail "registry 端口 5000 未监听: ${node_display}"
fi

# 3. registry UI 容器运行中
result=$(ssh_exec_capture "$registry_ip" \
    "nerdctl ps --format '{{.Names}}' 2>/dev/null | grep -c 'registry-ui' || \
     docker ps --format '{{.Names}}' 2>/dev/null | grep -c 'registry-ui' || echo 0")
if [ "$result" -ge 1 ]; then
    check_pass "registry UI 容器运行中: ${node_display}"
else
    check_fail "registry UI 容器未运行: ${node_display}"
fi

# 4. registry UI 端口 5080 监听
result=$(ssh_exec_capture "$registry_ip" \
    "ss -tlnp 2>/dev/null | grep -c ':5080' || echo 0")
if [ "$result" -ge 1 ]; then
    check_pass "registry UI 端口 5080 已监听: ${node_display}"
else
    check_fail "registry UI 端口 5080 未监听: ${node_display}"
fi

# 5. registry API 可访问
result=$(ssh_exec_capture "$registry_ip" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:5000/v2/ 2>/dev/null")
if [ "$result" = "200" ]; then
    check_pass "registry API 返回 200: ${node_display}"
else
    check_fail "registry API 不可访问 (HTTP: ${result}): ${node_display}"
fi

# 6. registry 镜像列表
result=$(ssh_exec_capture "$registry_ip" \
    "nerdctl images 2>/dev/null | grep registry | awk '{print \$2}' | grep -c '2.8.3' || \
     docker images 2>/dev/null | grep registry | awk '{print \$2}' | grep -c '2.8.3' || echo 0")
if [ "$result" -ge 1 ]; then
    check_pass "registry:2.8.3 镜像存在: ${node_display}"
else
    check_fail "registry:2.8.3 镜像不存在: ${node_display}"
fi

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "镜像仓库安装验证通过"
    exit 0
else
    log_error "镜像仓库安装验证失败"
    exit 1
fi
