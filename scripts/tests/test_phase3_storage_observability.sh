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
if [ "${1:-}" = "status" ]; then
    [ "${KF_OPENEBS_RELEASE_EXISTS:-false}" = "true" ]
    exit $?
fi
if [ "${1:-}" = "install" ] && [ "${2:-}" = "openebs" ]; then
    path_values="${!#}"
    grep -q "basePath: \"${KF_K8S_HOME}/openebs-root\"" "${path_values}"
fi
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
  *"get nodes"*) printf 'worker-a Ready worker 1m v1.30.14\nworker-b Ready worker 1m v1.30.14\nworker-c Ready worker 1m v1.30.14\nworker-d Ready worker 1m v1.30.14\n' ;;
  *"get service kubemate-minio-hl"*) printf 'service/kubemate-minio-hl\n' ;;
  *"get secret kubemate-minio-env"*) printf 'export MINIO_ROOT_USER="test-user"\nexport MINIO_ROOT_PASSWORD="test-password"\n' ;;
  *"get pvc --selector v1.min.io/tenant=kubemate-minio"*) printf 'data-0 Bound pv-0 1Gi RWO openebs-hostpath\ndata-1 Bound pv-1 1Gi RWO openebs-hostpath\ndata-2 Bound pv-2 1Gi RWO openebs-hostpath\ndata-3 Bound pv-3 1Gi RWO openebs-hostpath\n' ;;
  *"get pods --selector v1.min.io/tenant=kubemate-minio"*) printf 'minio-0 1/1 Running\nminio-1 1/1 Running\nminio-2 1/1 Running\nminio-3 1/1 Running\n' ;;
  *"get deployment"*) printf '%s\n' "${KF_STORAGE_MOCK_GROUP}-controller" ;;
  *"get pods"*) printf '%s\n' "${KF_STORAGE_MOCK_GROUP}-pod 1/1 Running" ;;
  *) : ;;
esac
for argument in "$@"; do
  if [ -f "${argument}" ] && grep -q 'name: BasePath' "${argument}"; then
    grep -q "value: ${KF_K8S_HOME}/openebs-root" "${argument}"
    ! grep -q '__KUBERNETES_WORK_DIR__' "${argument}"
  fi
done
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
export KF_K8S_HOME="${TMP}/k8s-work"
unset KF_OPENEBS_RELEASE_EXISTS || true
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
        openebs)
            printf 'chart' > "${KF_COMPONENT_RESOURCE_DIR}/openebs-4.2.0.tgz"
            printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/openebs-values.yaml"
            printf 'apiVersion: storage.k8s.io/v1\nkind: StorageClass\nmetadata:\n  name: local-hostpath\nparameters:\n  name: BasePath\n  value: __KUBERNETES_WORK_DIR__/openebs-root\n' > "${KF_COMPONENT_RESOURCE_DIR}/openebssc.yaml"
            ;;
        minio)
            printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: minio-operator\n' > "${KF_COMPONENT_RESOURCE_DIR}/minio-operator.yaml"
            printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n- tenant.yaml\n' > "${KF_COMPONENT_RESOURCE_DIR}/kustomization.yaml"
            printf 'apiVersion: minio.min.io/v2\nkind: Tenant\nmetadata:\n  name: kubemate-minio\n' > "${KF_COMPONENT_RESOURCE_DIR}/tenant.yaml"
            printf 'export MINIO_ROOT_USER="test-user"\nexport MINIO_ROOT_PASSWORD="test-password"\n' > "${KF_COMPONENT_RESOURCE_DIR}/tenant.env"
            ;;
        loki) printf 'chart' > "${KF_COMPONENT_RESOURCE_DIR}/loki-5.45.0.tgz"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/values.yaml" ;;
        alloy) printf 'chart' > "${KF_COMPONENT_RESOURCE_DIR}/alloy-1.4.0.tgz"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/alloy.config"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/alloy-values.yaml" ;;
    esac
    bash "${ROOT}/scripts/steps/phase3_ecosystem/${script}"
}

bash "${ROOT}/scripts/steps/phase3_ecosystem/46-prepare-storage-workers.sh"
for directory in openebs-root minio-root loki-root; do
    [ -d "${KF_K8S_HOME}/${directory}" ]
