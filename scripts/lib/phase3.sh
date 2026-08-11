#!/bin/bash

#===============================================================================
# 脚本名称：phase3.sh
# 功能：Kubemate phase3 组件脚本公共函数
# 作者：KubeFoundry Team
# 版本：0.3.1
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
    local labels='app.kubernetes.io/managed-by=kubefoundry'
    if [[ "${KF_COMPONENT_MEDIA_SHA256:-}" =~ ^[0-9a-f]{64}$ ]]; then
        labels+=",kubefoundry.io/media-sha256=${KF_COMPONENT_MEDIA_SHA256:0:63}"
    fi
    helm upgrade --install "${release}" "${chart}" --namespace "${namespace}" \
        --create-namespace --wait --timeout "${KF_HELM_TIMEOUT:-10m}" --labels "${labels}" "$@"
}

phase3_apply_managed() {
    local manifest="$1"
    phase3_apply_crds_first "${manifest}"
    kubectl apply --server-side --field-manager=kubefoundry --force-conflicts -f "${manifest}"
    kubectl label --overwrite -f "${manifest}" app.kubernetes.io/managed-by=kubefoundry
}

phase3_apply_crds_first() {
    local manifest="$1"
    local split_dir source document resources resource status
    local -a sources=()
    split_dir=$(mktemp -d)
    status=0

    if [ -d "${manifest}" ]; then
        while IFS= read -r -d '' source; do
            sources+=("${source}")
        done < <(find "${manifest}" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) -print0)
    else
        sources+=("${manifest}")
    fi

    if [ "${#sources[@]}" -gt 0 ]; then
        if ! awk -v output_dir="${split_dir}" '
            function flush_document() {
                if (document == "") return
                count++
                path = output_dir "/document-" count ".yaml"
                printf "%s", document > path
                close(path)
                document = ""
            }
            FNR == 1 && NR != 1 { flush_document() }
            /^---[[:space:]]*($|#)/ { flush_document(); next }
            { document = document $0 ORS }
            END { flush_document() }
        ' "${sources[@]}"; then
            status=1
        fi
    fi

    if [ "${status}" -eq 0 ]; then
        for document in "${split_dir}"/*.yaml; do
            [ -f "${document}" ] || continue
            if ! grep -Eq '^[[:space:]]*kind:[[:space:]]*CustomResourceDefinition([[:space:]]|$)' "${document}"; then
                continue
            fi
            if ! kubectl apply --server-side --field-manager=kubefoundry --force-conflicts -f "${document}"; then
                status=1
                break
            fi
            if ! resources=$(kubectl get -f "${document}" -o name); then
                status=1
                break
            fi
            while IFS= read -r resource; do
                [ -z "${resource}" ] && continue
                if ! kubectl wait --for=condition=Established "${resource}" \
                        --timeout "${KF_CRD_TIMEOUT:-180s}"; then
                    status=1
                    break 2
                fi
            done <<< "${resources}"
        done
    fi

    rm -rf -- "${split_dir}"
    return "${status}"
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
    phase3_apply_configmap phase3_apply_crds_first phase3_apply_managed phase3_wait_rollout \
    phase3_redact phase3_log_safe
