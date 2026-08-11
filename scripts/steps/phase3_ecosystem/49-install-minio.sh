#!/bin/bash

#===============================================================================
# 脚本名称：49-install-minio.sh
# 功能：非交互安装 MinIO Operator 和单节点对象存储
# 作者：KubeFoundry Team
# 版本：0.3.1
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
resource_dir=$(phase3_resource_path .)
operator_manifest="${resource_dir}/minio-operator.yaml"
minio_manifest="${resource_dir}/minio-dev.yaml"
[ -f "${operator_manifest}" ] || {
    log_error "MinIO Operator 清单不存在: ${operator_manifest}"
    exit 1
}
[ -f "${minio_manifest}" ] || {
    log_error "MinIO 工作负载清单不存在: ${minio_manifest}"
    exit 1
}

minio_image="registry:5000/quay.io/minio/minio:RELEASE.2024-03-05T04-48-44Z"
curl --fail --silent --show-error --output /dev/null \
    --header 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    'http://registry:5000/v2/quay.io/minio/minio/manifests/RELEASE.2024-03-05T04-48-44Z' || {
    log_error "MinIO 私有仓库镜像缺失: ${minio_image}"
    exit 1
}

phase3_apply_managed "${operator_manifest}"
phase3_wait_rollout deployment minio-operator kubemate-system

minio_node=$(kubectl get nodes \
    --selector='!node-role.kubernetes.io/control-plane,!node-role.kubernetes.io/master' \
    --no-headers 2>/dev/null | awk '$2 == "Ready" { print $1; exit }')
[ -n "${minio_node}" ] || {
    log_error "MinIO 没有可调度的 Ready Worker 节点"
    exit 1
}
rendered_manifest=$(mktemp)
trap 'rm -f -- "${rendered_manifest}"' EXIT
sed -E \
    -e "s|registry:5000/quay.io/minio/minio:[^[:space:]]+|${minio_image}|g" \
    -e "s|k8sn1|${minio_node}|g" \
    -e 's|/data2/minio_data|/data/minio-root|g' \
    "${minio_manifest}" > "${rendered_manifest}"
phase3_apply_managed "${rendered_manifest}"
kubectl wait --for=condition=Ready pod/minio --namespace kubemate-system \
    --timeout "${KF_MINIO_TIMEOUT:-10m}"
kubectl get service kubemate-minio-hl --namespace kubemate-system >/dev/null

log_success "MinIO Operator、对象存储工作负载和服务已就绪"
