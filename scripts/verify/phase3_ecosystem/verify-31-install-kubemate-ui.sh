#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
kube() {
    local duration="$1"; shift
    timeout --foreground "${duration}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${duration}" "$@"
    local status=$?
    case "${status}" in 124|137) printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21 ;; esac
    return "${status}"
}

[ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get --raw=/readyz >/dev/null 2>&1 || error "Kubernetes API 验证异常"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get configmap kubemate-etc -n kubemate-system >/dev/null 2>&1 || missing "Kubemate ConfigMap 不存在"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get deployment kubemate-appx -n kubemate-system >/dev/null 2>&1 || missing "Kubemate Deployment 不存在"
kube "${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" rollout status deployment/kubemate-appx --namespace kubemate-system --timeout="${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" >/dev/null 2>&1 || missing "Kubemate Deployment 未就绪"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get service kubemate-app -n kubemate-system >/dev/null 2>&1 || missing "Kubemate Service 不存在"
printf '[SUCCESS] Kubemate 管理组件已就绪\n'
