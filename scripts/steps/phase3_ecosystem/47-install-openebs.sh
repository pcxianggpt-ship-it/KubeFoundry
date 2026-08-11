#!/bin/bash

#===============================================================================
# 脚本名称：47-install-openebs.sh
# 功能：在主控节点幂等安装 OpenEBS
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
resource_dir=$(phase3_resource_path .)
chart_file="${resource_dir}/openebs-4.2.0.tgz"
[ -f "${chart_file}" ] || {
    log_error "OpenEBS Helm Chart 压缩包不存在: ${chart_file}"
    exit 1
}

values_file="${resource_dir}/openebs-values.yaml"
storage_class_file="${resource_dir}/openebssc.yaml"
[ -f "${storage_class_file}" ] && phase3_apply_managed "${storage_class_file}"
if [ -f "${values_file}" ]; then
    helm install openebs --namespace kubemate-system "${chart_file}" -f "${values_file}"
else
    helm install openebs --namespace kubemate-system "${chart_file}"
fi
kubectl get storageclass >/dev/null
deployments=$(kubectl get deployment --namespace kubemate-system --no-headers 2>/dev/null \
    | awk '$1 ~ /openebs/ { print $1 }')
while IFS= read -r name; do
    [ -z "${name}" ] || phase3_wait_rollout deployment "${name}" kubemate-system
done <<< "${deployments}"
log_success "OpenEBS 已幂等安装并通过控制面检查"
