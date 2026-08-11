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
if [ -f "${values_file}" ]; then
    phase3_helm_upgrade loki kubemate-system "${chart_file}" -f "${values_file}"
else
    phase3_helm_upgrade loki kubemate-system "${chart_file}"
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
