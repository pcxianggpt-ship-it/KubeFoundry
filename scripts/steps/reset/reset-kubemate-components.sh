#!/bin/bash

#===============================================================================
# 脚本名称：reset-kubemate-components.sh
# 功能：在主控制节点逆序清理 KubeFoundry 受管 Kubemate 组件
# 作者：KubeFoundry Team
# 版本：0.3.0
#===============================================================================

set -euo pipefail

fail() {
    log_error "$1"
    exit 64
}

validate_component_groups() {
    local groups="${KF_RESET_COMPONENT_GROUPS:-}"
    [ -z "${groups}" ] && return 0
    [[ "${groups}" =~ ^(nfs|kubemate|traefik|storage_observability|prometheus)(,(nfs|kubemate|traefik|storage_observability|prometheus))*$ ]] \
        || fail "重置组件组列表不安全"
}

validate_release_checksums() {
    local checksums="${KF_RESET_HELM_RELEASE_CHECKSUMS:-}"
    [ -z "${checksums}" ] && return 0
    [[ "${checksums}" =~ ^(alloy|loki|openebs|nfs-subdir-external-provisioner)=[0-9a-f]{64}(,(alloy|loki|openebs|nfs-subdir-external-provisioner)=[0-9a-f]{64})*$ ]] \
        || fail "重置 Helm 校验和列表不安全"
}

group_enabled() {
    case ",${KF_RESET_COMPONENT_GROUPS:-}," in
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
}

release_exists() {
    helm status "$1" --namespace "$2" >/dev/null 2>&1
}

expected_release_checksum() {
    local release="$1"
    local item
    IFS=',' read -r -a items <<< "${KF_RESET_HELM_RELEASE_CHECKSUMS:-}"
    for item in "${items[@]}"; do
        [ "${item%%=*}" = "${release}" ] && {
            printf '%s\n' "${item#*=}"
            return 0
        }
    done
    return 1
}

release_is_managed() {
    local release="$1"
    local namespace="$2"
    local expected_checksum expected_label metadata

    expected_checksum=$(expected_release_checksum "${release}") || return 1
    expected_label="${expected_checksum:0:63}"
    metadata=$(helm get metadata "${release}" --namespace "${namespace}" -o json) || return 1
    printf '%s\n' "${metadata}" | grep -Eq \
        '"app.kubernetes.io/managed-by"[[:space:]]*:[[:space:]]*"kubefoundry"' \
        && printf '%s\n' "${metadata}" | grep -Eq \
            '"kubefoundry.io/media-sha256"[[:space:]]*:[[:space:]]*"'"${expected_label}"'"'
}

uninstall_snapshot_release() {
    local release="$1"
    local namespace="$2"

    release_exists "${release}" "${namespace}" || return 0
    if ! release_is_managed "${release}" "${namespace}"; then
        log_warn "跳过未标记或校验和不匹配的 Helm release: ${namespace}/${release}"
        return 0
    fi
    log_info "清理安装快照记录的 Helm release: ${namespace}/${release}"
    helm uninstall "${release}" --namespace "${namespace}" --wait \
        --timeout "${KF_HELM_TIMEOUT:-10m}"
}

delete_managed_resources() {
    local namespace="$1"

    # 标签是独立于快照的第二道所有权保护；绝不按名称批量删除未标记资源。
    kubectl delete all,configmap,serviceaccount,role,rolebinding --namespace "${namespace}" \
        --selector 'app.kubernetes.io/managed-by=kubefoundry' --ignore-not-found
}

validate_component_groups
validate_release_checksums
if [ -z "${KF_RESET_COMPONENT_GROUPS:-}" ]; then
    log_info "安装快照和组件状态均未记录 Kubemate 组件，跳过组件清理"
    exit 0
fi

command -v kubectl >/dev/null 2>&1 || fail "缺少 kubectl，无法安全清理受管组件"
command -v helm >/dev/null 2>&1 || fail "缺少 Helm，无法安全清理受管组件"
: "${KUBECONFIG:=/etc/kubernetes/admin.conf}"
export KUBECONFIG
[ -f "${KUBECONFIG}" ] || fail "Kubernetes 管理配置不存在: ${KUBECONFIG}"

# 仅清理当前安装快照或组件状态明确记录的组，顺序与安装依赖严格相反。
if group_enabled storage_observability; then
    uninstall_snapshot_release alloy kubemate-system
    uninstall_snapshot_release loki kubemate-system
    delete_managed_resources kubemate-system
    uninstall_snapshot_release openebs kubemate-system
fi

if group_enabled prometheus; then
    delete_managed_resources "${KF_PROMETHEUS_NAMESPACE:-kubemate-monitoring-system}"
    delete_managed_resources kube-system
fi

if group_enabled traefik; then
    delete_managed_resources kubemate-system
fi

if group_enabled kubemate; then
    delete_managed_resources kubemate-system
fi

if group_enabled nfs; then
    uninstall_snapshot_release nfs-subdir-external-provisioner kubemate-system
fi

log_success "Kubemate 受管组件清理完成"
