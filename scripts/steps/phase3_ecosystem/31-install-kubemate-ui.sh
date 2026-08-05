#!/bin/bash

#===============================================================================
# 脚本名称：31-install-kubemate-ui.sh
# 功能：在主控节点声明式安装 Kubemate UI
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
: "${KF_PRIMARY_CONTROL_IP:?缺少主控制节点地址}"

kubemate_namespace="${KF_KUBEMATE_NAMESPACE:-kubemate-system}"
kubemate_nodeport="${KF_KUBEMATE_NODEPORT:-30088}"
manifest=$(phase3_resource_path "31-install-kubemate-ui")
[ -f "${manifest}" ] || {
    log_error "Kubemate YAML 不存在: ${manifest}"
    exit 1
}
[ -f "${KUBECONFIG}" ] || {
    log_error "Kubernetes 管理配置不存在: ${KUBECONFIG}"
    exit 1
}

phase3_ensure_namespace "${kubemate_namespace}"
kubectl create configmap kubemate-etc --namespace "${kubemate_namespace}" \
    --from-file=k8s_config.yml="${KUBECONFIG}" --dry-run=client -o yaml | kubectl apply -f -

# 只在任务目录生成副本，保留原始离线介质不变。
rendered=$(mktemp)
trap 'rm -f -- "${rendered}"' EXIT
escaped_ip=$(printf '%s' "${KF_PRIMARY_CONTROL_IP}" | sed 's/[&|\\]/\\&/g')
sed -e "s|__KF_PRIMARY_CONTROL_IP__|${escaped_ip}|g" \
    -e "s|\${KF_PRIMARY_CONTROL_IP}|${escaped_ip}|g" "${manifest}" > "${rendered}"

nodeports=$(kubectl get service --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.ports[*].nodePort}{"\n"}{end}')
if printf '%s\n' "${nodeports}" | awk -v port="${kubemate_nodeport}" \
    '$3 == port && !($1 == "kubemate-system" && $2 == "kubemate-ui") { found = 1 } END { exit found }'; then
    :
else
    log_error "NodePort 已被其他 Service 占用: ${kubemate_nodeport}"
    exit 1
fi

kubectl apply --server-side --field-manager=kubefoundry -f "${rendered}"
deployments=$(kubectl get deployment --namespace "${kubemate_namespace}" -o name)
if [ -n "${deployments}" ]; then
    while IFS= read -r deployment; do
        [ -z "${deployment}" ] || phase3_wait_rollout "${deployment%%/*}" "${deployment#*/}" "${kubemate_namespace}"
    done <<< "${deployments}"
fi
kubectl get service --namespace "${kubemate_namespace}" -o name | grep -q . || {
    log_error "Kubemate Service 未创建"
    exit 1
}
log_success "Kubemate UI 已幂等安装并通过就绪检查"
