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
if [ "${KF_TEST_MISSING_ROLE:-}" = 1 ] && [[ "$*" == *"get kmrole deployment -n kubemate-system"* ]]; then
    exit 1
fi
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
export KF_COMPONENT_GROUP_KEY=kubemate
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

grep -Fxq -- 'create configmap kubemate-etc --namespace kubemate-system --from-file=k8s_config.yml='"${KUBECONFIG}"' --dry-run=client -o yaml' \
    "${KF_KUBEMATE_KUBECTL_LOG}"
grep -Fxq -- 'apply --server-side --field-manager=kubefoundry --force-conflicts -f '"${KF_COMPONENT_RESOURCE_DIR}"'/kubemate-crds.yml' \
    "${KF_KUBEMATE_KUBECTL_LOG}"
grep -Fxq -- 'wait --for=condition=Established customresourcedefinition.apiextensions.k8s.io/users.example.io --timeout 180s' \
    "${KF_KUBEMATE_KUBECTL_LOG}"
grep -Fxq -- 'apply --server-side --field-manager=kubefoundry --force-conflicts -f '"${KF_COMPONENT_RESOURCE_DIR}"'/kubemate-resources.yml' \
    "${KF_KUBEMATE_KUBECTL_LOG}"
grep -Fxq -- 'label --overwrite -f '"${KF_COMPONENT_RESOURCE_DIR}"'/kubemate-resources.yml app.kubernetes.io/managed-by=kubefoundry kubefoundry.io/component-group=kubemate' \
    "${KF_KUBEMATE_KUBECTL_LOG}"
crd_apply_line=$(grep -nF -- 'apply --server-side --field-manager=kubefoundry --force-conflicts -f '"${KF_COMPONENT_RESOURCE_DIR}"'/kubemate-crds.yml' "${KF_KUBEMATE_KUBECTL_LOG}" | cut -d: -f1)
resource_apply_line=$(grep -nF -- 'apply --server-side --field-manager=kubefoundry --force-conflicts -f '"${KF_COMPONENT_RESOURCE_DIR}"'/kubemate-resources.yml' "${KF_KUBEMATE_KUBECTL_LOG}" | cut -d: -f1)
[ "${crd_apply_line}" -lt "${resource_apply_line}" ]
grep -Eq '^[[:space:]]*- ip: 10\.0\.0\.10[[:space:]]*$' \
    "${KF_COMPONENT_RESOURCE_DIR}/kubemate-resources.yml"
! grep -q -- '192.168.0.1' "${KF_COMPONENT_RESOURCE_DIR}/kubemate-resources.yml"
! grep -Eq 'ssh_exec|config_get|get_all_' "${ROOT}/scripts/steps/phase3_ecosystem/31-install-kubemate-ui.sh"

export KF_KUBECONFIG="${KUBECONFIG}"
KF_TEST_MISSING_ROLE=1 bash "${ROOT}/scripts/verify/phase3_ecosystem/verify-31-install-kubemate-ui.sh" \
    > "${TMP}/verify-missing.log" 2>&1 && exit 1
grep -q 'Kubemate deployment 角色不存在' "${TMP}/verify-missing.log"
bash "${ROOT}/scripts/verify/phase3_ecosystem/verify-31-install-kubemate-ui.sh" \
    > "${TMP}/verify-success.log"

printf 'phase3 Kubemate tests passed\n'
