#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
[ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
command -v kubectl >/dev/null 2>&1 || error "验证工具不可用: kubectl"
timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get --raw=/readyz >/dev/null 2>&1
status=$?
case "${status}" in
    124|137) printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21 ;;
    0) ;;
    *) error "Kubernetes API 验证异常" ;;
esac
phase=$(timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get namespace kubemate-system -o jsonpath='{.status.phase}' 2>/dev/null)
status=$?
case "${status}" in
    124|137) printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21 ;;
    0) ;;
    *) missing "kubemate-system 命名空间不存在" ;;
esac
[ "${phase}" = Active ] || missing "kubemate-system 命名空间未就绪"
printf '[SUCCESS] kubemate-system 命名空间已就绪\n'
