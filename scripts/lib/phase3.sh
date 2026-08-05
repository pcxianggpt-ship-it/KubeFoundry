#!/bin/bash

#===============================================================================
# 脚本名称：phase3.sh
# 功能：Kubemate phase3 组件脚本公共函数
# 作者：KubeFoundry Team
# 版本：0.3.0
#===============================================================================

[ -n "${_KUBEFNDRY_PHASE3_LOADED:-}" ] && return 0
_KUBEFNDRY_PHASE3_LOADED=1

phase3_init() {
    set -o errexit -o nounset -o pipefail
    : "${KUBECONFIG:=/etc/kubernetes/admin.conf}"
    export KUBECONFIG
    mkdir -p -- "${KF_COMPONENT_RESOURCE_DIR}"
    : "${KF_COMPONENT_RESOURCE_DIR:?缺少任务组件资源目录}"
    if [ ! -d "${KF_COMPONENT_RESOURCE_DIR}" ]; then
        log_error "任务组件资源目录不存在: ${KF_COMPONENT_RESOURCE_DIR}"
        return 1
    fi
}

phase3_resource_path() {
    local relative_path="$1"
    local root candidate
    root=$(realpath -e "${KF_COMPONENT_RESOURCE_DIR}")
    candidate=$(realpath -m "${root}/${relative_path}")
    case "${candidate}" in
        "${root}"|"${root}"/*) printf '%s\n' "${candidate}" ;;
        *) log_error "资源路径越出任务目录: ${relative_path}"; return 1 ;;
    esac
}

phase3_helm_upgrade() {
    local release="$1"
    local namespace="$2"
    local chart="$3"
    shift 3
    helm upgrade --install "${release}" "${chart}" --namespace "${namespace}" \
        --create-namespace --wait --timeout "${KF_HELM_TIMEOUT:-10m}" "$@"
}

phase3_ensure_namespace() {
    local namespace="$1"
    kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -
}

phase3_apply_configmap() {
    local name="$1"
    local namespace="$2"
    local file="$3"
    [ -f "${file}" ] || { log_error "ConfigMap 源文件不存在: ${file}"; return 1; }
    kubectl create configmap "${name}" --namespace "${namespace}" --from-file="${file}" \
        --dry-run=client -o yaml | kubectl apply -f -
}

phase3_wait_rollout() {
    local kind="$1"
    local name="$2"
    local namespace="$3"
    kubectl rollout status "${kind}/${name}" --namespace "${namespace}" \
        --timeout "${KF_ROLLOUT_TIMEOUT:-10m}"
}

phase3_redact() {
    sed -E 's/((password|token|secret|credential)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig'
}

phase3_log_safe() {
    printf '%s\n' "$*" | phase3_redact | while IFS= read -r line; do
        log_info "${line}"
    done
}

export -f phase3_init phase3_resource_path phase3_helm_upgrade phase3_ensure_namespace \
    phase3_apply_configmap phase3_wait_rollout phase3_redact phase3_log_safe
