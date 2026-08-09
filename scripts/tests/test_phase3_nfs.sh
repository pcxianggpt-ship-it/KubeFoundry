#!/bin/bash
set -o errexit -o nounset -o pipefail

# NFS phase3 脚本的离线行为测试：无 SSH、重复执行不重复写入。
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
MOCK_BIN="${TMP}/bin"
mkdir -p "${MOCK_BIN}" "${TMP}/share" "${TMP}/mount"

cat > "${MOCK_BIN}/systemctl" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "${MOCK_BIN}/exportfs" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "${MOCK_BIN}/showmount" <<'EOF'
#!/bin/bash
printf '/srv/share *\n'
EOF
cat > "${MOCK_BIN}/mountpoint" <<'EOF'
#!/bin/bash
exit 1
EOF
cat > "${MOCK_BIN}/mount" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "${MOCK_BIN}/umount" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "${MOCK_BIN}/nerdctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_NERDCTL_LOG}"
exit 0
EOF
export PATH="${MOCK_BIN}:${PATH}"
chmod +x "${MOCK_BIN}"/*
export PROJECT_ROOT="${ROOT}"
export KF_COMPONENT_RESOURCE_DIR="${TMP}/resources"
export KF_NFS_SERVER=10.0.0.10
export KF_NFS_SHARE_PATH=/srv/share
export KF_NFS_WORKER_MOUNT_PATH="${TMP}/mount"
export KF_NFS_STORAGE_CLASS=nfs-storage
export KF_NFS_EXPORTS_FILE="${TMP}/exports"
export KF_NFS_FSTAB_FILE="${TMP}/fstab"
export KF_NERDCTL_LOG="${TMP}/nerdctl.log"
export KF_NODE_IP=10.0.0.10
export KF_NODE_HOSTNAME=nfs-server
export KF_HELM_TIMEOUT=1s

log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "$*" >&2; }
export -f log_info log_success log_warn log_error
source "${ROOT}/scripts/lib/phase3.sh"

export KF_NFS_EXPORTS_MODE=managed
bash "${ROOT}/scripts/steps/phase3_ecosystem/32-configure-nfs-exports.sh"
bash "${ROOT}/scripts/steps/phase3_ecosystem/32-configure-nfs-exports.sh"
test "$(grep -cF '# >>>KubeFoundry NFS exports>>>' "${TMP}/exports")" -eq 1
! grep -En 'ssh_exec|config_get|get_all_' "${ROOT}/scripts/steps/phase3_ecosystem/32-configure-nfs-exports.sh"

bash "${ROOT}/scripts/steps/phase3_ecosystem/32-mount-nfs-workers.sh"
test ! -e "${TMP}/fstab"

export KF_NODE_IP=10.0.0.11
bash "${ROOT}/scripts/steps/phase3_ecosystem/32-mount-nfs-workers.sh"
test "$(grep -cF '# >>>KubeFoundry NFS fstab>>>' "${TMP}/fstab")" -eq 1
! grep -En 'ssh_exec|config_get|get_all_' "${ROOT}/scripts/steps/phase3_ecosystem/32-mount-nfs-workers.sh"

export KF_NFS_EXPORTS_MODE=external
bash "${ROOT}/scripts/steps/phase3_ecosystem/32-configure-nfs-exports.sh"
test "$(grep -cF '# >>>KubeFoundry NFS exports>>>' "${TMP}/exports")" -eq 1

touch "${KF_COMPONENT_RESOURCE_DIR}/32-import-nfs-image"
bash "${ROOT}/scripts/steps/phase3_ecosystem/32-import-nfs-image.sh"
grep -Fxq -- '--namespace k8s.io load --input '"${KF_COMPONENT_RESOURCE_DIR}"'/32-import-nfs-image' \
    "${KF_NERDCTL_LOG}"
grep -Fxq -- '--namespace k8s.io tag harbor.amarsoft.com/k8s-deploy/nfs-subdir-external-provisioner:v4.0.2 registry:5000/nfs/nfs-subdir-external-provisioner:v4.0.2' \
    "${KF_NERDCTL_LOG}"
grep -Fxq -- '--namespace k8s.io push --insecure-registry registry:5000/nfs/nfs-subdir-external-provisioner:v4.0.2' \
    "${KF_NERDCTL_LOG}"
grep -Fq 'kubectl rollout restart deployment/nfs-subdir-external-provisioner' \
    "${ROOT}/scripts/steps/phase3_ecosystem/32-install-nfs.sh"

printf 'phase3 NFS tests passed\n'
