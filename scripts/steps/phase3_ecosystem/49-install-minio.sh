#!/bin/bash

#===============================================================================
# 脚本名称：49-install-minio.sh
# 功能：通过固定配置文件安装 MinIO Operator 和四节点 Tenant
# 作者：KubeFoundry Team
# 版本：0.3.1
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
resource_dir=$(phase3_resource_path .)
operator_manifest="${resource_dir}/minio-operator.yaml"
kustomization_file="${resource_dir}/kustomization.yaml"
tenant_manifest="${resource_dir}/tenant.yaml"
tenant_env="${resource_dir}/tenant.env"
[ -f "${operator_manifest}" ] || {
    log_error "MinIO Operator 清单不存在: ${operator_manifest}"
    exit 1
}
for required_file in "${kustomization_file}" "${tenant_manifest}" "${tenant_env}"; do
    [ -f "${required_file}" ] || {
        log_error "MinIO Tenant 配置文件不存在: ${required_file}"
        exit 1
    }
done
if grep -q 'CHANGE_ME_' "${tenant_env}"; then
    log_error "MinIO 凭据配置仍包含 CHANGE_ME_ 占位符: ${tenant_env}"
    exit 1
fi

minio_image="registry:5000/quay.io/minio/minio:RELEASE.2024-03-05T04-48-44Z"
phase3_registry_image_exists "${minio_image}" || {
    log_error "MinIO 私有仓库镜像缺失: ${minio_image}"
    exit 1
}

phase3_apply_managed "${operator_manifest}"
phase3_wait_rollout deployment minio-operator kubemate-system
kubectl wait --for=condition=Established crd/tenants.minio.min.io --timeout=120s

mapfile -t minio_nodes < <(kubectl get nodes \
    --selector='!node-role.kubernetes.io/control-plane,!node-role.kubernetes.io/master' \
    --no-headers 2>/dev/null | awk '{ print $1 }')
[ "${#minio_nodes[@]}" -ge 4 ] || {
    log_error "MinIO 四节点 Tenant 至少需要 4 个 Worker，当前: ${#minio_nodes[@]}"
    exit 1
}
kubectl get storageclass openebs-hostpath >/dev/null 2>&1 || {
    log_error "MinIO Tenant 所需 StorageClass 不存在: openebs-hostpath"
    exit 1
}
kubectl label nodes "${minio_nodes[@]:0:4}" kubefoundry.io/minio=true --overwrite
kubectl apply -k "${resource_dir}"

tenant_name="kubemate-minio"
namespace="kubemate-system"
timeout="${KF_MINIO_TIMEOUT:-10m}"
kubectl wait --for=jsonpath='{.status.currentState}'=Initialized \
    "tenant/${tenant_name}" --namespace "${namespace}" --timeout "${timeout}"
kubectl wait --for=condition=Ready pod \
    --selector "v1.min.io/tenant=${tenant_name}" --namespace "${namespace}" --timeout "${timeout}"
tenant_pods=$(kubectl get pods --selector "v1.min.io/tenant=${tenant_name}" \
    --namespace "${namespace}" --no-headers | wc -l)
[ "${tenant_pods}" -eq 4 ] || {
    log_error "MinIO Tenant Pod 数量不正确，期望 4，实际 ${tenant_pods}"
    exit 1
}
tenant_pvcs=$(kubectl get pvc --selector "v1.min.io/tenant=${tenant_name}" \
    --namespace "${namespace}" --no-headers 2>/dev/null || true)
[ "$(printf '%s\n' "${tenant_pvcs}" | awk 'NF && $2 == "Bound" { count++ } END { print count + 0 }')" -eq 4 ] || {
    log_error "MinIO Tenant PVC 未全部 Bound"
    exit 1
}
kubectl get service kubemate-minio-hl --namespace kubemate-system >/dev/null

log_success "MinIO Operator、四节点 Tenant、PVC、Pod 和服务已就绪"
