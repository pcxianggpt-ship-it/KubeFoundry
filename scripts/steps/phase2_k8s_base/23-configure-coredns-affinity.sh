#!/bin/bash

#===============================================================================
# 脚本名称：23-configure-coredns-affinity.sh
# 功能：为 CoreDNS 副本追加软反亲和规则，优先跨节点调度
# 作者：KubeFoundry Team
# 版本：0.3.1
#===============================================================================

set -o pipefail

KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.conf}"
NAMESPACE="kube-system"
DEPLOYMENT="coredns"
ANNOTATION_KEY="kubefoundry.io/coredns-anti-affinity"
ANNOTATION_VALUE="v1"

run_kubectl() {
    KUBECONFIG="${KUBECONFIG_PATH}" "${KUBECTL_BIN}" "$@"
}

if ! run_kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    log_error "未找到 kube-system/coredns Deployment"
    exit 1
fi

current_marker=$(run_kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
    -o jsonpath='{.metadata.annotations.kubefoundry\.io/coredns-anti-affinity}')
if [ "${current_marker}" != "${ANNOTATION_VALUE}" ]; then
    rule='{"weight":100,"podAffinityTerm":{"labelSelector":{"matchExpressions":[{"key":"k8s-app","operator":"In","values":["kube-dns"]}]},"topologyKey":"kubernetes.io/hostname"}}'
    affinity=$(run_kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.affinity}')
    anti_affinity=$(run_kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity}')
    preferred=$(run_kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution}')

    if [ -z "${affinity}" ] || [ "${affinity}" = "{}" ]; then
        patch='[{"op":"add","path":"/spec/template/spec/affinity","value":{"podAntiAffinity":{"preferredDuringSchedulingIgnoredDuringExecution":['"${rule}"']}}}]'
    elif [ -z "${anti_affinity}" ] || [ "${anti_affinity}" = "{}" ]; then
        patch='[{"op":"add","path":"/spec/template/spec/affinity/podAntiAffinity","value":{"preferredDuringSchedulingIgnoredDuringExecution":['"${rule}"']}}]'
    elif [ -z "${preferred}" ] || [ "${preferred}" = "[]" ]; then
        patch='[{"op":"add","path":"/spec/template/spec/affinity/podAntiAffinity/preferredDuringSchedulingIgnoredDuringExecution","value":['"${rule}"']}]'
    else
        patch='[{"op":"add","path":"/spec/template/spec/affinity/podAntiAffinity/preferredDuringSchedulingIgnoredDuringExecution/-","value":'"${rule}"'}]'
    fi

    if ! run_kubectl patch deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --type=json -p "${patch}"; then
        log_error "CoreDNS 反亲和规则写入失败"
        exit 1
    fi
    if ! run_kubectl annotate deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
            "${ANNOTATION_KEY}=${ANNOTATION_VALUE}" --overwrite; then
        log_error "CoreDNS 反亲和规则标记写入失败"
        exit 1
    fi
fi

if ! run_kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s; then
    log_error "CoreDNS 滚动更新未在 180 秒内完成"
    exit 1
fi

log_success "CoreDNS 软反亲和规则已就绪"
