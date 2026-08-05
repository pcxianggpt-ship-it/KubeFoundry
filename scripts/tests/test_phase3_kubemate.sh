#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
BIN="${TMP}/bin"
mkdir -p "${BIN}" "${TMP}/resources" "${TMP}/kube"
printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: kubemate-ui\n  annotations:\n    control-ip: __KF_PRIMARY_CONTROL_IP__\n' > "${TMP}/resources/31-install-kubemate-ui"
printf 'apiVersion: v1\n' > "${TMP}/kube/admin.conf"
cat > "${BIN}/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_KUBEMATE_KUBECTL_LOG}"
case "$*" in
  *"apply --server-side"*) cp "${!#}" "${KF_KUBEMATE_RENDERED}" ;;
  *"get service --all-namespaces"*) printf 'kubemate-system kubemate-ui 30088\n' ;;
  *"get deployment --namespace"*) printf 'deployment/kubemate-ui\n' ;;
  *"get service --namespace"*) printf 'service/kubemate-ui\n' ;;
  *"get service"*) printf 'apiVersion: v1\n' ;;
  *"create namespace"*) printf 'apiVersion: v1\n' ;;
  *) : ;;
esac
exit 0
EOF
cat > "${BIN}/helm" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "${BIN}"/*
export PATH="${BIN}:${PATH}"
export PROJECT_ROOT="${ROOT}"
export KF_COMPONENT_RESOURCE_DIR="${TMP}/resources"
export KF_PRIMARY_CONTROL_IP=10.0.0.10
export KUBECONFIG="${TMP}/kube/admin.conf"
export KF_KUBEMATE_KUBECTL_LOG="${TMP}/kubectl.log"
export KF_KUBEMATE_RENDERED="${TMP}/rendered.yaml"
export KF_ROLLOUT_TIMEOUT=1s
export KF_NODE_HOSTNAME=cp-a
export KF_NODE_IP=10.0.0.10
export KF_NODE_ROLE=control_plane
export KF_NFS_SERVER=10.0.0.10
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "$*" >&2; }
export -f log_info log_success log_warn log_error

bash "${ROOT}/scripts/steps/phase3_ecosystem/31-install-kubemate-ui.sh"
grep -q -- '--from-file=k8s_config.yml=' "${KF_KUBEMATE_KUBECTL_LOG}"
grep -q -- 'apply --server-side' "${KF_KUBEMATE_KUBECTL_LOG}"
grep -q -- '10.0.0.10' "${KF_KUBEMATE_RENDERED}"
grep -q -- '__KF_PRIMARY_CONTROL_IP__' "${TMP}/resources/31-install-kubemate-ui"
! grep -Eq 'ssh_exec|config_get|get_all_' "${ROOT}/scripts/steps/phase3_ecosystem/31-install-kubemate-ui.sh"

printf 'phase3 Kubemate tests passed\n'
