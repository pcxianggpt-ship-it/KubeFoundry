#!/bin/bash

#===============================================================================
# 脚本名称：35-install-loki.sh
# 功能：在 OpenEBS 和 MinIO 成功后幂等安装 Loki
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
resource_dir=$(phase3_resource_path .)
chart_file="${resource_dir}/loki-5.45.0.tgz"
[ -f "${chart_file}" ] || {
    log_error "Loki Helm Chart 压缩包不存在: ${chart_file}"
    exit 1
}
values_file="${resource_dir}/values.yaml"
required_images=(
    registry:5000/grafana/loki:2.9.4
    registry:5000/grafana/loki-canary:2.9.4
    registry:5000/ghcr.io/kiwigrid/k8s-sidecar:1.24.3
    registry:5000/nginxinc/nginx-unprivileged:1.24-alpine
)
missing_images=()
for image in "${required_images[@]}"; do
    if ! phase3_registry_image_exists "${image}"; then
        missing_images+=("${image}")
    fi
done
if [ "${#missing_images[@]}" -gt 0 ]; then
    log_error "Loki 私有仓库镜像缺失: ${missing_images[*]}"
    exit 1
fi
kubectl get service kubemate-minio-hl --namespace kubemate-system >/dev/null 2>&1 || {
    log_error "Loki 依赖的 MinIO Service 未就绪: kubemate-system/kubemate-minio-hl"
    exit 1
}
minio_config=$(kubectl get secret kubemate-minio-env --namespace kubemate-system \
    -o go-template='{{index .data "config.env" | base64decode}}')
minio_access_key=$(printf '%s\n' "${minio_config}" \
    | sed -n 's/^export MINIO_ROOT_USER="\([A-Za-z0-9._-]*\)"$/\1/p')
minio_secret_key=$(printf '%s\n' "${minio_config}" \
    | sed -n 's/^export MINIO_ROOT_PASSWORD="\([A-Za-z0-9._-]*\)"$/\1/p')
[ -n "${minio_access_key}" ] && [ -n "${minio_secret_key}" ] || {
    log_error "MinIO Tenant Secret 缺少合法的 MINIO_ROOT_USER 或 MINIO_ROOT_PASSWORD"
    exit 1
}
loki_secret_values=$(mktemp)
chmod 600 "${loki_secret_values}"
trap 'rm -f -- "${loki_secret_values}"' EXIT
printf 'loki:\n  storage:\n    s3:\n      accessKeyId: "%s"\n      secretAccessKey: "%s"\n' \
    "${minio_access_key}" "${minio_secret_key}" > "${loki_secret_values}"
worker_count=$(kubectl get nodes \
    --selector='!node-role.kubernetes.io/control-plane,!node-role.kubernetes.io/master' \
    --no-headers 2>/dev/null | awk '$2 == "Ready" { count++ } END { print count + 0 }')
[ "${worker_count}" -gt 0 ] || {
    log_error "Loki 没有可调度的 Ready Worker 节点"
    exit 1
}
loki_replicas="${worker_count}"
[ "${loki_replicas}" -le 3 ] || loki_replicas=3
if [ -f "${values_file}" ]; then
    phase3_helm_upgrade loki kubemate-system "${chart_file}" -f "${values_file}" -f "${loki_secret_values}" \
        --set "read.replicas=${loki_replicas}" \
        --set "write.replicas=${loki_replicas}" \
        --set "backend.replicas=${loki_replicas}" \
        --set "loki.commonConfig.replication_factor=${loki_replicas}" \
        --set 'sidecar.image.repository=registry:5000/ghcr.io/kiwigrid/k8s-sidecar' \
        --set 'loki.storage.s3.endpoint=kubemate-minio-hl:9000'
else
    phase3_helm_upgrade loki kubemate-system "${chart_file}" -f "${loki_secret_values}" \
        --set "read.replicas=${loki_replicas}" \
        --set "write.replicas=${loki_replicas}" \
        --set "backend.replicas=${loki_replicas}" \
        --set "loki.commonConfig.replication_factor=${loki_replicas}" \
        --set 'sidecar.image.repository=registry:5000/ghcr.io/kiwigrid/k8s-sidecar' \
        --set 'loki.storage.s3.endpoint=kubemate-minio-hl:9000'
fi
deployments=$(kubectl get deployment --namespace kubemate-system --no-headers 2>/dev/null \
    | awk '$1 ~ /loki/ { print $1 }')
while IFS= read -r name; do
    [ -z "${name}" ] || phase3_wait_rollout deployment "${name}" kubemate-system
done <<< "${deployments}"
kubectl get pods --namespace kubemate-system --no-headers 2>/dev/null | grep -q loki || {
    log_error "Loki 工作负载未就绪"
    exit 1
}
log_success "Loki 已幂等安装并通过健康检查"
