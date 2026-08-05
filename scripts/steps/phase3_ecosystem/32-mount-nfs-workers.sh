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
if ! mountpoint -q -- "${KF_NFS_WORKER_MOUNT_PATH}"; then
    mount -t nfs "${KF_NFS_SERVER}:${KF_NFS_SHARE_PATH}" "${KF_NFS_WORKER_MOUNT_PATH}"
fi
log_success "当前 Worker 的 NFS 挂载已幂等完成"
