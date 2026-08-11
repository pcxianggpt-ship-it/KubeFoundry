#!/bin/bash

#===============================================================================
# 脚本名称：38-install-prometheus.sh
# 功能：在主控节点声明式安装 Prometheus 监控组件
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
namespace="${KF_PROMETHEUS_NAMESPACE:-kubemate-system}"
resource_dir=$(phase3_resource_path .)
phase3_ensure_namespace "${namespace}"
rendered=$(mktemp -d)
trap 'rm -rf -- "${rendered}"' EXIT
cp -a "${resource_dir}/." "${rendered}/"
prom_data_dir="${KF_PROM_DATA_DIR:-/data/prom_data}"
find "${rendered}" -type f \( -name '*.yaml' -o -name '*.yml' \) -exec sed -i "s|/data/prom_data|${prom_data_dir}|g" {} +
additional_scrape_secret="${rendered}/additional-scrape-configs.Secret.yaml"
[ -f "${additional_scrape_secret}" ] || {
    log_error "Prometheus additional-scrape-configs Secret 不存在: ${additional_scrape_secret}"
    exit 1
}
sanitized_secret=$(mktemp)
if ! awk '
    /^  managedFields:[[:space:]]*$/ { skip_managed_fields = 1; next }
    skip_managed_fields && /^  [[:alnum:]_.-]+:/ { skip_managed_fields = 0 }
    skip_managed_fields { next }
    /^  (creationTimestamp|resourceVersion|uid):/ { next }
    { print }
' "${additional_scrape_secret}" > "${sanitized_secret}"; then
    rm -f -- "${sanitized_secret}"
    log_error "清理 Prometheus Secret 服务端元数据失败"
    exit 1
fi
mv -- "${sanitized_secret}" "${additional_scrape_secret}"
phase3_apply_managed "${additional_scrape_secret}"
find "${rendered}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 \
    | sort -z \
    | while IFS= read -r -d '' manifest; do
        [ "${manifest}" = "${additional_scrape_secret}" ] && continue
        phase3_apply_managed "${manifest}"
    done
kubectl wait --for=condition=Established crd --all --timeout "${KF_CRD_TIMEOUT:-10m}"
deployments=$(kubectl get deployment --namespace "${namespace}" --no-headers 2>/dev/null | awk '{print $1}')
while IFS= read -r name; do
    [ -z "${name}" ] || phase3_wait_rollout deployment "${name}" "${namespace}"
done <<< "${deployments}"
kubectl get pods --namespace "${namespace}" --no-headers 2>/dev/null | grep -Eq 'prometheus|node-exporter|kube-state-metrics' || {
    log_error "Prometheus 监控工作负载未就绪"
    exit 1
}
log_success "Prometheus 监控组件已安装并通过就绪检查"
