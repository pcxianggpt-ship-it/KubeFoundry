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
check_status() {
    case "$1" in
        0) return 0 ;;
        21) printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21 ;;
        *) return 1 ;;
    esac
}

[ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get --raw=/readyz >/dev/null 2>&1; status=$?
check_status "${status}" || error "Kubernetes API 验证异常"
rows=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get daemonset -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,DESIRED:.status.desiredNumberScheduled,READY:.status.numberReady' --no-headers 2>/dev/null); status=$?
check_status "${status}" || error "Traefik DaemonSet 查询失败"
printf '%s\n' "${rows}" | awk '$2 ~ /^traefik($|-)/ && $3 > 0 && $4 == $3 { found=1 } END { exit !found }' || missing "Traefik DaemonSet 未就绪"
daemonsets=$(printf '%s\n' "${rows}" | awk '$2 ~ /^traefik($|-)/ { print $1 "/" $2 }')
for daemonset in ${daemonsets}; do
    namespace=${daemonset%%/*}
    name=${daemonset#*/}
    kube "${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" rollout status "daemonset/${name}" --namespace "${namespace}" --timeout="${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" >/dev/null 2>&1
    status=$?; check_status "${status}" || missing "Traefik DaemonSet 未就绪"
done
services=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get service -A --no-headers 2>/dev/null); status=$?
check_status "${status}" || error "Traefik Service 查询失败"
printf '%s\n' "${services}" | awk '$2 ~ /^traefik($|-)/ { found=1 } END { exit !found }' || missing "Traefik Service 不存在"
printf '[SUCCESS] Traefik 网关资源已就绪\n'
