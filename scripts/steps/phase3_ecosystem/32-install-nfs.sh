#!/bin/bash

#===============================================================================
# 脚本名称：32-install-nfs.sh
# 功能：在主控节点幂等安装 NFS subdir provisioner
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
: "${KF_NFS_SERVER:?缺少 NFS 服务地址}"
: "${KF_NFS_SHARE_PATH:?缺少 NFS 共享目录}"
: "${KF_NFS_STORAGE_CLASS:?缺少 NFS StorageClass}"

chart_dir=$(phase3_resource_path .)
[ -f "${chart_dir}/Chart.yaml" ] || {
    log_error "NFS Helm Chart 不存在: ${chart_dir}"
    exit 1
}

phase3_helm_upgrade "nfs-subdir-external-provisioner" "kubemate-system" "${chart_dir}" \
    --set "nfs.server=${KF_NFS_SERVER}" \
    --set "nfs.path=${KF_NFS_SHARE_PATH}" \
    --set image.repository=registry:5000/nfs/nfs-subdir-external-provisioner \
    --set image.tag=v4.0.2 \
    --set "storageClass.name=${KF_NFS_STORAGE_CLASS}" \
    --set storageClass.defaultClass=true

kubectl rollout restart deployment/nfs-subdir-external-provisioner --namespace kubemate-system
phase3_wait_rollout deployment nfs-subdir-external-provisioner kubemate-system
log_success "NFS Provisioner 已幂等安装"