done
if KF_K8S_HOME="${TMP}/../unsafe" \
        bash "${ROOT}/scripts/steps/phase3_ecosystem/46-prepare-storage-workers.sh" >/dev/null 2>&1; then
    printf '不安全的 Kubernetes 工作目录未被拒绝\n' >&2
    exit 1
fi
run_group openebs 47-install-openebs.sh
export KF_OPENEBS_RELEASE_EXISTS=true
run_group openebs 47-install-openebs.sh
run_group minio 49-install-minio.sh
run_group loki 35-install-loki.sh
run_group alloy 48-install-alloy.sh
grep -q -- '^install openebs --namespace kubemate-system .*openebs-4.2.0.tgz -f .*openebs-values.yaml -f /tmp/' "${KF_STORAGE_HELM_LOG}" || {
    printf 'OpenEBS Helm 调用不符合预期:\n' >&2
    cat "${KF_STORAGE_HELM_LOG}" >&2
    exit 1
}
[ "$(grep -c -- '^install openebs --namespace kubemate-system ' "${KF_STORAGE_HELM_LOG}")" -eq 1 ]
grep -q -- 'loki-5.45.0.tgz.*-f .*values.yaml -f /tmp/' "${KF_STORAGE_HELM_LOG}"
grep -q -- '--set read.replicas=3 --set write.replicas=3 --set backend.replicas=3 --set loki.commonConfig.replication_factor=3 --set sidecar.image.repository=registry:5000/ghcr.io/kiwigrid/k8s-sidecar --set loki.storage.s3.endpoint=kubemate-minio-hl:9000' "${KF_STORAGE_HELM_LOG}"
grep -q -- 'alloy-1.4.0.tgz.*-f .*alloy-values.yaml' "${KF_STORAGE_HELM_LOG}"
grep -q -- 'apply --server-side --field-manager=kubefoundry --force-conflicts -f /tmp/' "${KF_STORAGE_KUBECTL_LOG}"
grep -q -- 'apply -k .*resources' "${KF_STORAGE_KUBECTL_LOG}"
grep -q -- 'label nodes worker-a worker-b worker-c worker-d kubefoundry.io/minio=true --overwrite' "${KF_STORAGE_KUBECTL_LOG}"
grep -q -- "wait --for=jsonpath={.status.currentState}=Initialized tenant/kubemate-minio --namespace kubemate-system --timeout 10m" "${KF_STORAGE_KUBECTL_LOG}"
! grep -Eq 'ssh_exec|config_get|get_all_' "${ROOT}/scripts/steps/phase3_ecosystem/47-install-openebs.sh" "${ROOT}/scripts/steps/phase3_ecosystem/49-install-minio.sh" "${ROOT}/scripts/steps/phase3_ecosystem/35-install-loki.sh" "${ROOT}/scripts/steps/phase3_ecosystem/48-install-alloy.sh"
! grep -Eq -- '--dry-run' "${ROOT}/scripts/steps/phase3_ecosystem/47-install-openebs.sh" "${ROOT}/scripts/steps/phase3_ecosystem/35-install-loki.sh" "${ROOT}/scripts/steps/phase3_ecosystem/48-install-alloy.sh"
grep -q 'application/vnd.oci.image.index.v1+json' "${ROOT}/scripts/lib/phase3.sh"
grep -q 'value: __KUBERNETES_WORK_DIR__/openebs-root' "${ROOT}/kube-media/03.setup_file/v1.30.14/helmapp/openebs/openebssc.yaml"
for file in minio-operator.yaml kustomization.yaml tenant.yaml; do
    [ -s "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/${file}" ]
done
grep -Fqx 'kube-media/**/minio/tenant.env' "${ROOT}/.gitignore"
grep -q 'storage: 10Gi' "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
grep -q 'cpu: 250m' "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
grep -q 'memory: 512Mi' "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
grep -q 'cpu: "2"' "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
grep -q 'memory: 4Gi' "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
! grep -Eq '(^|[/:])minio/kes([:@]|$)|^[[:space:]]+kes:' \
    "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
printf 'phase3 storage observability tests passed\n'
