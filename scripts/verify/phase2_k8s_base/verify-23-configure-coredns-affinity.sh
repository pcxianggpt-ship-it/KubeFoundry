#!/bin/bash

#===============================================================================
# 脚本名称：verify-23-configure-coredns-affinity.sh
# 功能：验证 CoreDNS 软反亲和规则及 Deployment 就绪状态
# 作者：KubeFoundry Team
# 版本：0.3.1
#===============================================================================

set -o pipefail

KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.conf}"

run_kubectl() {
    KUBECONFIG="${KUBECONFIG_PATH}" "${KUBECTL_BIN}" "$@"
}

marker=$(run_kubectl get deployment coredns -n kube-system \
    -o jsonpath='{.metadata.annotations.kubefoundry\.io/coredns-anti-affinity}')
if [ "${marker}" != "v2" ]; then
    log_error "CoreDNS 未发现 KubeFoundry 反亲和规则标记"
    exit 1
fi

rule_count=$(run_kubectl get deployment coredns -n kube-system -o go-template='{{range $rule := .spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution}}{{$rule.podAffinityTerm.topologyKey}}{{"|"}}{{range $rule.podAffinityTerm.labelSelector.matchExpressions}}{{.key}}{{"="}}{{.operator}}{{"="}}{{range .values}}{{.}}{{","}}{{end}}{{end}}{{"\n"}}{{end}}' \
    | grep -Fxc 'kubernetes.io/hostname|k8s-app=In=kube-dns,' || true)
if [ "${rule_count}" -ne 1 ]; then
    log_error "CoreDNS 目标软反亲和规则数量异常: ${rule_count}"
    exit 1
fi

if ! run_kubectl rollout status deployment/coredns -n kube-system --timeout=30s; then
    log_error "CoreDNS Deployment 未就绪"
    exit 1
fi

log_success "CoreDNS 反亲和规则验证通过"
