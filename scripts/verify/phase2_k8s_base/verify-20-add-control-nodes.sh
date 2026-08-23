#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
kube() {
    [ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
    timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${KF_VERIFY_COMMAND_TIMEOUT:-30s}" "$@"
    local status=$?
    case "${status}" in 124|137) printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21 ;; esac
    return "${status}"
}

[ -n "${KF_NODE_HOSTNAME:-}" ] || error "验证缺少运行参数: KF_NODE_HOSTNAME"
[ -s /etc/kubernetes/admin.conf ] || missing "当前控制节点尚未加入集群"
command -v systemctl >/dev/null 2>&1 || error "验证工具不可用: systemctl"
systemctl is-active --quiet kubelet || missing "kubelet 未运行"
kube get --raw=/readyz >/dev/null 2>&1 || error "Kubernetes API 验证异常"
kube get node "${KF_NODE_HOSTNAME}" >/dev/null 2>&1 || missing "当前控制节点未注册"
printf '[SUCCESS] 当前控制节点已加入集群\n'
