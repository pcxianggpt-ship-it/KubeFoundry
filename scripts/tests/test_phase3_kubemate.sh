#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
BIN="${TMP}/bin"
mkdir -p "${BIN}" "${TMP}/resources" "${TMP}/kube"
printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: kubemate-base\n' > "${TMP}/resources/kubemate-crds.yml"
cat > "${TMP}/resources/kubemate-resources.yml" <<'EOF'
kind: Deployment
apiVersion: apps/v1
metadata:
  name: kubemate-appx
  namespace: kubemate-system
spec:
  template:
    spec:
      hostAliases:
        - ip: 192.168.0.1
          hostnames:
            - "k8sc1"
EOF
printf 'apiVersion: v1\n' > "${TMP}/kube/admin.conf"
cat > "${BIN}/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_KUBEMATE_KUBECTL_LOG}"
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

grep -Fxq -- 'create configmap kubemate-etc --namespace kubemate-system --from-file=k8s_config.yml='"${KUBECONFIG}" \
    "${KF_KUBEMATE_KUBECTL_LOG}"
grep -Fxq -- 'apply -f '"${KF_COMPONENT_RESOURCE_DIR}" "${KF_KUBEMATE_KUBECTL_LOG}"
! grep -Eq -- '--dry-run|apply --server-side|field-manager|force-conflicts' "${KF_KUBEMATE_KUBECTL_LOG}"
grep -Eq '^[[:space:]]*- ip: 10\.0\.0\.10[[:space:]]*$' \
    "${KF_COMPONENT_RESOURCE_DIR}/kubemate-resources.yml"
! grep -q -- '192.168.0.1' "${KF_COMPONENT_RESOURCE_DIR}/kubemate-resources.yml"
! grep -Eq 'ssh_exec|config_get|get_all_' "${ROOT}/scripts/steps/phase3_ecosystem/31-install-kubemate-ui.sh"

printf 'phase3 Kubemate tests passed\n'
