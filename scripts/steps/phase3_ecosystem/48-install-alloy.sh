#!/bin/bash

#===============================================================================
# 脚本名称：48-install-alloy.sh
# 功能：在 Loki 健康后幂等安装 Grafana Alloy
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
resource_dir=$(phase3_resource_path .)
config_file="${resource_dir}/alloy.config"
chart_dir="${resource_dir}"
[ -f "${config_file}" ] || {
    log_error "Alloy 配置不存在: ${config_file}"
    exit 1
}
[ -f "${chart_dir}/Chart.yaml" ] || {
    log_error "Alloy Helm Chart 不存在: ${chart_dir}"
    exit 1
}
kubectl create configmap alloy --namespace kubemate-system --from-file=config.alloy="${config_file}" \
    --dry-run=client -o yaml | kubectl apply --server-side --field-manager=kubefoundry -f -
values_file="${chart_dir}/alloy-values.yaml"
if [ -f "${values_file}" ]; then
    phase3_helm_upgrade alloy kubemate-system "${chart_dir}" -f "${values_file}"
else
    phase3_helm_upgrade alloy kubemate-system "${chart_dir}"
fi
deployments=$(kubectl get deployment --namespace kubemate-system --no-headers 2>/dev/null \
    | awk '$1 ~ /alloy/ { print $1 }')
while IFS= read -r name; do
    [ -z "${name}" ] || phase3_wait_rollout deployment "${name}" kubemate-system
done <<< "${deployments}"
kubectl get pods --namespace kubemate-system --no-headers 2>/dev/null | grep -q alloy || {
    log_error "Alloy 工作负载未就绪"
    exit 1
}
log_success "Alloy 已幂等安装并完成采集链路检查"
