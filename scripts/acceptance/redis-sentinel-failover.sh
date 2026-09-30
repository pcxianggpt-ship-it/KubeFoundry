#!/bin/bash

# Redis Sentinel 真实故障切换验收。仅在明确确认后删除当前 master Pod。
set -o errexit -o nounset -o pipefail

[ "${KF_ACCEPT_REDIS_FAILOVER:-}" = YES ] || {
    printf '[ERROR] 该验收会删除当前 Redis master Pod；请显式设置 KF_ACCEPT_REDIS_FAILOVER=YES\n' >&2
    exit 64
}

: "${KUBECONFIG:=/etc/kubernetes/admin.conf}"
export KUBECONFIG
namespace=redis-sentinel
selector='app.kubernetes.io/instance=kubefoundry-redis,app.kubernetes.io/name=redis'
master_set=kubefoundry-master
timeout_seconds=${KF_REDIS_FAILOVER_TIMEOUT_SECONDS:-240}
[[ "${timeout_seconds}" =~ ^[0-9]+$ ]] && [ "${timeout_seconds}" -ge 30 ] || {
    printf '[ERROR] KF_REDIS_FAILOVER_TIMEOUT_SECONDS 必须是不小于 30 的整数\n' >&2
    exit 64
}

password_file=$(mktemp)
trap 'rm -f -- "${password_file}"' EXIT
chmod 0600 "${password_file}"
kubectl get secret kubefoundry-redis-auth --namespace "${namespace}" \
    -o jsonpath='{.data.redis-password}' | base64 --decode > "${password_file}"
[ -s "${password_file}" ] || { printf '[ERROR] Redis 密码为空\n' >&2; exit 1; }
printf '\n' >> "${password_file}"

redis_cli() {
    local pod="$1" container="$2"
    shift 2
    kubectl exec -i "${pod}" --namespace "${namespace}" -c "${container}" -- \
        sh -c 'IFS= read -r REDISCLI_AUTH; export REDISCLI_AUTH; exec redis-cli "$@"' sh "$@" \
        < "${password_file}"
}

mapfile -t pods < <(kubectl get pods --namespace "${namespace}" --selector "${selector}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
[ "${#pods[@]}" -eq 3 ] || { printf '[ERROR] Redis Pod 数量不是 3\n' >&2; exit 1; }

master_address=$(redis_cli "${pods[0]}" sentinel -p 26379 SENTINEL get-master-addr-by-name \
    "${master_set}")
old_master_host=$(printf '%s\n' "${master_address}" | head -n 1)
old_master_pod=${old_master_host%%.*}
printf '%s\n' "${pods[@]}" | grep -Fxq "${old_master_pod}" || {
    printf '[ERROR] Sentinel 返回的 master 不属于当前 StatefulSet\n' >&2
    exit 1
}

key="kubefoundry:acceptance:$(date +%s):$$"
value=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
redis_cli "${old_master_pod}" redis SET "${key}" "${value}" >/dev/null
[ "$(redis_cli "${old_master_pod}" redis GET "${key}")" = "${value}" ] || {
    printf '[ERROR] Redis 故障切换前读写校验失败\n' >&2
    exit 1
}

printf '[INFO] 删除当前 master Pod 并等待 Sentinel 切换: %s\n' "${old_master_pod}"
kubectl delete pod "${old_master_pod}" --namespace "${namespace}" --wait=false >/dev/null

deadline=$((SECONDS + timeout_seconds))
new_master_pod=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
    for sentinel_pod in "${pods[@]}"; do
        [ "${sentinel_pod}" = "${old_master_pod}" ] && continue
        if address=$(redis_cli "${sentinel_pod}" sentinel -p 26379 SENTINEL \
                get-master-addr-by-name "${master_set}" 2>/dev/null); then
            candidate=${address%%$'\n'*}
            candidate=${candidate%%.*}
            if [ -n "${candidate}" ] && [ "${candidate}" != "${old_master_pod}" ]; then
                new_master_pod=${candidate}
                break 2
            fi
        fi
    done
    sleep 3
done
[ -n "${new_master_pod}" ] || { printf '[ERROR] Sentinel 未在超时内完成切换\n' >&2; exit 1; }

[ "$(redis_cli "${new_master_pod}" redis GET "${key}")" = "${value}" ] || {
    printf '[ERROR] Redis 故障切换后数据读取失败\n' >&2
    exit 1
}
redis_cli "${new_master_pod}" redis DEL "${key}" >/dev/null
kubectl rollout status statefulset/redis-node --namespace "${namespace}" \
    --timeout="${timeout_seconds}s" >/dev/null
printf '[SUCCESS] Redis Sentinel 已从 %s 切换到 %s，读写数据保持正常\n' \
    "${old_master_pod}" "${new_master_pod}"
