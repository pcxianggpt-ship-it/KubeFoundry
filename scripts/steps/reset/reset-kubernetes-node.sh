#!/bin/bash

#===============================================================================
# 脚本名称：reset-kubernetes-node.sh
# 功能：仅清理 KubeFoundry 管理的 Kubernetes 节点数据
# 作者：KubeFoundry Team
# 版本：0.2.1
#===============================================================================

set -euo pipefail

fail() {
    log_error "$1"
    exit 64
}

require_safe_work_dir() {
    local work_dir="$1"
    [[ -n "$work_dir" ]] || fail "Kubernetes 工作目录不能为空"
    case "$work_dir" in
        /*) ;;
        *) fail "Kubernetes 工作目录必须为绝对路径" ;;
    esac
    case "$work_dir" in
        /|/etc|/etc/*|/usr|/usr/*|/var|/var/*|/root|/root/*)
            fail "Kubernetes 工作目录不在允许范围内" ;;
    esac
    [[ "$work_dir" != *$'\n'* && "$work_dir" != *$'\r'* && "$work_dir" != *".."* ]] \
        || fail "Kubernetes 工作目录不安全"
}

remove_managed_directory() {
    local target="$1"
    [[ -n "$target" ]] || fail "受管清理目录不能为空"
    case "$target" in
        "${KF_K8S_HOME}"/*) ;;
        *) fail "拒绝清理工作目录外的路径: ${target}" ;;
    esac
    [[ ! -L "$target" ]] || fail "拒绝清理符号链接: ${target}"
    rm -rf --one-file-system -- "$target"
}

remove_system_directory() {
    local target="$1"
    case "$target" in
        /etc/kubernetes|/etc/cni/net.d) ;;
        *) fail "拒绝清理非白名单系统目录: ${target}" ;;
    esac
    [[ ! -L "$target" ]] || fail "拒绝清理符号链接: ${target}"
    rm -rf --one-file-system -- "$target"
}

has_role() {
    local role="$1"
    local roles=",${KF_NODE_ROLES:-${KF_NODE_ROLE:-}},"
    [[ "$roles" == *",${role},"* ]]
}

cleanup_registry() {
    has_role registry || return 0
    local container_cmd=""
    if command -v nerdctl >/dev/null 2>&1; then
        container_cmd="nerdctl"
    elif command -v docker >/dev/null 2>&1; then
        container_cmd="docker"
    fi
    if [[ -n "$container_cmd" ]]; then
        "$container_cmd" rm -f registry registry-ui-5080 >/dev/null 2>&1 || true
    fi
    remove_managed_directory "${KF_K8S_HOME}/04.registry"
}

require_safe_work_dir "${KF_K8S_HOME:-}"
[[ ! -L "${KF_K8S_HOME}" ]] || fail "拒绝使用符号链接 Kubernetes 工作目录"
resolved_work_dir=$(readlink -f -- "${KF_K8S_HOME}" 2>/dev/null || true)
[[ "${resolved_work_dir}" == "${KF_K8S_HOME}" ]] \
    || fail "Kubernetes 工作目录解析后发生变化，拒绝清理"

log_info "开始清理 Kubernetes 节点: ${KF_NODE_HOSTNAME}"
kubeadm reset -f || true
systemctl stop kubelet || true

remove_managed_directory "${KF_KUBELET_ROOT:-}"
remove_managed_directory "${KF_ETCD_DATA_DIR:-}"
remove_managed_directory "${KF_CONTAINERD_ROOT:-}"
cleanup_registry

remove_system_directory /etc/kubernetes
remove_system_directory /etc/cni/net.d
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true
systemctl daemon-reload
log_success "Kubernetes 节点清理完成"
