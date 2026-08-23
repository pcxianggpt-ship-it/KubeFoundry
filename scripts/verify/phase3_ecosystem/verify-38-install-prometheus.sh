#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
kube() {
    timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${KF_VERIFY_COMMAND_TIMEOUT:-30s}" "$@"
    local status=$?
    case "${status}" in 124|137) return 21 ;; esac
    return "${status}"
}
check_status() { [ "$1" -ne 21 ] || { printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21; }; }

[ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
kube get --raw=/readyz >/dev/null 2>&1; status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || error "Kubernetes API 验证异常"
kube get prometheus -A >/dev/null 2>&1; status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || missing "Prometheus 自定义资源不存在"
kube get servicemonitor -A >/dev/null 2>&1; status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || missing "ServiceMonitor 资源不存在"
pods=$(kube get pods -A --no-headers 2>/dev/null); status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || error "Prometheus Pod 查询失败"
printf '%s\n' "${pods}" | awk '$2 ~ /prometheus/ && $4 == "Running" { found=1 } END { exit !found }' || missing "Prometheus 工作负载未就绪"
printf '[SUCCESS] Prometheus 监控组件已就绪\n'
