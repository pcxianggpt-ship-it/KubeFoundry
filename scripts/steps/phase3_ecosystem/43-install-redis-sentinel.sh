#!/bin/bash

#===============================================================================
# 脚本名称：43-install-redis-sentinel.sh
# 功能：使用冻结的 Bitnami Chart 离线部署 Redis Sentinel
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init

namespace=redis-sentinel
release=kubefoundry-redis
secret=kubefoundry-redis-auth
chart=$(phase3_resource_path redis-28.0.12.tgz)
values=$(phase3_resource_path values-sentinel.yaml)

for file in "${chart}" "${values}"; do
    [ -f "${file}" ] || { log_error "Redis 离线介质缺失: ${file}"; exit 1; }
done

storage_class=${KF_REDIS_STORAGE_CLASS:-}
if [ -z "${storage_class}" ]; then
    storage_class=$(kubectl get storageclass \
        -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}')
fi
[ "$(printf '%s\n' "${storage_class}" | sed '/^$/d' | wc -l)" -eq 1 ] \
    && [[ "${storage_class}" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ ]] \
    && kubectl get storageclass "${storage_class}" >/dev/null 2>&1 || {
    log_error "Redis Sentinel 未找到唯一可用的 StorageClass"
    exit 1
}

work_dir=$(mktemp -d)
trap 'rm -rf -- "${work_dir}"' EXIT
rendered_values="${work_dir}/values-sentinel.yaml"
sed "s|openebs-hostpath|${storage_class}|g" "${values}" > "${rendered_values}"

phase3_ensure_namespace "${namespace}"

if kubectl get secret "${secret}" --namespace "${namespace}" >/dev/null 2>&1; then
    managed_by=$(kubectl get secret "${secret}" --namespace "${namespace}" \
        -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}')
    component_group=$(kubectl get secret "${secret}" --namespace "${namespace}" \
        -o jsonpath='{.metadata.labels.kubefoundry\.io/component-group}')
    password_data=$(kubectl get secret "${secret}" --namespace "${namespace}" \
        -o jsonpath='{.data.redis-password}')
    [ "${managed_by}" = kubefoundry ] && [ "${component_group}" = redis_sentinel ] \
        && [ -n "${password_data}" ] || {
            log_error "Redis 密码 Secret 已存在但不属于 KubeFoundry 或缺少 redis-password"
            exit 1
        }
else
    umask 077
    secret_manifest="${work_dir}/redis-secret.yaml"
    password=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
    [ "${#password}" -eq 64 ] || { log_error "Redis 密码生成失败"; exit 1; }
    password_data=$(printf '%s' "${password}" | base64 | tr -d '\n')
    unset password
    cat > "${secret_manifest}" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${secret}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/managed-by: kubefoundry
    kubefoundry.io/component-group: redis_sentinel
type: Opaque
data:
  redis-password: ${password_data}
EOF
    unset password_data
    chmod 0600 "${secret_manifest}"
    phase3_apply_managed "${secret_manifest}" >/dev/null
    rm -f -- "${secret_manifest}"
fi

export KF_HELM_ATOMIC=1
phase3_helm_upgrade "${release}" "${namespace}" "${chart}" -f "${rendered_values}"
log_success "Redis Sentinel 安装命令执行完成"
