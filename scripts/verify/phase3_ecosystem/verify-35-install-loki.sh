#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
run() {
    timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" "$@"
    local status=$?
    case "${status}" in 124|137) printf '[ERROR] 验证命令超时\n' >&2; exit 21 ;; esac
    return "${status}"
}

[ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
command -v helm >/dev/null 2>&1 || error "验证工具不可用: helm"
run env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get --raw=/readyz >/dev/null 2>&1 || error "Kubernetes API 验证异常"
run env KUBECONFIG="${KF_KUBECONFIG}" helm status loki --namespace kubemate-system >/dev/null 2>&1 || missing "loki Helm Release 不存在"
pods=$(run env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get pods -n kubemate-system --no-headers 2>/dev/null)
status=$?
[ "${status}" -ne 21 ] || exit 21
[ "${status}" -eq 0 ] || error "loki Pod 查询失败"
printf '%s\n' "${pods}" | awk '$1 ~ /loki/ && ($3 == "Running" || $3 == "Completed") { found=1 } END { exit !found }' || missing "loki 工作负载未就绪"
printf '[SUCCESS] loki 已就绪\n'
