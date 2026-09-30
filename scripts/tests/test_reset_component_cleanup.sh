#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
BIN="${TMP}/bin"
mkdir -p "${BIN}"

cat > "${BIN}/helm" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_RESET_HELM_LOG}"
if [ "$1" = get ] && [ "$2" = metadata ]; then
    if [ "${KF_RESET_UNMANAGED_RELEASE:-0}" = 1 ]; then
        printf '%s\n' '{"labels":{"app.kubernetes.io/managed-by":"other"}}'
    else
        printf '%s\n' '{"labels":{"app.kubernetes.io/managed-by":"kubefoundry","kubefoundry.io/media-sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
    fi
fi
exit 0
EOF
cat > "${BIN}/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_RESET_KUBECTL_LOG}"
exit 0
EOF
chmod +x "${BIN}"/*

export PATH="${BIN}:${PATH}"
export KF_RESET_HELM_LOG="${TMP}/helm.log"
export KF_RESET_KUBECTL_LOG="${TMP}/kubectl.log"
export KUBECONFIG="${TMP}/admin.conf"
export KF_RESET_COMPONENT_GROUPS='nfs,kubemate,traefik,storage_observability,prometheus,redis_sentinel'
export KF_RESET_HELM_RELEASE_CHECKSUMS='alloy=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,loki=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,openebs=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,nfs-subdir-external-provisioner=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,kubefoundry-redis=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
touch "${KUBECONFIG}"
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "$*" >&2; }
export -f log_info log_success log_warn log_error

bash "${ROOT}/scripts/steps/reset/reset-kubemate-components.sh"
grep -Fxq 'uninstall alloy --namespace kubemate-system --wait --timeout 10m' "${KF_RESET_HELM_LOG}"
grep -Fxq 'uninstall loki --namespace kubemate-system --wait --timeout 10m' "${KF_RESET_HELM_LOG}"
grep -Fxq 'uninstall openebs --namespace kubemate-system --wait --timeout 10m' "${KF_RESET_HELM_LOG}"
grep -Fxq 'uninstall nfs-subdir-external-provisioner --namespace kubemate-system --wait --timeout 10m' \
    "${KF_RESET_HELM_LOG}"
grep -Fxq 'uninstall kubefoundry-redis --namespace redis-sentinel --wait --timeout 10m' \
    "${KF_RESET_HELM_LOG}"
grep -Fq -- '--selector app.kubernetes.io/managed-by=kubefoundry,kubefoundry.io/component-group=redis_sentinel' \
    "${KF_RESET_KUBECTL_LOG}"
test "$(grep -nF 'uninstall alloy' "${KF_RESET_HELM_LOG}" | cut -d: -f1)" \
    -lt "$(grep -nF 'uninstall loki' "${KF_RESET_HELM_LOG}" | cut -d: -f1)"
test "$(grep -nF 'uninstall loki' "${KF_RESET_HELM_LOG}" | cut -d: -f1)" \
    -lt "$(grep -nF 'uninstall openebs' "${KF_RESET_HELM_LOG}" | cut -d: -f1)"
grep -Fq -- '--selector app.kubernetes.io/managed-by=kubefoundry,kubefoundry.io/component-group=kubemate' \
    "${KF_RESET_KUBECTL_LOG}"

if KF_RESET_COMPONENT_GROUPS='nfs,unknown' bash "${ROOT}/scripts/steps/reset/reset-kubemate-components.sh"; then
    printf '%s\n' '不安全组件组列表未被拒绝' >&2
    exit 1
fi

: > "${KF_RESET_HELM_LOG}"
export KF_RESET_COMPONENT_GROUPS=nfs
export KF_RESET_HELM_RELEASE_CHECKSUMS='nfs-subdir-external-provisioner=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
export KF_RESET_UNMANAGED_RELEASE=1
bash "${ROOT}/scripts/steps/reset/reset-kubemate-components.sh"
! grep -Fq 'uninstall nfs-subdir-external-provisioner' "${KF_RESET_HELM_LOG}"
unset KF_RESET_UNMANAGED_RELEASE

# 仅加载节点重置脚本的函数定义，避免测试环境执行真实 kubeadm reset。
source <(awk '/^require_safe_work_dir "\$\{KF_K8S_HOME:-\}"/{exit} {print}' \
    "${ROOT}/scripts/steps/reset/reset-kubernetes-node.sh")

FSTAB="${TMP}/fstab"
cat > "${FSTAB}" <<'EOF'
UUID=user-root / ext4 defaults 0 1
# >>>KubeFoundry NFS fstab>>>
10.0.0.10:/srv/share /data/kubefoundry-nfs nfs defaults,_netdev 0 0
# <<<KubeFoundry NFS fstab<<<
UUID=user-data /data ext4 defaults 0 2
EOF
remove_managed_block "${FSTAB}" '# >>>KubeFoundry NFS fstab>>>' '# <<<KubeFoundry NFS fstab<<<'
grep -Fq 'UUID=user-root / ext4 defaults 0 1' "${FSTAB}"
grep -Fq 'UUID=user-data /data ext4 defaults 0 2' "${FSTAB}"
! grep -Fq 'KubeFoundry NFS fstab' "${FSTAB}"

cat > "${FSTAB}" <<'EOF'
# >>>KubeFoundry NFS fstab>>>
10.0.0.10:/srv/share /data/kubefoundry-nfs nfs defaults,_netdev 0 0
# <<<KubeFoundry NFS fstab<<<
# >>>KubeFoundry NFS fstab>>>
10.0.0.10:/srv/share /data/kubefoundry-nfs nfs defaults,_netdev 0 0
# <<<KubeFoundry NFS fstab<<<
EOF
if (remove_managed_block "${FSTAB}" '# >>>KubeFoundry NFS fstab>>>' '# <<<KubeFoundry NFS fstab<<<'); then
    printf '%s\n' '重复受管标记块未被拒绝' >&2
    exit 1
fi
test "$(grep -cF '# >>>KubeFoundry NFS fstab>>>' "${FSTAB}")" -eq 2

# 基线恢复只在当前文件仍匹配安装后校验和时执行。
STATE_DIR="${TMP}/managed-config"
managed_state_dir() { printf '%s\n' "${STATE_DIR}"; }
manifest_target_allowed() { return 0; }
mkdir -p "${STATE_DIR}/baseline"
chmod 0700 "${STATE_DIR}" "${STATE_DIR}/baseline"
TARGET_CONFIG="${TMP}/containerd.toml"
BASELINE="${STATE_DIR}/baseline/containerd.config"
printf '%s\n' 'original-user-config' > "${BASELINE}"
printf '%s\n' 'kubefoundry-managed-config' > "${TARGET_CONFIG}"
chmod 0600 "${BASELINE}"
original_sha=$(sha256sum "${BASELINE}" | awk '{print $1}')
managed_sha=$(sha256sum "${TARGET_CONFIG}" | awk '{print $1}')
printf 'containerd.config\t%s\t%s\t%s\t%s\t640\t%s\t%s\n' \
    "${TARGET_CONFIG}" "${original_sha}" "${BASELINE}" "${managed_sha}" "$(id -u)" "$(id -g)" \
    > "${STATE_DIR}/manifest.tsv"
chmod 0600 "${STATE_DIR}/manifest.tsv"
preflight_replacement_manifest
restore_replacement_manifest
grep -Fqx 'original-user-config' "${TARGET_CONFIG}"
test "$(stat -c '%a' "${TARGET_CONFIG}")" = 640
test ! -e "${STATE_DIR}"

mkdir -p "${STATE_DIR}/baseline"
chmod 0700 "${STATE_DIR}" "${STATE_DIR}/baseline"
printf '%s\n' 'original-user-config' > "${BASELINE}"
printf '%s\n' 'user-modified-after-install' > "${TARGET_CONFIG}"
chmod 0600 "${BASELINE}"
printf 'containerd.config\t%s\t%s\t%s\t%s\t640\t%s\t%s\n' \
    "${TARGET_CONFIG}" "${original_sha}" "${BASELINE}" "${managed_sha}" "$(id -u)" "$(id -g)" \
    > "${STATE_DIR}/manifest.tsv"
chmod 0600 "${STATE_DIR}/manifest.tsv"
if (preflight_replacement_manifest); then
    printf '%s\n' '用户修改后的受管配置未被拒绝' >&2
    exit 1
fi
grep -Fqx 'user-modified-after-install' "${TARGET_CONFIG}"

rm -rf "${STATE_DIR}"
mkdir -p "${STATE_DIR}"
chmod 0700 "${STATE_DIR}"
if (preflight_replacement_manifest); then
    printf '%s\n' '缺少清单的受管状态目录未被拒绝' >&2
    exit 1
fi

printf 'reset component cleanup tests passed\n'
