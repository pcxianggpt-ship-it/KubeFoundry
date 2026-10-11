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
release=redis
secret=redis-auth
chart=$(phase3_resource_path redis-28.0.12.tgz)
values=$(phase3_resource_path values-sentinel.yaml)

for file in "${chart}" "${values}"; do
    [ -f "${file}" ] || { log_error "Redis 离线介质缺失: ${file}"; exit 1; }
done

# 旧 release 的数据卷不能通过重命名原地迁移，避免创建第二套 Redis。
if helm status kubefoundry-redis --namespace "${namespace}" >/dev/null 2>&1; then
    log_error "检测到旧 Redis release，请先完成数据迁移或重置后再安装新命名版本"
    exit 1
fi

storage_class=${KF_REDIS_STORAGE_CLASS:-localpath}
[[ "${storage_class}" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ ]] \
    && kubectl get storageclass "${storage_class}" >/dev/null 2>&1 || {
    log_error "Redis Sentinel 所需 StorageClass 不存在: ${storage_class}"
    exit 1
}

work_dir=$(mktemp -d)
trap 'rm -rf -- "${work_dir}"' EXIT
rendered_values="${work_dir}/values-sentinel.yaml"
sed "s|localpath|${storage_class}|g" "${values}" > "${rendered_values}"

phase3_ensure_namespace "${namespace}"

configured_password_data=
set +x
if [ -n "${KF_REDIS_PASSWORD_FILE:-}" ]; then
    [ -f "${KF_REDIS_PASSWORD_FILE}" ] && [ ! -L "${KF_REDIS_PASSWORD_FILE}" ] \
        && [ -r "${KF_REDIS_PASSWORD_FILE}" ] && [ -s "${KF_REDIS_PASSWORD_FILE}" ] || {
        log_error "Redis 密码配置文件不可读或为空"
        exit 1
    }
    configured_password_data=$(base64 < "${KF_REDIS_PASSWORD_FILE}" | tr -d '\n')
fi

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
    if [ -n "${configured_password_data}" ] && [ "${password_data}" != "${configured_password_data}" ]; then
        log_error "已有 Redis 密码与配置不一致，请先重置 Redis 组件；不支持在线改密"
        exit 1
    fi
else
    umask 077
    secret_manifest="${work_dir}/redis-secret.yaml"
    if [ -n "${configured_password_data}" ]; then
        password_data=${configured_password_data}
    else
        password=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
        [ "${#password}" -eq 64 ] || { log_error "Redis 密码生成失败"; exit 1; }
        password_data=$(printf '%s' "${password}" | base64 | tr -d '\n')
        unset password
    fi
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
    # kubectl 的失败输出可能包含 Secret 内容，不写入安装日志。
    if ! kubectl apply --server-side --field-manager=kubefoundry --force-conflicts \
            -f "${secret_manifest}" >"${work_dir}/secret-apply.log" 2>&1; then
        log_error "Redis 密码 Secret 创建失败，请检查 Kubernetes API 和资源权限"
        exit 1
    fi
    rm -f -- "${secret_manifest}"
fi
unset configured_password_data password_data

export KF_HELM_ATOMIC=1
phase3_helm_upgrade "${release}" "${namespace}" "${chart}" -f "${rendered_values}"
log_success "Redis Sentinel 安装命令执行完成"
