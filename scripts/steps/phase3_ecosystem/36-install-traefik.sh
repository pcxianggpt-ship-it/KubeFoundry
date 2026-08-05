#!/bin/bash

#===============================================================================
# 脚本名称：36-install-traefik.sh
# 功能：在主控节点声明式安装 Traefik 网关
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
manifest_dir=$(phase3_resource_path .)
[ -d "${manifest_dir}" ] || {
    log_error "Traefik 清单目录不存在: ${manifest_dir}"
    exit 1
}

nodeports=$(grep -RhoE 'nodePort:[[:space:]]*[0-9]+' "${manifest_dir}" 2>/dev/null \
    | awk '{ print $2 }' | sort -u || true)
existing=$(kubectl get service --all-namespaces --no-headers 2>/dev/null || true)
while IFS= read -r port; do
    [ -z "${port}" ] && continue
    if printf '%s\n' "${existing}" | awk -v port="${port}" '$0 ~ (":" port "/") && $2 !~ /^traefik($|-)/ { found=1 } END { exit found }'; then
        :
    else
        log_error "Traefik NodePort 已被占用: ${port}"
        exit 1
    fi
done <<< "${nodeports}"

kubectl apply --server-side --field-manager=kubefoundry -f "${manifest_dir}"
deployments=$(kubectl get deployment --all-namespaces --no-headers 2>/dev/null \
    | awk '$2 ~ /^traefik($|-)/ { print $1 "/" $2 }')
while IFS= read -r target; do
    [ -z "${target}" ] && continue
    namespace=${target%%/*}
    name=${target#*/}
    phase3_wait_rollout deployment "${name}" "${namespace}"
done <<< "${deployments}"

services=$(kubectl get service --all-namespaces --no-headers 2>/dev/null \
    | awk '$2 ~ /^traefik($|-)/ { print $1 "/" $2 }')
[ -n "${services}" ] || {
    log_error "Traefik Service 未创建"
    exit 1
}
log_success "Traefik 网关已幂等安装并通过 rollout 检查"
