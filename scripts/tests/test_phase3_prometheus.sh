#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
BIN="${TMP}/bin"
RESOURCE_DIR="${TMP}/resources"
mkdir -p "${BIN}" "${RESOURCE_DIR}"

cat > "${BIN}/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_PROM_KUBECTL_LOG}"
if [ "${1:-}" = 'apply' ] && [ "${2:-}" = '-f' ] && [ -f "${3:-}" ] \
    && grep -q '/data/k8s_install/prom_data' "${3}"; then
  : > "${KF_PROM_RENDERED_OK}"
fi
case "$*" in
  "get nodes -l "*) printf 'node/k8sw1\nnode/k8sw2\n' ;;
  *"get prometheus k8s -n kubemate-system -o jsonpath="*) printf '2:2' ;;
esac
EOF
chmod +x "${BIN}/kubectl"

export PATH="${BIN}:${PATH}"
export PROJECT_ROOT="${ROOT}"
export KF_COMPONENT_RESOURCE_DIR="${RESOURCE_DIR}"
export KF_PROM_KUBECTL_LOG="${TMP}/kubectl.log"
export KF_PROM_RENDERED_OK="${TMP}/rendered-ok"
export KF_K8S_HOME="/data/k8s_install"
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "$*" >&2; }
export -f log_info log_success log_warn log_error

printf 'path: /data/prom_data\n' > "${RESOURCE_DIR}/promlocal-pv.yaml"
mkdir -p \
    "${RESOURCE_DIR}/1-crd" \
    "${RESOURCE_DIR}/2-prometheusOperator" \
    "${RESOURCE_DIR}/3-prometheus" \
    "${RESOURCE_DIR}/4-nodeExporter" \
    "${RESOURCE_DIR}/5-kubeStateMetrics" \
    "${RESOURCE_DIR}/6-alertmanager" \
    "${RESOURCE_DIR}/7-kubernetesControlPlaneRule"
printf 'apiVersion: apps/v1\nkind: Deployment\n' > "${RESOURCE_DIR}/8-metrics-server-ha.yaml"

bash "${ROOT}/scripts/steps/phase3_ecosystem/38-install-prometheus.sh"

grep -Fxq -- 'label node/k8sw1 node/k8sw2 prom=true --overwrite=true' "${KF_PROM_KUBECTL_LOG}"
grep -Eq '^apply -f /tmp/' "${KF_PROM_KUBECTL_LOG}"
grep -Fxq -- "create -f ${RESOURCE_DIR}/1-crd" "${KF_PROM_KUBECTL_LOG}"

expected=(
    "${RESOURCE_DIR}/2-prometheusOperator"
    "${RESOURCE_DIR}/3-prometheus"
    "${RESOURCE_DIR}/4-nodeExporter"
    "${RESOURCE_DIR}/5-kubeStateMetrics"
    "${RESOURCE_DIR}/6-alertmanager"
    "${RESOURCE_DIR}/7-kubernetesControlPlaneRule"
    "${RESOURCE_DIR}/8-metrics-server-ha.yaml"
)
previous_line=$(grep -nF -- "create -f ${RESOURCE_DIR}/1-crd" "${KF_PROM_KUBECTL_LOG}" | cut -d: -f1)
for resource in "${expected[@]}"; do
    current_line=$(grep -nF -- "apply -f ${resource}" "${KF_PROM_KUBECTL_LOG}" | cut -d: -f1)
    [ "${current_line}" -gt "${previous_line}" ]
    previous_line="${current_line}"
done

test -f "${KF_PROM_RENDERED_OK}"
! grep -Eq 'phase3_apply_managed|rollout|additional-scrape|server-side|dry-run' \
    "${ROOT}/scripts/steps/phase3_ecosystem/38-install-prometheus.sh"

export KF_KUBECONFIG="${TMP}/admin.conf"
export KF_VERIFY_COMMAND_TIMEOUT=30s
export KF_VERIFY_ROLLOUT_TIMEOUT=180s
: > "${KF_KUBECONFIG}"
bash "${ROOT}/scripts/verify/phase3_ecosystem/verify-38-install-prometheus.sh"

grep -Fq -- 'rollout status deployment/prometheus-operator --namespace kubemate-system --timeout=180s' "${KF_PROM_KUBECTL_LOG}"
grep -Fq -- 'rollout status statefulset/prometheus-k8s --namespace kubemate-system --timeout=180s' "${KF_PROM_KUBECTL_LOG}"
grep -Fq -- 'rollout status daemonset/node-exporter --namespace kubemate-system --timeout=180s' "${KF_PROM_KUBECTL_LOG}"
grep -Fq -- 'rollout status deployment/metrics-server --namespace kube-system --timeout=180s' "${KF_PROM_KUBECTL_LOG}"

printf 'phase3 Prometheus tests passed\n'
