#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
kube() {
    [ -n "${KF_KUBECONFIG:-}" ] || error "验证缺少运行参数: KF_KUBECONFIG"
    [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
    timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${KF_VERIFY_COMMAND_TIMEOUT:-30s}" "$@"
    local status=$?
    case "${status}" in 124|137) printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21 ;; esac
    return "${status}"
}

[ -n "${KF_NODE_HOSTNAME:-}" ] || error "验证缺少运行参数: KF_NODE_HOSTNAME"
[ -f /etc/sysconfig/kubelet ] || missing "kubelet 受管配置不存在"
grep -Fqx '# Managed by KubeFoundry v0.3.2' /etc/sysconfig/kubelet || \
    missing "kubelet 受管标记缺失"
manifest=/var/lib/kubefoundry/managed-config/manifest.tsv
[ -f "${manifest}" ] || missing "kubelet 配置基线清单不存在"
grep -Fq $'kubelet.sysconfig\t/etc/sysconfig/kubelet\t' "${manifest}" || \
    missing "kubelet 配置基线记录缺失"
grep -Fq $'kubectl.config\t'"${HOME}/.kube/config"$'\t' "${manifest}" || \
    missing "kubectl 配置基线记录缺失"
[ -s /etc/kubernetes/admin.conf ] || missing "Kubernetes 集群尚未初始化"
for manifest in kube-apiserver kube-controller-manager kube-scheduler etcd; do
    [ -s "/etc/kubernetes/manifests/${manifest}.yaml" ] || missing "Kubernetes 静态 Pod 清单不完整: ${manifest}"
done
kube get --raw=/readyz >/dev/null 2>&1 || error "Kubernetes API 验证异常"
kube get node "${KF_NODE_HOSTNAME}" >/dev/null 2>&1 || missing "主控节点尚未注册"
printf '[SUCCESS] Kubernetes 集群已初始化\n'
