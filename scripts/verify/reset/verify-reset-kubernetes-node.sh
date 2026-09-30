#!/bin/bash

#===============================================================================
# 脚本名称：verify-reset-kubernetes-node.sh
# 功能：验证 KubeFoundry 受管 Kubernetes 节点已完成清理
# 作者：KubeFoundry Team
# 版本：0.2.1
#===============================================================================

set -euo pipefail

fail() {
    log_error "$1"
    exit 1
}

require_safe_work_dir() {
    local work_dir="$1"
    [[ -n "$work_dir" && "$work_dir" == /* ]] || fail "Kubernetes 工作目录无效"
    [[ "$work_dir" != / && "$work_dir" != *$'\n'* && "$work_dir" != *$'\r'* \
        && "$work_dir" != *".."* ]] || fail "Kubernetes 工作目录不安全"
}

assert_absent() {
    local target="$1"
    [[ -n "$target" ]] || fail "验证目录不能为空"
    [[ ! -e "$target" && ! -L "$target" ]] || fail "重置残留未清理: ${target}"
}

assert_no_managed_block() {
    local file="$1"
    local marker="$2"
    [ ! -L "${file}" ] || fail "验证文件不能是符号链接: ${file}"
    [ ! -f "${file}" ] || ! grep -qF -- "${marker}" "${file}" \
        || fail "受管 NFS 配置残留未清理: ${file}"
}

assert_no_owned_file() {
    local target="$1"
    [[ ! -e "${target}" && ! -L "${target}" ]] || fail "KubeFoundry 受管文件残留未清理: ${target}"
}

has_role() {
    local role="$1"
    local roles=",${KF_NODE_ROLES:-${KF_NODE_ROLE:-}},"
    [[ "$roles" == *",${role},"* ]]
}

verify_registry() {
    has_role registry || return 0
    local container_cmd=""
    if command -v nerdctl >/dev/null 2>&1; then
        container_cmd="nerdctl"
    elif command -v docker >/dev/null 2>&1; then
        container_cmd="docker"
    fi
    if [[ -n "$container_cmd" ]]; then
        ! "$container_cmd" container inspect registry >/dev/null 2>&1 \
            || fail "Registry 容器仍在运行"
        ! "$container_cmd" container inspect registry-ui-5080 >/dev/null 2>&1 \
            || fail "Registry UI 容器仍在运行"
    fi
    assert_absent "${KF_K8S_HOME}/04.registry"
}

require_safe_work_dir "${KF_K8S_HOME:-}"

if systemctl is-active --quiet kubelet 2>/dev/null; then
    fail "kubelet 服务仍在运行"
fi

assert_absent "${KF_KUBELET_ROOT:-}"
assert_absent "${KF_ETCD_DATA_DIR:-}"
assert_absent "${KF_CONTAINERD_ROOT:-}"
assert_absent /etc/kubernetes
assert_absent /etc/cni/net.d
assert_absent /run/flannel
for interface in cni0 flannel.1; do
    ! ip link show "${interface}" >/dev/null 2>&1 \
        || fail "Kubernetes CNI 网络接口残留未清理: ${interface}"
done
assert_no_managed_block /etc/fstab '# >>>KubeFoundry NFS fstab>>>'
assert_no_managed_block /etc/exports '# >>>KubeFoundry NFS exports>>>'
assert_no_managed_block /etc/hosts '# >>>KubeFoundry>>>'
assert_no_managed_block /etc/sysctl.conf '# >>>KubeFoundry sysctl>>>'
for managed_file in \
    /etc/yum.repos.d/k8s.repo \
    /etc/yum.repos.d/k8s-http.repo \
    /etc/modules-load.d/kubefoundry-k8s.conf \
    /etc/sysctl.d/99-kubefoundry-k8s.conf \
    /etc/security/limits.d/99-kubefoundry.conf \
    /etc/systemd/system/kubefoundry-disable-swap.service \
    /etc/systemd/system/kubefoundry-etcd-backup.service \
    /etc/systemd/system/kubefoundry-etcd-backup.timer \
    /usr/local/libexec/kubefoundry-etcd-backup.sh; do
    assert_no_owned_file "${managed_file}"
done
if [ -n "${KF_REGISTRY_IP:-}" ]; then
    assert_no_owned_file "/etc/containerd/certs.d/${KF_REGISTRY_IP}:5000/hosts.toml"
fi
assert_no_owned_file /etc/containerd/certs.d/registry:5000/hosts.toml
assert_no_owned_file /var/lib/kubefoundry/managed-config
verify_registry

log_success "Kubernetes 节点重置验证通过: ${KF_NODE_HOSTNAME}"
