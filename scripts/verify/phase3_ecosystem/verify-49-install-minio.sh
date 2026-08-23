#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
kube() {
    local duration="$1"; shift
    timeout --foreground "${duration}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${duration}" "$@"
    local status=$?
    case "${status}" in 124|137) return 21 ;; esac
    return "${status}"
}
check_status() { [ "$1" -ne 21 ] || { printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21; }; }

[ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get --raw=/readyz >/dev/null 2>&1; status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || error "Kubernetes API 验证异常"
kube "${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" rollout status deployment/minio-operator --namespace kubemate-system --timeout="${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" >/dev/null 2>&1; status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || missing "MinIO Operator 未就绪"
state=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get tenant kubemate-minio -n kubemate-system -o jsonpath='{.status.currentState}' 2>/dev/null); status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || missing "MinIO Tenant 不存在"
[ "${state}" = Initialized ] || missing "MinIO Tenant 未初始化"
pods=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get pods -n kubemate-system -l v1.min.io/tenant=kubemate-minio --no-headers 2>/dev/null); status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || error "MinIO Pod 查询失败"
[ "$(printf '%s\n' "${pods}" | awk '$2 ~ /^[0-9]+\/[0-9]+$/ && $2 != "0/0" && $3 == "Running" { count++ } END { print count+0 }')" -eq 4 ] || missing "MinIO Tenant Pod 未全部就绪"
pvcs=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get pvc -n kubemate-system -l v1.min.io/tenant=kubemate-minio --no-headers 2>/dev/null); status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || error "MinIO PVC 查询失败"
[ "$(printf '%s\n' "${pvcs}" | awk '$2 == "Bound" { count++ } END { print count+0 }')" -eq 4 ] || missing "MinIO Tenant PVC 未全部 Bound"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get service kubemate-minio-hl -n kubemate-system >/dev/null 2>&1; status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || missing "MinIO Headless Service 不存在"
printf '[SUCCESS] MinIO Operator、Tenant、Pod 和 PVC 已就绪\n'
