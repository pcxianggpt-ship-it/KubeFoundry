#!/bin/bash

#===============================================================================
# 脚本名称：32-mount-nfs-workers.sh
# 功能：在当前 Worker 节点幂等维护 NFS 挂载
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
: "${KF_NFS_SERVER:?缺少 NFS 服务地址}"
: "${KF_NFS_SHARE_PATH:?缺少 NFS 共享目录}"
: "${KF_NFS_WORKER_MOUNT_PATH:?缺少 Worker 挂载目录}"

if [ "${KF_NFS_EXPORTS_MODE:-}" = "managed" ] && [ "${KF_NODE_IP:-}" = "${KF_NFS_SERVER}" ]; then
    log_info "当前节点是受管 NFS 服务端，跳过自身 NFS 挂载以避免自挂载"
    exit 0
fi

managed_marker_begin="# >>>KubeFoundry NFS fstab>>>"
managed_marker_end="# <<<KubeFoundry NFS fstab<<<"
fstab_entry="${KF_NFS_SERVER}:${KF_NFS_SHARE_PATH} ${KF_NFS_WORKER_MOUNT_PATH} nfs defaults,_netdev 0 0"
fstab_file="${KF_NFS_FSTAB_FILE:-/etc/fstab}"

mkdir -p -- "${KF_NFS_WORKER_MOUNT_PATH}"
if ! grep -qF "${managed_marker_begin}" "${fstab_file}" 2>/dev/null; then
    {
        printf '%s\n' "${managed_marker_begin}"
        printf '%s\n' "${fstab_entry}"
        printf '%s\n' "${managed_marker_end}"
    } >> "${fstab_file}"
fi
expected_source="${KF_NFS_SERVER}:${KF_NFS_SHARE_PATH}"
if mountpoint -q -- "${KF_NFS_WORKER_MOUNT_PATH}"; then
    mounted_source=$(findmnt -n -o SOURCE --target "${KF_NFS_WORKER_MOUNT_PATH}" 2>/dev/null || true)
    if [ "${mounted_source}" != "${expected_source}" ]; then
        log_error "挂载目录已被其他文件系统占用: ${KF_NFS_WORKER_MOUNT_PATH} (${mounted_source:-未知来源})"
        exit 1
    fi
    log_info "NFS 已挂载，跳过重复挂载: ${expected_source}"
else
    mount -t nfs "${expected_source}" "${KF_NFS_WORKER_MOUNT_PATH}"
fi
log_success "当前 Worker 的 NFS 挂载已幂等完成"
