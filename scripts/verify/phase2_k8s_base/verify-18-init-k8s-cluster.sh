#!/bin/bash

#===============================================================================
# 脚本名称：verify-18-init-k8s-cluster.sh
# 功能：验证K8S集群初始化
# 执行机器：管理节点（远程验证主控制节点）
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

log_info "===== 验证：K8S集群初始化 ====="

primary_cp=$(get_all_control_plane_ips | head -1)
node_display=$(get_node_hostname "$primary_cp" 2>/dev/null)
node_display="${node_display:-$primary_cp}"

# 1. kubectl 配置文件存在
result=$(ssh_exec_capture "$primary_cp" \
    "test -f /etc/kubernetes/admin.conf && echo 'OK' || echo 'MISSING'" 2>/dev/null)
if [ "$result" = "OK" ]; then
    check_pass "admin.conf 存在: ${node_display}"
else
    check_fail "admin.conf 不存在: ${node_display}"
fi

# 2. kubeconfig 已配置
result=$(ssh_exec_capture "$primary_cp" \
    "test -f \$HOME/.kube/config && echo 'OK' || echo 'MISSING'" 2>/dev/null)
if [ "$result" = "OK" ]; then
    check_pass "kubeconfig 已配置: ${node_display}"
else
    check_fail "kubeconfig 未配置: ${node_display}"
fi

# 3. kubectl get nodes 可用
result=$(ssh_exec_capture "$primary_cp" \
    "kubectl get nodes --no-headers 2>/dev/null | wc -l")
if [ "$result" -ge 1 ]; then
    check_pass "kubectl 可正常查询节点 (共 ${result} 个): ${node_display}"
else
    check_fail "kubectl 无法查询节点: ${node_display}"
fi

# 4. kubelet 服务运行
result=$(ssh_exec_capture "$primary_cp" "systemctl is-active kubelet 2>/dev/null")
if [ "$result" = "active" ]; then
    check_pass "kubelet 服务运行中: ${node_display}"
else
    check_fail "kubelet 服务未运行: ${node_display}"
fi

# 5. kubelet 数据目录配置
kubelet_root=$(config_get '.env.kubelet_root' '/data/kubelet_root')
result=$(ssh_exec_capture "$primary_cp" \
    "grep -c 'KUBELET_EXTRA_ARGS' /etc/sysconfig/kubelet 2>/dev/null || true" | tr -d '[:space:]')
if [ "$result" -ge 1 ]; then
    check_pass "kubelet 数据目录已配置: ${node_display}"
else
    check_fail "kubelet 数据目录未配置: ${node_display}"
fi

# 6. 静态 Pod 运行（etcd/apiserver/controller/scheduler）
for component in etcd kube-apiserver kube-controller-manager kube-scheduler; do
    result=$(ssh_exec_capture "$primary_cp" \
        "kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c '${component}' || true" | tr -d '[:space:]')
    if [ "$result" -ge 1 ]; then
        check_pass "${component} Pod 存在: ${node_display}"
    else
        check_fail "${component} Pod 未找到: ${node_display}"
    fi
done

# 结果汇总
log_separator
log_info "验证结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -eq 0 ]; then
    log_success "K8S集群初始化验证通过"
    exit 0
else
    log_error "K8S集群初始化验证失败"
    exit 1
fi
