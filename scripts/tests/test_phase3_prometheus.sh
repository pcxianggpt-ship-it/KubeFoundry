#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
BIN="${TMP}/bin"
mkdir -p "${BIN}" "${TMP}/resources"
cat > "${BIN}/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_PROM_KUBECTL_LOG}"
for argument in "$@"; do
  if [ -f "${argument}" ] && [ "$(basename "${argument}")" = 'additional-scrape-configs.Secret.yaml' ] \
      && grep -Eq 'managedFields|resourceVersion|uid:|creationTimestamp' "${argument}"; then
    exit 1
  fi
  if [ -f "${argument}" ] && grep -q '/data/prom_data' "${argument}"; then
    : > "${KF_PROM_RENDERED_OK}"
  fi
done
case "$*" in
  *"get deployment"*) printf 'prometheus-operator 1 1 1 1m\n' ;;
  *"get pods"*) printf 'prometheus-prometheus 3/3 Running\nnode-exporter 1/1 Running\nkube-state-metrics 1/1 Running\n' ;;
  *"top nodes"*) printf 'cp-a 10m 100Mi\n' ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "${BIN}/kubectl"
export PATH="${BIN}:${PATH}"
export PROJECT_ROOT="${ROOT}"
export KF_COMPONENT_RESOURCE_DIR="${TMP}/resources"
export KF_PROM_KUBECTL_LOG="${TMP}/kubectl.log"
export KF_PROM_RENDERED_OK="${TMP}/rendered-ok"
export KF_CRD_TIMEOUT=1s
export KF_ROLLOUT_TIMEOUT=1s
export KF_NODE_HOSTNAME=cp-a
export KF_NODE_IP=10.0.0.1
export KF_NODE_ROLE=control_plane
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "$*" >&2; }
export -f log_info log_success log_warn log_error

printf 'apiVersion: v1\nkind: PersistentVolume\nspec:\n  hostPath:\n    path: /data/prom_data\n' > "${KF_COMPONENT_RESOURCE_DIR}/prometheus.yaml"
printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: metrics-server\n' > "${KF_COMPONENT_RESOURCE_DIR}/metrics-server.yaml"
cat > "${KF_COMPONENT_RESOURCE_DIR}/additional-scrape-configs.Secret.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  creationTimestamp: '2025-05-07T02:00:50Z'
  managedFields:
  - apiVersion: v1
    manager: kubectl-create
  name: additional-scrape-configs
  namespace: kubemate-system
  resourceVersion: '197458704'
  uid: b0718516-6033-4234-906d-acf2f619fe1a
type: Opaque
data: {}
EOF
bash "${ROOT}/scripts/steps/phase3_ecosystem/38-install-prometheus.sh"
grep -q -- 'apply --server-side' "${KF_PROM_KUBECTL_LOG}"
test -f "${KF_PROM_RENDERED_OK}"
grep -q -- 'additional-scrape-configs.Secret.yaml' "${KF_PROM_KUBECTL_LOG}"
grep -q -- 'metrics-server.yaml' "${KF_PROM_KUBECTL_LOG}"

! grep -Eq 'ssh_exec|config_get|get_all_|k8sw1|k8sw2' "${ROOT}/scripts/steps/phase3_ecosystem/38-install-prometheus.sh"

printf 'phase3 Prometheus tests passed\n'
