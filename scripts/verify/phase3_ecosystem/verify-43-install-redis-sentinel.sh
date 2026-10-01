#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
kube() {
    local duration="$1"
    shift
    timeout --foreground "${duration}" env KUBECONFIG="${KF_KUBECONFIG}" \
        kubectl --request-timeout="${duration}" "$@"
    local status=$?
    case "${status}" in 124|137) printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21 ;; esac
    return "${status}"
}

namespace=redis-sentinel
release=redis
secret=redis-auth
selector='app.kubernetes.io/instance=redis,app.kubernetes.io/name=redis'
command_timeout=${KF_VERIFY_COMMAND_TIMEOUT:-30s}
rollout_timeout=${KF_VERIFY_ROLLOUT_TIMEOUT:-300s}
[ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
command -v kubectl >/dev/null 2>&1 || error "验证工具不可用: kubectl"
command -v helm >/dev/null 2>&1 || error "验证工具不可用: helm"
kube "${command_timeout}" get --raw=/readyz >/dev/null 2>&1 || error "Kubernetes API 验证异常"
storage_class=${KF_REDIS_STORAGE_CLASS:-localpath}
kube "${command_timeout}" get storageclass "${storage_class}" >/dev/null 2>&1 \
    || missing "Redis StorageClass 不存在: ${storage_class}"

release_status=$(timeout --foreground "${command_timeout}" env KUBECONFIG="${KF_KUBECONFIG}" \
    helm status "${release}" --namespace "${namespace}" -o json 2>/dev/null) || missing "Redis Helm release 不存在"
printf '%s\n' "${release_status}" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"deployed"' \
    || missing "Redis Helm release 未处于 deployed 状态"

statefulset=$(kube "${command_timeout}" get statefulset --namespace "${namespace}" \
    --selector "${selector}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null) \
    || error "Redis StatefulSet 查询失败"
[ "$(printf '%s\n' "${statefulset}" | sed '/^$/d' | wc -l)" -eq 1 ] \
    || missing "Redis release 未对应唯一 StatefulSet"
[ "${statefulset}" = redis-node ] || missing "Redis StatefulSet 名称不正确: ${statefulset}"

kube "${command_timeout}" get statefulset "${statefulset}" --namespace "${namespace}" \
    >/dev/null 2>&1 || missing "Redis StatefulSet 不存在"
kube "${rollout_timeout}" rollout status "statefulset/${statefulset}" \
    --namespace "${namespace}" --timeout="${rollout_timeout}" >/dev/null 2>&1 \
    || missing "Redis StatefulSet 未就绪"

replicas=$(kube "${command_timeout}" get statefulset "${statefulset}" \
    --namespace "${namespace}" -o jsonpath='{.spec.replicas}|{.status.readyReplicas}' 2>/dev/null)
[ "${replicas}" = '3|3' ] || missing "Redis 期望 3 个 Pod，当前副本状态为 ${replicas:-未知}"

mapfile -t pods < <(kube "${command_timeout}" get pods --namespace "${namespace}" \
    --selector "${selector}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
[ "${#pods[@]}" -eq 3 ] || missing "Redis Pod 数量不是 3"
[ "$(printf '%s\n' "${pods[@]}" | sort)" = "$(printf 'redis-node-0\nredis-node-1\nredis-node-2')" ] \
    || missing "Redis Pod 名称不正确"

pvc_status=$(kube "${command_timeout}" get pvc --namespace "${namespace}" \
    --selector 'app.kubernetes.io/instance=redis' \
    -o jsonpath='{range .items[*]}{.metadata.name}|{.status.phase}|{.spec.storageClassName}{"\n"}{end}' 2>/dev/null) \
    || error "Redis PVC 状态查询失败"
[ "$(printf '%s\n' "${pvc_status}" | sed '/^$/d' | wc -l)" -eq 3 ] \
    || missing "Redis PVC 数量不是 3"
[ "$(printf '%s\n' "${pvc_status}" | cut -d '|' -f1 | sort -u)" = \
    "$(printf 'redis-data-redis-node-0\nredis-data-redis-node-1\nredis-data-redis-node-2')" ] \
    || missing "Redis PVC 名称不正确"
while IFS='|' read -r pvc_name phase pvc_storage_class; do
    [ -z "${phase}" ] && continue
    [ "${phase}" = Bound ] && [ "${pvc_storage_class}" = "${storage_class}" ] \
        || missing "Redis PVC 未全部 Bound 或 StorageClass 不正确"
done <<< "${pvc_status}"

auth_secret=$(kube "${command_timeout}" get statefulset "${statefulset}" --namespace "${namespace}" \
    -o jsonpath='{.spec.template.spec.volumes[?(@.name=="redis-password")].secret.secretName}' 2>/dev/null) \
    || error "Redis 密码卷查询失败"
[ "${auth_secret}" = "${secret}" ] || missing "Redis 密码卷未引用 ${secret}"
password_base64=$(kube "${command_timeout}" get secret "${secret}" --namespace "${namespace}" \
    -o jsonpath='{.data.redis-password}' 2>/dev/null) || error "Redis 密码读取失败"
[ -n "${password_base64}" ] || error "Redis 密码为空"
printf '%s' "${password_base64}" | base64 --decode >/dev/null 2>&1 \
    || error "Redis 密码编码无效"

redis_cli() {
    local pod="$1" container="$2"
    shift 2
    printf '%s' "${password_base64}" | base64 --decode | \
        kube "${command_timeout}" exec -i "${pod}" --namespace "${namespace}" -c "${container}" -- \
            sh -c 'REDISCLI_AUTH=$(cat); export REDISCLI_AUTH; exec redis-cli "$@"' sh "$@"
}

sentinel_info=$(redis_cli "${pods[0]}" sentinel -p 26379 SENTINEL master redis-master 2>/dev/null) \
    || missing "Sentinel 无法查询 master"
quorum=$(printf '%s\n' "${sentinel_info}" | awk 'previous == "quorum" { print; exit } { previous = $0 }')
[ "${quorum}" = 2 ] || missing "Sentinel quorum 不是 2"
master_address=$(redis_cli "${pods[0]}" sentinel -p 26379 SENTINEL get-master-addr-by-name \
    redis-master 2>/dev/null) || missing "Sentinel 无法识别当前 master"
[ "$(printf '%s\n' "${master_address}" | sed '/^$/d' | wc -l)" -eq 2 ] \
    || missing "Sentinel 返回的 master 地址无效"
[ "$(printf '%s\n' "${master_address}" | tail -n 1)" = 6379 ] \
    || missing "Sentinel 返回的 master 端口无效"

master_count=0
replica_count=0
for pod in "${pods[@]}"; do
    role=$(redis_cli "${pod}" redis ROLE 2>/dev/null | head -n 1) \
        || missing "Redis 复制角色查询失败: ${pod}"
    case "${role}" in
        master) master_count=$((master_count + 1)) ;;
        slave|replica) replica_count=$((replica_count + 1)) ;;
        *) missing "Redis 返回未知复制角色: ${pod}" ;;
    esac
done
[ "${master_count}" -eq 1 ] && [ "${replica_count}" -eq 2 ] \
    || missing "Redis 复制拓扑异常: master=${master_count}, replica=${replica_count}"

printf '[SUCCESS] Redis Sentinel release、3 Pod、quorum、复制链路和 PVC 已就绪\n'
