#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
BIN="${TMP}/bin"
MEDIA="${TMP}/redis"
mkdir -p "${BIN}" "${MEDIA}"
cp "${ROOT}/kube-media/03.setup_file/v1.30.14/helmapp/redis/redis-28.0.12.tgz" \
    "${ROOT}/kube-media/03.setup_file/v1.30.14/helmapp/redis/values-sentinel.yaml" "${MEDIA}/"

cat > "${BIN}/helm" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_REDIS_HELM_LOG}"
for argument in "$@"; do
  if [ -f "${argument}" ] && grep -q '^    storageClass: localpath$' "${argument}"; then
    : > "${KF_REDIS_RENDERED_VALUES_OK}"
  fi
done
case "$*" in
  *"status kubefoundry-redis --namespace redis-sentinel"*) exit "${KF_REDIS_LEGACY_STATUS:-1}" ;;
  *"status redis --namespace redis-sentinel -o json"*)
    printf '%s\n' '{"info":{"status":"deployed"}}' ;;
esac
exit 0
EOF
cat > "${BIN}/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_REDIS_CURL_LOG}"
# 安装不应访问镜像仓库；任何预检查请求均失败。
exit 22
EOF
cat > "${BIN}/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_REDIS_KUBECTL_LOG}"
args="$*"
case "${args}" in
  *"get --raw=/readyz"*) printf 'ok\n' ;;
  *"get storageclass localpath"*) [ "${KF_REDIS_STORAGE_MISSING:-0}" = 0 ] || exit 1 ;;
  *"get namespace redis-sentinel"*)
    [ -f "${KF_REDIS_NAMESPACE_STATE}" ] || exit 1 ;;
  *"create namespace redis-sentinel"*) touch "${KF_REDIS_NAMESPACE_STATE}" ;;
  *"get secret redis-auth"*)
    if [ "${KF_REDIS_SECRET_MODE:-managed}" = absent ] || [ ! -f "${KF_REDIS_SECRET_STATE}" ]; then
      exit 1
    fi
    case "${args}" in
      *"metadata.labels.app"*)
        [ "${KF_REDIS_SECRET_MODE:-managed}" = unmanaged ] && printf 'other' || printf 'kubefoundry' ;;
      *"metadata.labels.kubefoundry"*) printf 'redis_sentinel' ;;
      *"data.redis-password"*) printf 'c2VjcmV0LXJlZGlzLXZhbHVl' ;;
    esac
    ;;
  *"apply --server-side"*)
    for argument in "$@"; do
      if [ -f "${argument}" ] && grep -q '^kind: Secret$' "${argument}"; then
        touch "${KF_REDIS_SECRET_STATE}"
      fi
    done
    ;;
  *"label --overwrite"*) : ;;
  *"get statefulset --namespace"*"--selector"*) printf '%s\n' "${KF_REDIS_STATEFULSET:-redis-node}" ;;
  *"get statefulset "*"redis-password"*) printf '%s' "${KF_REDIS_AUTH_SECRET:-redis-auth}" ;;
  *"get statefulset "*"spec.replicas"*) printf '3|3' ;;
  *"get statefulset "*) : ;;
  *"rollout status statefulset/"*) : ;;
  *"get pods"*"app.kubernetes.io/instance=redis"*)
    printf '%s-0\n%s-1\n%s-2\n' "${KF_REDIS_STATEFULSET:-redis-node}" \
      "${KF_REDIS_STATEFULSET:-redis-node}" "${KF_REDIS_STATEFULSET:-redis-node}" ;;
  *"get pvc"*"app.kubernetes.io/instance=redis"*)
    printf '%s|%s|%s\nredis-data-redis-node-1|Bound|localpath\nredis-data-redis-node-2|Bound|localpath\n' \
      "${KF_REDIS_PVC_NAME:-redis-data-redis-node-0}" "${KF_REDIS_PVC_PHASE:-Bound}" "${KF_REDIS_PVC_STORAGE:-localpath}" ;;
  *"exec -i"*"SENTINEL master redis-master"*)
    printf 'name\nredis-master\nip\n%s-0.redis-headless.redis-sentinel.svc.cluster.local\nport\n6379\nquorum\n2\n' "${KF_REDIS_STATEFULSET:-redis-node}" ;;
  *"exec -i"*"SENTINEL get-master-addr-by-name redis-master"*)
    printf '%s-0.redis-headless.redis-sentinel.svc.cluster.local\n6379\n' "${KF_REDIS_STATEFULSET:-redis-node}" ;;
  *"exec -i ${KF_REDIS_STATEFULSET:-redis-node}-0"*" ROLE"*) printf 'master\n' ;;
  *"exec -i ${KF_REDIS_STATEFULSET:-redis-node}-1"*" ROLE"*|*"exec -i ${KF_REDIS_STATEFULSET:-redis-node}-2"*" ROLE"*)
    printf 'slave\n' ;;
