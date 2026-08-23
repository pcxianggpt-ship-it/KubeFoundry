#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
kube() {
    [ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
    local duration="${1}"; shift
    timeout --foreground "${duration}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${duration}" "$@"
    local status=$?
    case "${status}" in 124|137) printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21 ;; esac
    return "${status}"
}

kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get --raw=/readyz >/dev/null 2>&1 || error "Kubernetes API 验证异常"
annotation=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get deployment coredns -n kube-system -o jsonpath='{.metadata.annotations.kubefoundry\.io/coredns-anti-affinity}' 2>/dev/null); status=$?
[ "${status}" -ne 21 ] || exit 21
[ "${status}" -eq 0 ] || missing "CoreDNS Deployment 不存在"
[ "${annotation}" = v2 ] || missing "CoreDNS 反亲和标记未就绪"
kube "${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" rollout status deployment/coredns --namespace kube-system --timeout="${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" >/dev/null 2>&1 || missing "CoreDNS 未就绪"
printf '[SUCCESS] CoreDNS 反亲和配置已就绪\n'
