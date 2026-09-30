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
        /etc/kubernetes|/etc/cni/net.d|/run/flannel) ;;
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

managed_file_is_owned() {
    local target="$1"
    [ ! -e "${target}" ] && [ ! -L "${target}" ] && return 1
    [ -f "${target}" ] && [ ! -L "${target}" ] || fail "受管配置不是普通文件: ${target}"
    [ "$(head -n 1 "${target}")" = '# Managed by KubeFoundry v0.3.2' ]
}

require_owned_or_absent() {
    local target="$1"
    [ ! -e "${target}" ] && [ ! -L "${target}" ] && return 0
    managed_file_is_owned "${target}" || fail "受管配置已被用户替换，拒绝删除: ${target}"
}

remove_owned_file() {
    local target="$1"
    [ ! -e "${target}" ] && [ ! -L "${target}" ] && return 0
    managed_file_is_owned "${target}" || fail "受管配置所有权校验失败: ${target}"
    rm -f -- "${target}"
}

manifest_target_allowed() {
    case "$1" in
        /etc/systemd/system/containerd.service|/etc/systemd/system/buildkit.service|\
        /etc/systemd/system/buildkit.socket|/etc/containerd/config.toml|\
        /etc/sysconfig/kubelet|"${HOME}/.kube/config") return 0 ;;
        *) return 1 ;;
    esac
}

managed_state_dir() {
    printf '%s\n' /var/lib/kubefoundry/managed-config
}

