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
cat > "${BIN}/curl" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "${BIN}/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_STORAGE_KUBECTL_LOG}"
case "$*" in
  *"get nodes"*) printf 'worker-a Ready worker 1m v1.30.14\nworker-b Ready worker 1m v1.30.14\n' ;;
  *"get service kubemate-minio-hl"*) printf 'service/kubemate-minio-hl\n' ;;
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
        openebs) printf 'chart' > "${KF_COMPONENT_RESOURCE_DIR}/openebs-4.2.0.tgz"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/openebs-values.yaml"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/openebssc.yaml" ;;
        minio) printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: minio-operator\n' > "${KF_COMPONENT_RESOURCE_DIR}/minio-operator.yaml"; printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: minio\nspec:\n  containers:\n  - image: registry:5000/quay.io/minio/minio:old\n  nodeSelector:\n    kubernetes.io/hostname: k8sn1\n  volumes:\n  - hostPath:\n      path: /data2/minio_data\n' > "${KF_COMPONENT_RESOURCE_DIR}/minio-dev.yaml" ;;
        loki) printf 'chart' > "${KF_COMPONENT_RESOURCE_DIR}/loki-5.45.0.tgz"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/values.yaml" ;;
        alloy) printf 'chart' > "${KF_COMPONENT_RESOURCE_DIR}/alloy-1.4.0.tgz"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/alloy.config"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/alloy-values.yaml" ;;
    esac
    bash "${ROOT}/scripts/steps/phase3_ecosystem/${script}"
}

run_group openebs 47-install-openebs.sh
run_group minio 49-install-minio.sh
run_group loki 35-install-loki.sh
run_group alloy 48-install-alloy.sh
grep -q -- '^install openebs --namespace kubemate-system .*openebs-4.2.0.tgz -f .*openebs-values.yaml$' "${KF_STORAGE_HELM_LOG}"
grep -q -- 'loki-5.45.0.tgz.*-f .*values.yaml' "${KF_STORAGE_HELM_LOG}"
grep -q -- '--set read.replicas=2 --set write.replicas=2 --set backend.replicas=2 --set loki.commonConfig.replication_factor=2 --set loki.storage.s3.endpoint=kubemate-minio-hl:9000' "${KF_STORAGE_HELM_LOG}"
grep -q -- 'alloy-1.4.0.tgz.*-f .*alloy-values.yaml' "${KF_STORAGE_HELM_LOG}"
grep -q -- 'wait --for=condition=Ready pod/minio --namespace kubemate-system --timeout 10m' "${KF_STORAGE_KUBECTL_LOG}"
! grep -Eq 'ssh_exec|config_get|get_all_' "${ROOT}/scripts/steps/phase3_ecosystem/47-install-openebs.sh" "${ROOT}/scripts/steps/phase3_ecosystem/49-install-minio.sh" "${ROOT}/scripts/steps/phase3_ecosystem/35-install-loki.sh" "${ROOT}/scripts/steps/phase3_ecosystem/48-install-alloy.sh"
! grep -Eq -- '--dry-run' "${ROOT}/scripts/steps/phase3_ecosystem/47-install-openebs.sh" "${ROOT}/scripts/steps/phase3_ecosystem/35-install-loki.sh" "${ROOT}/scripts/steps/phase3_ecosystem/48-install-alloy.sh"
printf 'phase3 storage observability tests passed\n'
