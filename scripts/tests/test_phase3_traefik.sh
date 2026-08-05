#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
BIN="${TMP}/bin"
mkdir -p "${BIN}" "${TMP}/resources"
printf 'apiVersion: v1\nkind: Service\nmetadata:\n  name: traefik\nspec:\n  ports:\n  - port: 80\n    nodePort: 30080\n' > "${TMP}/resources/traefik.yaml"
cat > "${BIN}/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_TRAEFIK_KUBECTL_LOG}"
case "$*" in
  *"get service --all-namespaces --no-headers"*) printf 'kube-system traefik ClusterIP 10.0.0.1 80:30080/TCP 1m\n' ;;
  *"get deployment --all-namespaces --no-headers"*) printf 'kube-system traefik 1 1 1 1m\n' ;;
  *"get service --all-namespaces"*) printf 'kube-system traefik ClusterIP 10.0.0.1 80:30080/TCP 1m\n' ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "${BIN}/kubectl"
export PATH="${BIN}:${PATH}"
export PROJECT_ROOT="${ROOT}"
export KF_COMPONENT_RESOURCE_DIR="${TMP}/resources"
export KF_TRAEFIK_KUBECTL_LOG="${TMP}/kubectl.log"
export KF_ROLLOUT_TIMEOUT=1s
export KF_NODE_HOSTNAME=cp-a
export KF_NODE_IP=10.0.0.1
export KF_NODE_ROLE=control_plane
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "$*" >&2; }
export -f log_info log_success log_warn log_error

bash "${ROOT}/scripts/steps/phase3_ecosystem/36-install-traefik.sh" || {
    status=$?
    cat "${KF_TRAEFIK_KUBECTL_LOG}" >&2 || true
    exit "${status}"
}
grep -q -- 'apply --server-side' "${KF_TRAEFIK_KUBECTL_LOG}"
grep -q -- 'rollout status deployment/traefik' "${KF_TRAEFIK_KUBECTL_LOG}"
! grep -Eq 'ssh_exec|config_get|get_all_|sleep 10' "${ROOT}/scripts/steps/phase3_ecosystem/36-install-traefik.sh"

printf 'phase3 Traefik tests passed\n'