preflight_replacement_manifest() {
    local state_dir
    state_dir="$(managed_state_dir)"
    local manifest="${state_dir}/manifest.tsv"
    local key target original backup managed mode uid gid current expected_backup
    local -A seen_keys=() seen_targets=()

    [ ! -e "${state_dir}" ] && [ ! -L "${state_dir}" ] && return 0
    [ ! -L "${state_dir}" ] || fail "受管配置目录不能是符号链接"
    [ -d "${state_dir}" ] || fail "受管配置状态路径不是目录"
    [ -f "${manifest}" ] && [ ! -L "${manifest}" ] || fail "受管配置清单不安全"
    [ "$(stat -c '%a' "${state_dir}" 2>/dev/null)" = 700 ] || fail "受管配置目录权限异常"
    [ "$(stat -c '%a' "${manifest}" 2>/dev/null)" = 600 ] || fail "受管配置清单权限异常"

    while IFS=$'\t' read -r key target original backup managed mode uid gid extra; do
        [ -n "${key}" ] || continue
        [ -z "${extra:-}" ] || fail "受管配置清单字段数量异常"
        [[ "${key}" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "受管配置键不安全"
        manifest_target_allowed "${target}" || fail "受管配置目标不在白名单: ${target}"
        [ -z "${seen_keys[${key}]:-}" ] || fail "受管配置清单包含重复键: ${key}"
        [ -z "${seen_targets[${target}]:-}" ] || fail "受管配置清单包含重复目标: ${target}"
        seen_keys["${key}"]=1
        seen_targets["${target}"]=1
        [[ "${managed}" =~ ^[0-9a-f]{64}$ ]] || fail "受管配置安装后校验和无效: ${target}"
        if [ -e "${target}" ] || [ -L "${target}" ]; then
            [ -f "${target}" ] && [ ! -L "${target}" ] || fail "受管配置目标不安全: ${target}"
            current="$(sha256sum "${target}" | awk '{print $1}')"
            if [ "${current}" != "${managed}" ] && [ "${current}" != "${original}" ]; then
                fail "受管配置已被用户修改，拒绝覆盖: ${target}"
            fi
        elif [ "${original}" != ABSENT ]; then
            fail "需恢复的受管配置意外缺失: ${target}"
        fi

        if [ "${original}" = ABSENT ]; then
            [ "${backup}" = - ] && [ "${mode}" = - ] && [ "${uid}" = - ] && [ "${gid}" = - ] \
                || fail "原始不存在的配置清单记录异常: ${target}"
        else
            [[ "${original}" =~ ^[0-9a-f]{64}$ && "${mode}" =~ ^[0-7]{3,4}$ \
                && "${uid}" =~ ^[0-9]+$ && "${gid}" =~ ^[0-9]+$ ]] \
                || fail "受管配置原始元数据无效: ${target}"
            expected_backup="${state_dir}/baseline/${key}"
            [ "${backup}" = "${expected_backup}" ] || fail "受管配置备份路径异常: ${target}"
            [ -d "${state_dir}/baseline" ] && [ ! -L "${state_dir}/baseline" ] \
                || fail "受管配置基线目录不安全"
            [ "$(stat -c '%a' "${state_dir}/baseline" 2>/dev/null)" = 700 ] \
                || fail "受管配置基线目录权限异常"
            [ -f "${backup}" ] && [ ! -L "${backup}" ] || fail "受管配置基线备份缺失: ${target}"
            [ "$(stat -c '%a' "${backup}" 2>/dev/null)" = 600 ] \
                || fail "受管配置基线备份权限异常: ${target}"
            [ "$(sha256sum "${backup}" | awk '{print $1}')" = "${original}" ] \
                || fail "受管配置基线校验失败: ${target}"
        fi
    done < "${manifest}"
}

restore_replacement_manifest() {
    local state_dir
    state_dir="$(managed_state_dir)"
    local manifest="${state_dir}/manifest.tsv"
    local key target original backup managed mode uid gid extra current temporary
    [ -f "${manifest}" ] || return 0

    while IFS=$'\t' read -r key target original backup managed mode uid gid extra; do
        [ -n "${key}" ] || continue
        current=""
        [ -f "${target}" ] && current="$(sha256sum "${target}" | awk '{print $1}')"
        if [ "${original}" = ABSENT ]; then
            [ -z "${current}" ] || rm -f -- "${target}"
            continue
        fi
        [ "${current}" = "${original}" ] && continue
        temporary="$(dirname "${target}")/.kubefoundry-restore-${key}.$$"
        install -m "${mode}" "${backup}" "${temporary}" || fail "无法恢复受管配置: ${target}"
        chown "${uid}:${gid}" "${temporary}" || { rm -f -- "${temporary}"; fail "无法恢复配置属主: ${target}"; }
        mv -f -- "${temporary}" "${target}" || { rm -f -- "${temporary}"; fail "无法原子恢复受管配置: ${target}"; }
    done < "${manifest}"
    rm -rf --one-file-system -- "${state_dir}"
}

preflight_managed_configuration() {
    local target
    for target in \
        /etc/yum.repos.d/k8s.repo \
        /etc/yum.repos.d/k8s-http.repo \
        /etc/modules-load.d/kubefoundry-k8s.conf \
        /etc/sysctl.d/99-kubefoundry-k8s.conf \
        /etc/security/limits.d/99-kubefoundry.conf \
        /etc/systemd/system/kubefoundry-disable-swap.service \
        /etc/systemd/system/kubefoundry-etcd-backup.service \
        /etc/systemd/system/kubefoundry-etcd-backup.timer \
        /usr/local/libexec/kubefoundry-etcd-backup.sh; do
        require_owned_or_absent "${target}"
    done
    if [ -n "${KF_REGISTRY_IP:-}" ]; then
        require_owned_or_absent "/etc/containerd/certs.d/${KF_REGISTRY_IP}:5000/hosts.toml"
    fi
    require_owned_or_absent /etc/containerd/certs.d/registry:5000/hosts.toml
    for block in \
        '/etc/hosts|# >>>KubeFoundry>>>|# <<<KubeFoundry<<<' \
        '/etc/sysctl.conf|# >>>KubeFoundry sysctl>>>|# <<<KubeFoundry sysctl<<<' \
        '/etc/fstab|# >>>KubeFoundry NFS fstab>>>|# <<<KubeFoundry NFS fstab<<<' \
        '/etc/exports|# >>>KubeFoundry NFS exports>>>|# <<<KubeFoundry NFS exports<<<'; do
        IFS='|' read -r target begin end <<< "${block}"
        if [ -f "${target}" ] && { grep -qF -- "${begin}" "${target}" \
                || grep -qF -- "${end}" "${target}"; }; then
            [ ! -L "${target}" ] || fail "受管标记块文件不能是符号链接: ${target}"
            validate_managed_block "${target}" "${begin}" "${end}" \
                || fail "受管标记块不完整或重复: ${target}"
        fi
    done
    preflight_replacement_manifest
}

cleanup_managed_configuration() {
    local target
    systemctl disable --now kubefoundry-etcd-backup.timer >/dev/null 2>&1 || true
    systemctl stop kubefoundry-etcd-backup.service >/dev/null 2>&1 || true
    systemctl disable --now kubefoundry-disable-swap.service >/dev/null 2>&1 || true
    remove_managed_block /etc/hosts '# >>>KubeFoundry>>>' '# <<<KubeFoundry<<<'
    remove_managed_block /etc/sysctl.conf '# >>>KubeFoundry sysctl>>>' '# <<<KubeFoundry sysctl<<<'
    for target in \
        /etc/yum.repos.d/k8s.repo \
        /etc/yum.repos.d/k8s-http.repo \
        /etc/modules-load.d/kubefoundry-k8s.conf \
        /etc/sysctl.d/99-kubefoundry-k8s.conf \
        /etc/security/limits.d/99-kubefoundry.conf \
        /etc/systemd/system/kubefoundry-disable-swap.service \
        /etc/systemd/system/kubefoundry-etcd-backup.service \
        /etc/systemd/system/kubefoundry-etcd-backup.timer \
        /usr/local/libexec/kubefoundry-etcd-backup.sh; do
        remove_owned_file "${target}"
    done
    if [ -n "${KF_REGISTRY_IP:-}" ]; then
        remove_owned_file "/etc/containerd/certs.d/${KF_REGISTRY_IP}:5000/hosts.toml"
        rmdir "/etc/containerd/certs.d/${KF_REGISTRY_IP}:5000" 2>/dev/null || true
    fi
    remove_owned_file /etc/containerd/certs.d/registry:5000/hosts.toml
    rmdir /etc/containerd/certs.d/registry:5000 2>/dev/null || true
    restore_replacement_manifest
    sysctl --system >/dev/null 2>&1 || true
    command -v yum >/dev/null 2>&1 && yum clean all >/dev/null 2>&1 || true
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
preflight_managed_configuration
systemctl disable --now kubefoundry-etcd-backup.timer >/dev/null 2>&1 || true
systemctl stop kubefoundry-etcd-backup.service >/dev/null 2>&1 || true
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
remove_system_directory /run/flannel
cleanup_managed_configuration
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true
systemctl daemon-reload
log_success "Kubernetes 节点清理完成"