esac
exit 0
EOF
chmod +x "${BIN}"/*

export PATH="${BIN}:${PATH}"
export PROJECT_ROOT="${ROOT}"
export KF_COMPONENT_RESOURCE_DIR="${MEDIA}"
export KF_COMPONENT_GROUP_KEY=redis_sentinel
export KF_COMPONENT_MEDIA_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export KF_REDIS_HELM_LOG="${TMP}/helm.log"
export KF_REDIS_KUBECTL_LOG="${TMP}/kubectl.log"
export KF_REDIS_CURL_LOG="${TMP}/curl.log"
export KF_REDIS_RENDERED_VALUES_OK="${TMP}/rendered-values-ok"
export KF_REDIS_NAMESPACE_STATE="${TMP}/namespace"
export KF_REDIS_SECRET_STATE="${TMP}/secret"
export KF_REDIS_SECRET_MODE=absent
export KF_VERIFY_COMMAND_TIMEOUT=2s
export KF_VERIFY_ROLLOUT_TIMEOUT=2s
export KF_KUBECONFIG="${TMP}/admin.conf"
touch "${KF_KUBECONFIG}" "${KF_REDIS_CURL_LOG}"
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "$*" >&2; }
export -f log_info log_success log_warn log_error

# 仅提供 Chart 和 values，修改 values 后无需维护摘要文件。
printf '\n# local configuration\n' >> "${MEDIA}/values-sentinel.yaml"
bash "${ROOT}/scripts/steps/phase3_ecosystem/43-install-redis-sentinel.sh"
export KF_REDIS_SECRET_MODE=managed
bash "${ROOT}/scripts/verify/phase3_ecosystem/verify-43-install-redis-sentinel.sh"
# 验证不能把旧名称、错误存储类、未绑定卷或错误认证引用判断为成功。
for invalid in \
    KF_REDIS_STATEFULSET=legacy-redis-node \
    KF_REDIS_PVC_NAME=redis-data-legacy-redis-node-0 \
    KF_REDIS_PVC_STORAGE=nfs-storage \
    KF_REDIS_PVC_PHASE=Pending \
    KF_REDIS_AUTH_SECRET=legacy-redis-auth; do
    if env "${invalid}" bash "${ROOT}/scripts/verify/phase3_ecosystem/verify-43-install-redis-sentinel.sh" \
        > "${TMP}/invalid.log" 2>&1; then
        printf 'Redis 验证未拒绝不匹配的配置: %s\n' "${invalid}" >&2
        exit 1
    fi
done

# 缺少本地存储类时不能回退到默认 NFS；旧 release 不能与新 release 并行安装。
for invalid in KF_REDIS_STORAGE_MISSING=1 KF_REDIS_LEGACY_STATUS=0; do
    : > "${KF_REDIS_HELM_LOG}"
    if env "${invalid}" bash "${ROOT}/scripts/steps/phase3_ecosystem/43-install-redis-sentinel.sh" \
        > "${TMP}/invalid-install.log" 2>&1; then
        printf 'Redis 安装未拒绝不匹配的环境: %s\n' "${invalid}" >&2
        exit 1
    fi
    ! grep -q '^upgrade ' "${KF_REDIS_HELM_LOG}"
done
bash "${ROOT}/scripts/steps/phase3_ecosystem/43-install-redis-sentinel.sh"

test -f "${KF_REDIS_RENDERED_VALUES_OK}"

grep -q -- '^upgrade --install redis .*redis-28.0.12.tgz --namespace redis-sentinel .*--atomic .*--labels app.kubernetes.io/managed-by=kubefoundry,kubefoundry.io/component-group=redis_sentinel,kubefoundry.io/media-sha256=' \
    "${KF_REDIS_HELM_LOG}"
test ! -s "${KF_REDIS_CURL_LOG}"
redis_image=$(sed -n '/^image:$/,/^master:$/p' "${MEDIA}/values-sentinel.yaml")
sentinel_image=$(sed -n '/^sentinel:$/,/^networkPolicy:$/p' "${MEDIA}/values-sentinel.yaml")
for image_values in "${redis_image}" "${sentinel_image}"; do
    grep -q 'tag: "8.10.1"' <<< "${image_values}"
    grep -q 'digest: ""' <<< "${image_values}"
    ! grep -q 'sha256:' <<< "${image_values}"
done
! grep -Eq 'secret-redis-value|c2VjcmV0LXJlZGlzLXZhbHVl' \
    "${KF_REDIS_HELM_LOG}" "${KF_REDIS_KUBECTL_LOG}" "${KF_REDIS_CURL_LOG}"

export KF_REDIS_SECRET_MODE=unmanaged
if bash "${ROOT}/scripts/steps/phase3_ecosystem/43-install-redis-sentinel.sh" >/dev/null 2>&1; then
    printf '未拒绝非 KubeFoundry 所有的 Redis Secret\n' >&2
    exit 1
fi

! grep -qi 'kubefoundry' "${ROOT}/scripts/verify/phase3_ecosystem/verify-43-install-redis-sentinel.sh"
grep -q '^  existingSecret: redis-auth$' "${MEDIA}/values-sentinel.yaml"
grep -q '^  masterSet: redis-master$' "${MEDIA}/values-sentinel.yaml"
grep -q '^architecture: replication$'  "${MEDIA}/values-sentinel.yaml"
grep -q '^fullnameOverride: redis$' "${MEDIA}/values-sentinel.yaml"
grep -q '^  replicaCount: 3$' "${MEDIA}/values-sentinel.yaml"
grep -q '^  quorum: 2$' "${MEDIA}/values-sentinel.yaml"
grep -q '^    storageClass: localpath$' "${MEDIA}/values-sentinel.yaml"
! grep -Eq 'redis-ha|allyaml|redis-sentinel-pvc' \
    "${ROOT}/scripts/steps/phase3_ecosystem/43-install-redis-sentinel.sh"
bash -n "${ROOT}/scripts/acceptance/redis-sentinel-failover.sh"
grep -q 'KF_ACCEPT_REDIS_FAILOVER.*YES' "${ROOT}/scripts/acceptance/redis-sentinel-failover.sh"
if bash "${ROOT}/scripts/acceptance/redis-sentinel-failover.sh" >/dev/null 2>&1; then
    printf 'Redis 故障切换验收缺少破坏性确认保护\n' >&2
    exit 1
fi

printf 'redis sentinel tests passed\n'
