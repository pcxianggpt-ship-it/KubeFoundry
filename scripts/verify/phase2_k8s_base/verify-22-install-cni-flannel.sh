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
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get namespace kube-flannel >/dev/null 2>&1 || missing "Flannel 命名空间不存在"
kube "${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" rollout status daemonset/kube-flannel-ds --namespace kube-flannel --timeout="${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" >/dev/null 2>&1 || missing "Flannel DaemonSet 未就绪"
kube "${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" rollout status deployment/coredns --namespace kube-system --timeout="${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" >/dev/null 2>&1 || missing "CoreDNS 未就绪"
printf '[SUCCESS] Flannel 和 CoreDNS 已就绪\n'
