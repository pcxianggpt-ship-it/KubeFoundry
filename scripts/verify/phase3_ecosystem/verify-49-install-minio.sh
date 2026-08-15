#!/bin/bash

#===============================================================================
# 脚本名称：verify-49-install-minio.sh
# 功能：验证 MinIO Operator 和四节点 Tenant
# 作者：KubeFoundry Team
# 版本：0.3.1
#===============================================================================

source "${PROJECT_ROOT}/scripts/lib/logger.sh"

set -o errexit -o nounset -o pipefail
: "${KUBECONFIG:=/etc/kubernetes/admin.conf}"
export KUBECONFIG

namespace="kubemate-system"
tenant_name="kubemate-minio"

kubectl rollout status deployment/minio-operator --namespace "${namespace}" --timeout=120s
current_state=$(kubectl get tenant "${tenant_name}" --namespace "${namespace}" \
    -o jsonpath='{.status.currentState}')
[ "${current_state}" = "Initialized" ] || {
    log_error "MinIO Tenant 状态未就绪: ${current_state:-unknown}"
    exit 1
}

pod_count=$(kubectl get pods --namespace "${namespace}" \
    --selector "v1.min.io/tenant=${tenant_name}" --no-headers | awk '$2 == "1/1" && $3 == "Running" { count++ } END { print count + 0 }')
[ "${pod_count}" -eq 4 ] || {
    log_error "MinIO Tenant Ready Pod 数量不正确: ${pod_count}/4"
    exit 1
}

pvc_count=$(kubectl get pvc --namespace "${namespace}" \
    --selector "v1.min.io/tenant=${tenant_name}" --no-headers | awk '$2 == "Bound" { count++ } END { print count + 0 }')
[ "${pvc_count}" -eq 4 ] || {
    log_error "MinIO Tenant Bound PVC 数量不正确: ${pvc_count}/4"
    exit 1
}

node_count=$(kubectl get pods --namespace "${namespace}" \
    --selector "v1.min.io/tenant=${tenant_name}" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' \
    | sort -u | awk 'NF { count++ } END { print count + 0 }')
[ "${node_count}" -eq 4 ] || {
    log_error "MinIO Tenant 未分布在 4 个不同 Worker: ${node_count}/4"
    exit 1
}

kubectl get service "${tenant_name}-hl" --namespace "${namespace}" >/dev/null
log_success "MinIO Operator、Tenant、4 个 Pod、4 个 PVC 和内部服务验证通过"
