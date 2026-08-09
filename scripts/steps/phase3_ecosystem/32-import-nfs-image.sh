#!/bin/bash

#===============================================================================
# 脚本名称：32-import-nfs-image.sh
# 功能：将离线 NFS Provisioner 镜像导入到内网 Registry
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init

archive=$(phase3_resource_path 32-import-nfs-image)
[ -f "${archive}" ] || {
    log_error "NFS 离线镜像不存在: ${archive}"
    exit 1
}

source_image="harbor.amarsoft.com/k8s-deploy/nfs-subdir-external-provisioner:v4.0.2"
target_image="registry:5000/nfs/nfs-subdir-external-provisioner:v4.0.2"

if command -v nerdctl >/dev/null 2>&1; then
    nerdctl --namespace k8s.io load --input "${archive}"
    nerdctl --namespace k8s.io tag "${source_image}" "${target_image}"
    nerdctl --namespace k8s.io push --insecure-registry "${target_image}"
elif command -v ctr >/dev/null 2>&1; then
    ctr --namespace k8s.io images import "${archive}"
    ctr --namespace k8s.io images tag "${source_image}" "${target_image}"
    ctr --namespace k8s.io images push --plain-http "${target_image}"
else
    log_error "缺少 nerdctl 或 ctr，无法导入 NFS 离线镜像"
    exit 1
fi

log_success "NFS 离线镜像已导入到 ${target_image}"
