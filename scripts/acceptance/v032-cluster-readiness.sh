#!/bin/bash

#===============================================================================
# 脚本名称：v032-cluster-readiness.sh
# 功能：只读检查 v0.3.2 完整安装候选集群并输出脱敏验收摘要
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

set -o errexit -o nounset -o pipefail

: "${KUBECONFIG:=/etc/kubernetes/admin.conf}"
export KUBECONFIG
expect_redis="${KF_EXPECT_REDIS:-1}"
expect_minio="${KF_EXPECT_MINIO:-1}"
expect_etcd_backup="${KF_EXPECT_ETCD_BACKUP:-1}"
backup_dir="${KF_ETCD_BACKUP_DIR:-/var/backups/kubefoundry/etcd}"

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

validate_flag() {
    case "$2" in
        0|1) ;;
        *) fail "$1 必须是 0 或 1" ;;
    esac
}

validate_flag KF_EXPECT_REDIS "${expect_redis}"
validate_flag KF_EXPECT_MINIO "${expect_minio}"
validate_flag KF_EXPECT_ETCD_BACKUP "${expect_etcd_backup}"

for tool in kubectl awk grep; do
    command -v "${tool}" >/dev/null 2>&1 || fail "缺少只读验收工具: ${tool}"
done
[ -r "${KUBECONFIG}" ] || fail "Kubeconfig 不可读"

readyz="$(kubectl get --raw=/readyz 2>/dev/null)" || fail "Kubernetes API 不可达"
[ "${readyz}" = ok ] || fail "Kubernetes API 未就绪"

nodes_file="$(mktemp)"
pods_file="$(mktemp)"
trap 'rm -f -- "${nodes_file}" "${pods_file}"' EXIT

kubectl get nodes --no-headers \
    -o 'custom-columns=NAME:.metadata.name,INTERNAL_IP:.status.addresses[?(@.type=="InternalIP")].address,READY:.status.conditions[?(@.type=="Ready")].status' \
    > "${nodes_file}" || fail "无法读取节点状态"
[ -s "${nodes_file}" ] || fail "集群没有节点"
printf '%s\n' '[INFO] 节点状态（名称、InternalIP、Ready）：'
cat "${nodes_file}"
awk '$3 != "True" { failed = 1 } END { exit failed }' "${nodes_file}" \
    || fail "存在未 Ready 节点，不能进入完整安装动态验收"

kubectl get pods --all-namespaces --no-headers \
    -o 'custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase' \
    | awk '$3 != "Running" && $3 != "Succeeded"' > "${pods_file}" \
    || fail "无法读取 Pod 状态"
if [ -s "${pods_file}" ]; then
    printf '%s\n' '[ERROR] 存在非 Running/Succeeded Pod：' >&2
    cat "${pods_file}" >&2
    exit 1
fi

if [ "${expect_redis}" = 1 ]; then
    command -v helm >/dev/null 2>&1 || fail "缺少只读验收工具: helm"
    helm status kubefoundry-redis --namespace redis-sentinel >/dev/null \
        || fail "Redis Sentinel Helm release 不可用"
    kubectl rollout status statefulset/kubefoundry-redis-node \
        --namespace redis-sentinel --timeout=1s >/dev/null \
        || fail "Redis Sentinel StatefulSet 未就绪"
fi

if [ "${expect_minio}" = 1 ]; then
    tenant_count="$(kubectl get tenants.minio.min.io --all-namespaces --no-headers 2>/dev/null \
        | awk 'END { print NR + 0 }')"
    [ "${tenant_count}" -ge 1 ] || fail "未找到 MinIO Tenant"
    kubectl get pods --namespace minio-tenant \
        -l 'v1.min.io/tenant=kubefoundry-minio' --no-headers >/dev/null \
        || fail "无法读取 MinIO Tenant Pod"
fi

if [ "${expect_etcd_backup}" = 1 ]; then
    for tool in systemctl find sha256sum stat; do
        command -v "${tool}" >/dev/null 2>&1 || fail "缺少只读验收工具: ${tool}"
    done
    systemctl is-enabled --quiet kubefoundry-etcd-backup.timer \
        || fail "etcd 备份 timer 未启用"
    systemctl is-active --quiet kubefoundry-etcd-backup.timer \
        || fail "etcd 备份 timer 未运行"
    [ -d "${backup_dir}" ] && [ ! -L "${backup_dir}" ] \
        || fail "etcd 备份目录不存在或不安全"
    [ "$(stat -c '%a' "${backup_dir}")" = 700 ] || fail "etcd 备份目录权限不是 700"
    newest="$(find "${backup_dir}" -maxdepth 1 -type f \
        -name 'kubefoundry-etcd-????????T??????Z.db' -printf '%f\n' | sort -r | head -n 1)"
    [ -n "${newest}" ] || fail "未找到 KubeFoundry etcd 快照"
    [ -s "${backup_dir}/${newest}.status.json" ] || fail "etcd 快照状态文件缺失"
    (cd "${backup_dir}" && sha256sum --check --strict "${newest}.sha256" >/dev/null) \
        || fail "etcd 快照 SHA-256 校验失败"
    printf '[INFO] 最新 etcd 快照：%s\n' "${newest}"
fi

printf '%s\n' '[SUCCESS] v0.3.2 集群只读验收预检通过'
