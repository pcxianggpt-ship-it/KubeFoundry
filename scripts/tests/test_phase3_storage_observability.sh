#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
BIN="${TMP}/bin"
mkdir -p "${BIN}"
cat > "${BIN}/helm" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_STORAGE_HELM_LOG}"
exit 0
EOF
cat > "${BIN}/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_STORAGE_KUBECTL_LOG}"
case "$*" in
  *"get deployment"*) printf '%s\n' "${KF_STORAGE_MOCK_GROUP}-controller" ;;
  *"get pods"*) printf '%s\n' "${KF_STORAGE_MOCK_GROUP}-pod 1/1 Running" ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "${BIN}"/*
export PATH="${BIN}:${PATH}"
export PROJECT_ROOT="${ROOT}"
export KF_STORAGE_HELM_LOG="${TMP}/helm.log"
export KF_STORAGE_KUBECTL_LOG="${TMP}/kubectl.log"
export KF_COMPONENT_RESOURCE_DIR="${TMP}/resources"
export KF_ROLLOUT_TIMEOUT=1s
export KF_NODE_HOSTNAME=cp-a
export KF_NODE_IP=10.0.0.1
export KF_NODE_ROLE=control_plane
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "$*" >&2; }
export -f log_info log_success log_warn log_error

run_group() {
    local group="$1" script="$2"
    rm -rf "${KF_COMPONENT_RESOURCE_DIR}"
    mkdir -p "${KF_COMPONENT_RESOURCE_DIR}"
    export KF_STORAGE_MOCK_GROUP="${group}"
    case "${group}" in
        openebs) printf 'apiVersion: v2\nname: openebs\n' > "${KF_COMPONENT_RESOURCE_DIR}/Chart.yaml"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/openebs-values.yaml"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/openebssc.yaml" ;;
        minio) printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/minio-operator.yaml" ;;
        loki) printf 'apiVersion: v2\nname: loki\n' > "${KF_COMPONENT_RESOURCE_DIR}/Chart.yaml"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/values.yaml" ;;
        alloy) printf 'apiVersion: v2\nname: alloy\n' > "${KF_COMPONENT_RESOURCE_DIR}/Chart.yaml"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/alloy.config"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/alloy-values.yaml" ;;
    esac
    bash "${ROOT}/scripts/steps/phase3_ecosystem/${script}"
}

run_group openebs 47-install-openebs.sh
run_group minio 49-install-minio.sh
run_group loki 35-install-loki.sh
run_group alloy 48-install-alloy.sh
! grep -Eq 'ssh_exec|config_get|get_all_' "${ROOT}/scripts/steps/phase3_ecosystem/47-install-openebs.sh" "${ROOT}/scripts/steps/phase3_ecosystem/49-install-minio.sh" "${ROOT}/scripts/steps/phase3_ecosystem/35-install-loki.sh" "${ROOT}/scripts/steps/phase3_ecosystem/48-install-alloy.sh"
printf 'phase3 storage observability tests passed\n'
