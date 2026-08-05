#!/bin/bash

#===============================================================================
# 脚本名称：verify-31-install-kubemate-ui.sh
# 功能：在当前主控节点验证 Kubemate UI
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
namespace="${KF_KUBEMATE_NAMESPACE:-kubemate-system}"
nodeport="${KF_KUBEMATE_NODEPORT:-30088}"

kubectl wait --for=condition=available deployment --all --namespace "${namespace}" \
    --timeout "${KF_ROLLOUT_TIMEOUT:-10m}"
kubectl get service --namespace "${namespace}" -o wide | grep -q "${nodeport}" || {
    log_error "Kubemate UI Service NodePort 不可用: ${nodeport}"
    exit 1
}
log_success "Kubemate UI 验证通过"
