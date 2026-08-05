#!/bin/bash

#===============================================================================
# 脚本名称：verify-36-install-traefik.sh
# 功能：在当前主控节点验证 Traefik 网关
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
targets=$(kubectl get deployment --all-namespaces --no-headers 2>/dev/null \
    | awk '$2 ~ /^traefik($|-)/ { print $1 "/" $2 }')
[ -n "${targets}" ] || {
    log_error "未找到 Traefik Deployment"
    exit 1
}
while IFS= read -r target; do
    namespace=${target%%/*}
    name=${target#*/}
    phase3_wait_rollout deployment "${name}" "${namespace}"
done <<< "${targets}"
services=$(kubectl get service --all-namespaces --no-headers 2>/dev/null \
    | awk '$2 ~ /^traefik($|-)/ { print $1 "/" $2 }')
[ -n "${services}" ] || {
    log_error "未找到 Traefik Service"
    exit 1
}
log_success "Traefik 工作负载和 Service 验证通过"
