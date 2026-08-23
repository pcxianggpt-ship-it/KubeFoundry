#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
kube() {
    local duration="$1"
    shift
    timeout --foreground "${duration}" env KUBECONFIG="${KF_KUBECONFIG}" \
        kubectl --request-timeout="${duration}" "$@"
    local status=$?
    case "${status}" in 124|137) printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21 ;; esac
    return "${status}"
}
rollout() {
    local resource="$1" namespace="$2"
    kube "${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" rollout status "${resource}" \
        --namespace "${namespace}" --timeout="${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" >/dev/null 2>&1
}

[ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
command -v kubectl >/dev/null 2>&1 || error "验证工具不可用: kubectl"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get --raw=/readyz >/dev/null 2>&1 || error "Kubernetes API 验证异常"

kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get prometheus k8s -n kubemate-system >/dev/null 2>&1 || missing "Prometheus 自定义资源不存在"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get servicemonitor prometheus-k8s -n kubemate-system >/dev/null 2>&1 || missing "Prometheus ServiceMonitor 不存在"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get deployment prometheus-operator -n kubemate-system >/dev/null 2>&1 || missing "Prometheus Operator 不存在"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get statefulset prometheus-k8s -n kubemate-system >/dev/null 2>&1 || missing "Prometheus StatefulSet 不存在"

rollout deployment/prometheus-operator kubemate-system || missing "Prometheus Operator 未就绪"
rollout statefulset/prometheus-k8s kubemate-system || missing "Prometheus StatefulSet 未就绪"

replicas=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get prometheus k8s -n kubemate-system \
    -o jsonpath='{.spec.replicas}:{.status.availableReplicas}' 2>/dev/null)
status=$?
[ "${status}" -ne 21 ] || exit 21
[ "${status}" -eq 0 ] || error "Prometheus 副本状态查询失败"
desired=${replicas%%:*}
available=${replicas#*:}
[[ "${desired}" =~ ^[0-9]+$ && "${available}" =~ ^[0-9]+$ ]] || missing "Prometheus CR 副本未全部可用"
[ "${desired:-0}" -gt 0 ] && [ "${available:-0}" -eq "${desired}" ] || missing "Prometheus CR 副本未全部可用"

rollout deployment/kube-state-metrics kubemate-system || missing "kube-state-metrics 未就绪"
rollout daemonset/node-exporter kubemate-system || missing "node-exporter 未就绪"
rollout statefulset/alertmanager-main kubemate-system || missing "Alertmanager 未就绪"
rollout deployment/metrics-server kube-system || missing "metrics-server 未就绪"

printf '[SUCCESS] Prometheus、Operator 和监控工作负载已就绪\n'
