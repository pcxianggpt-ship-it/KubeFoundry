#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
BIN="${TMP}/bin"
mkdir -p "${BIN}" "${TMP}/resources" "${TMP}/kube"
printf 'apiVersion: apiextensions.k8s.io/v1\nkind: CustomResourceDefinition\nmetadata:\n  name: users.example.io\n' > "${TMP}/resources/kubemate-crds.yml"
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
case "$*" in
  *"get -f "*"kubemate-crds.yml -o name"*) printf 'customresourcedefinition.apiextensions.k8s.io/users.example.io\n' ;;
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
grep -Fxq -- 'apply -f '"${KF_COMPONENT_RESOURCE_DIR}"'/kubemate-crds.yml' "${KF_KUBEMATE_KUBECTL_LOG}"
grep -Fxq -- 'wait --for=condition=Established customresourcedefinition.apiextensions.k8s.io/users.example.io --timeout 180s' \
    "${KF_KUBEMATE_KUBECTL_LOG}"
grep -Fxq -- 'apply -f '"${KF_COMPONENT_RESOURCE_DIR}"'/kubemate-resources.yml' "${KF_KUBEMATE_KUBECTL_LOG}"
crd_apply_line=$(grep -nF -- 'apply -f '"${KF_COMPONENT_RESOURCE_DIR}"'/kubemate-crds.yml' "${KF_KUBEMATE_KUBECTL_LOG}" | cut -d: -f1)
resource_apply_line=$(grep -nF -- 'apply -f '"${KF_COMPONENT_RESOURCE_DIR}"'/kubemate-resources.yml' "${KF_KUBEMATE_KUBECTL_LOG}" | cut -d: -f1)
[ "${crd_apply_line}" -lt "${resource_apply_line}" ]
! grep -Eq -- '--dry-run|apply --server-side|field-manager|force-conflicts' "${KF_KUBEMATE_KUBECTL_LOG}"
grep -Eq '^[[:space:]]*- ip: 10\.0\.0\.10[[:space:]]*$' \
    "${KF_COMPONENT_RESOURCE_DIR}/kubemate-resources.yml"
! grep -q -- '192.168.0.1' "${KF_COMPONENT_RESOURCE_DIR}/kubemate-resources.yml"
! grep -Eq 'ssh_exec|config_get|get_all_' "${ROOT}/scripts/steps/phase3_ecosystem/31-install-kubemate-ui.sh"

printf 'phase3 Kubemate tests passed\n'
