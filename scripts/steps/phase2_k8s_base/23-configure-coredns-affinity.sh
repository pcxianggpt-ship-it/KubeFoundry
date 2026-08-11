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
ANNOTATION_VALUE="v2"

run_kubectl() {
    KUBECONFIG="${KUBECONFIG_PATH}" "${KUBECTL_BIN}" "$@"
}

if ! run_kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    log_error "未找到 kube-system/coredns Deployment"
    exit 1
fi

current_marker=$(run_kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
    -o jsonpath='{.metadata.annotations.kubefoundry\.io/coredns-anti-affinity}')
rule='{"weight":100,"podAffinityTerm":{"labelSelector":{"matchExpressions":[{"key":"k8s-app","operator":"In","values":["kube-dns"]}]},"topologyKey":"kubernetes.io/hostname"}}'
rule_rows=$(run_kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o go-template='{{range $index, $rule := .spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution}}{{printf "%d|" $index}}{{$rule.podAffinityTerm.topologyKey}}{{"|"}}{{range $rule.podAffinityTerm.labelSelector.matchExpressions}}{{.key}}{{"="}}{{.operator}}{{"="}}{{range .values}}{{.}}{{","}}{{end}}{{end}}{{"\n"}}{{end}}')
matching_indices=()
while IFS='|' read -r rule_index topology selector; do
    if [ "${topology}" = "kubernetes.io/hostname" ] \
            && [ "${selector}" = "k8s-app=In=kube-dns," ]; then
        matching_indices+=("${rule_index}")
    fi
done <<< "${rule_rows}"

needs_rollout=false
if [ "${#matching_indices[@]}" -gt 1 ]; then
    for ((index=${#matching_indices[@]} - 1; index >= 1; index--)); do
        duplicate_index=${matching_indices[${index}]}
        patch='[{"op":"remove","path":"/spec/template/spec/affinity/podAntiAffinity/preferredDuringSchedulingIgnoredDuringExecution/'"${duplicate_index}"'"}]'
        if ! run_kubectl patch deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --type=json -p "${patch}"; then
            log_error "CoreDNS 重复反亲和规则清理失败"
            exit 1
        fi
    done
    needs_rollout=true
fi

if [ "${#matching_indices[@]}" -eq 0 ]; then
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
    needs_rollout=true
fi

if [ "${current_marker}" != "${ANNOTATION_VALUE}" ]; then
    if ! run_kubectl annotate deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
            "${ANNOTATION_KEY}=${ANNOTATION_VALUE}" --overwrite; then
        log_error "CoreDNS 反亲和规则标记写入失败"
        exit 1
    fi
    needs_rollout=true
fi

if [ "${needs_rollout}" = true ]; then
    if ! run_kubectl rollout restart deployment/"${DEPLOYMENT}" -n "${NAMESPACE}"; then
        log_error "CoreDNS 滚动重启触发失败"
        exit 1
    fi
fi

if ! run_kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s; then
    log_error "CoreDNS 滚动更新未在 180 秒内完成"
    exit 1
fi

log_success "CoreDNS 软反亲和规则已就绪"
