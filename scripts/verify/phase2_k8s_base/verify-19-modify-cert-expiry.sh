#!/bin/bash

set -o nounset -o pipefail

grep -q -- '--cluster-signing-duration=867240h0m0s' /etc/kubernetes/manifests/kube-controller-manager.yaml 2>/dev/null || { printf '[INFO] 证书有效期参数未配置\n'; exit 10; }
[ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || { printf '[ERROR] Kubernetes 管理配置不可读\n' >&2; exit 20; }
timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get --raw=/readyz >/dev/null 2>&1
status=$?
case "${status}" in
    0) printf '[SUCCESS] Kubernetes 证书有效期参数已就绪\n' ;;
    124|137) printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21 ;;
    *) printf '[ERROR] Kubernetes API 验证异常\n' >&2; exit 20 ;;
esac
