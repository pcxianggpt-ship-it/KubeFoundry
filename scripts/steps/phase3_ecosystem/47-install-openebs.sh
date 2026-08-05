#!/bin/bash

#===============================================================================
# 脚本名称：47-install-openebs.sh
# 功能：在主控节点幂等安装 OpenEBS
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
chart_dir=$(phase3_resource_path .)
[ -f "${chart_dir}/Chart.yaml" ] || {
    log_error "OpenEBS Helm Chart 不存在: ${chart_dir}"
    exit 1
}

values_file="${chart_dir}/openebs-values.yaml"
storage_class_file="${chart_dir}/openebssc.yaml"
[ -f "${storage_class_file}" ] && phase3_apply_managed "${storage_class_file}"
if [ -f "${values_file}" ]; then
    phase3_helm_upgrade openebs kubemate-system "${chart_dir}" -f "${values_file}"
else
    phase3_helm_upgrade openebs kubemate-system "${chart_dir}"
fi
kubectl get storageclass >/dev/null
deployments=$(kubectl get deployment --namespace kubemate-system --no-headers 2>/dev/null \
    | awk '$1 ~ /openebs/ { print $1 }')
while IFS= read -r name; do
    [ -z "${name}" ] || phase3_wait_rollout deployment "${name}" kubemate-system
done <<< "${deployments}"
log_success "OpenEBS 已幂等安装并通过控制面检查"
