#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
run() {
    local duration="$1"; shift
    timeout --foreground "${duration}" "$@"
    local status=$?
    case "${status}" in 124|137) printf '[ERROR] 验证命令超时\n' >&2; exit 21 ;; esac
    return "${status}"
}

[ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
command -v helm >/dev/null 2>&1 || error "验证工具不可用: helm"
run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get --raw=/readyz >/dev/null 2>&1 || error "Kubernetes API 验证异常"
run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" env KUBECONFIG="${KF_KUBECONFIG}" helm status nfs-subdir-external-provisioner --namespace kubemate-system >/dev/null 2>&1 || missing "NFS Provisioner Helm Release 不存在"
run "${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" rollout status deployment/nfs-subdir-external-provisioner --namespace kubemate-system --timeout="${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}" >/dev/null 2>&1 || missing "NFS Provisioner 未就绪"
run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get storageclass "${KF_NFS_STORAGE_CLASS:-nfs-client}" >/dev/null 2>&1 || missing "NFS StorageClass 不存在"
printf '[SUCCESS] NFS Provisioner 已就绪\n'
