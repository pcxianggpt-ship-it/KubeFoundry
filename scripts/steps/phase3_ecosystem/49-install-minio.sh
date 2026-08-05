#!/bin/bash

#===============================================================================
# 脚本名称：49-install-minio.sh
# 功能：非交互安装 MinIO Operator 和可选租户清单
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
resource_dir=$(phase3_resource_path .)
operator_manifest="${resource_dir}/minio-operator.yaml"
[ -f "${operator_manifest}" ] || {
    log_error "MinIO Operator 清单不存在: ${operator_manifest}"
    exit 1
}
phase3_apply_managed "${operator_manifest}"
deployments=$(kubectl get deployment --namespace kubemate-system --no-headers 2>/dev/null \
    | awk '$1 ~ /minio/ { print $1 }')
while IFS= read -r name; do
    [ -z "${name}" ] || phase3_wait_rollout deployment "${name}" kubemate-system
done <<< "${deployments}"
tenant_manifest="${resource_dir}/minio-tenant.yaml"
if [ -f "${tenant_manifest}" ]; then
    phase3_apply_managed "${tenant_manifest}"
fi
kubectl get pods --namespace kubemate-system --no-headers 2>/dev/null | grep -q minio || {
    log_error "MinIO 工作负载未就绪"
    exit 1
}
log_success "MinIO 已完成非交互安装和工作负载检查"
