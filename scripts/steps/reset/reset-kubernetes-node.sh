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

unmount_managed_mounts() {
    local target="$1"
    local mount_point

    command -v findmnt >/dev/null 2>&1 || fail "缺少 findmnt，无法安全卸载受管目录挂载点"
    while IFS= read -r mount_point; do
        [ -n "$mount_point" ] || continue
        log_info "卸载受管目录挂载点: ${mount_point}"
        if ! umount -- "$mount_point"; then
            log_warn "常规卸载失败，尝试惰性卸载: ${mount_point}"
            umount -l -- "$mount_point" || fail "无法卸载受管目录挂载点: ${mount_point}"
        fi
    done < <(findmnt -rn -o TARGET | awk -v target="$target" \
        '$0 == target || index($0, target "/") == 1' | sort -r)
}

remove_managed_directory() {
    local target="$1"
    [[ -n "$target" ]] || fail "受管清理目录不能为空"
    case "$target" in
        "${KF_K8S_HOME}"/*) ;;
        *) fail "拒绝清理工作目录外的路径: ${target}" ;;
    esac
    [[ ! -L "$target" ]] || fail "拒绝清理符号链接: ${target}"
    unmount_managed_mounts "$target"
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

managed_block_exists() {
    local file="$1"
    local begin_marker="$2"
    [ -f "${file}" ] && [ ! -L "${file}" ] && grep -qF -- "${begin_marker}" "${file}"
}

validate_managed_block() {
    local file="$1"
    local begin_marker="$2"
    local end_marker="$3"

    awk -v begin="${begin_marker}" -v end="${end_marker}" '
        $0 == begin {
            if (inside || ++blocks > 1) exit 21
            inside = 1
            next
        }
        $0 == end {
            if (!inside) exit 22
            inside = 0
        }
        END { if (inside || blocks != 1) exit 23 }
    ' "${file}"
}

remove_managed_block() {
    local file="$1"
    local begin_marker="$2"
    local end_marker="$3"
    local temporary

    [ -e "${file}" ] || return 0
    [ -f "${file}" ] && [ ! -L "${file}" ] || fail "拒绝修改非普通文件或符号链接: ${file}"
    managed_block_exists "${file}" "${begin_marker}" || return 0
    temporary=$(mktemp "${file}.kubefoundry.XXXXXX") || fail "无法创建系统配置临时文件: ${file}"
    if ! validate_managed_block "${file}" "${begin_marker}" "${end_marker}"; then
        rm -f -- "${temporary}"
        fail "受管标记块不完整或重复，拒绝修改系统配置: ${file}"
    fi
    awk -v begin="${begin_marker}" -v end="${end_marker}" '
        $0 == begin { inside = 1; next }
        $0 == end { inside = 0; next }
        !inside { print }
    ' "${file}" > "${temporary}"
    if ! chmod --reference="${file}" "${temporary}"; then
        rm -f -- "${temporary}"
        fail "无法保留系统配置权限: ${file}"
    fi
    if ! chown --reference="${file}" "${temporary}"; then
        rm -f -- "${temporary}"
        fail "无法保留系统配置属主: ${file}"
    fi
    if ! mv -f -- "${temporary}" "${file}"; then
        rm -f -- "${temporary}"
        fail "无法原子更新系统配置: ${file}"
    fi
}

managed_nfs_mount_points() {
    local fstab_file="$1"
    awk '
        $0 == "# >>>KubeFoundry NFS fstab>>>" { inside = 1; next }
        $0 == "# <<<KubeFoundry NFS fstab<<<" { inside = 0; next }
        inside && $0 !~ /^[[:space:]]*#/ && NF >= 2 { print $2 }
    ' "${fstab_file}"
}

cleanup_managed_nfs() {
    local fstab_file="/etc/fstab"
    local exports_file="/etc/exports"
    local mount_point

    if managed_block_exists "${fstab_file}" '# >>>KubeFoundry NFS fstab>>>'; then
        validate_managed_block "${fstab_file}" '# >>>KubeFoundry NFS fstab>>>' '# <<<KubeFoundry NFS fstab<<<' \
            || fail "受管标记块不完整或重复，拒绝卸载 NFS 挂载"
        while IFS= read -r mount_point; do
            [[ "${mount_point}" == /* && "${mount_point}" != / && "${mount_point}" != *$'\n'* \
                && "${mount_point}" != *$'\r'* && "${mount_point}" != *".."* ]] \
                || fail "受管 NFS 挂载点不安全: ${mount_point}"
            if mountpoint -q -- "${mount_point}"; then
                log_info "卸载受管 NFS 挂载点: ${mount_point}"
                umount -- "${mount_point}" || umount -l -- "${mount_point}" \
                    || fail "无法卸载受管 NFS 挂载点: ${mount_point}"
            fi
        done < <(managed_nfs_mount_points "${fstab_file}")
        remove_managed_block "${fstab_file}" '# >>>KubeFoundry NFS fstab>>>' '# <<<KubeFoundry NFS fstab<<<'
    fi

    if managed_block_exists "${exports_file}" '# >>>KubeFoundry NFS exports>>>'; then
        validate_managed_block "${exports_file}" '# >>>KubeFoundry NFS exports>>>' '# <<<KubeFoundry NFS exports<<<' \
            || fail "受管标记块不完整或重复，拒绝刷新 NFS exports"
        remove_managed_block "${exports_file}" '# >>>KubeFoundry NFS exports>>>' '# <<<KubeFoundry NFS exports<<<'
        command -v exportfs >/dev/null 2>&1 || fail "缺少 exportfs，无法安全刷新 NFS exports"
        exportfs -ra || fail "无法刷新 NFS exports"
    fi
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
cleanup_managed_nfs
kubeadm reset -f || fail "kubeadm reset 执行失败"
systemctl stop kubelet || true

cleanup_registry

# 删除 containerd 的容器记录前先释放 registry 名称，避免 nerdctl 遗留名称索引。
if systemctl is-active --quiet containerd 2>/dev/null; then
    systemctl stop containerd || fail "无法停止 containerd，拒绝删除其数据目录"
fi

remove_managed_directory "${KF_KUBELET_ROOT:-}"
remove_managed_directory "${KF_ETCD_DATA_DIR:-}"
remove_managed_directory "${KF_CONTAINERD_ROOT:-}"

remove_system_directory /etc/kubernetes
remove_system_directory /etc/cni/net.d
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true
systemctl daemon-reload
log_success "Kubernetes 节点清理完成"
