#!/bin/bash

set -o errexit -o nounset -o pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
export TEST_ROOT
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/resources" "${TEST_ROOT}/logs"
export PATH="${TEST_ROOT}/bin:${PATH}"
export KF_COMPONENT_RESOURCE_DIR="${TEST_ROOT}/resources"
export KUBECONFIG="${TEST_ROOT}/admin.conf"
export LOG_FILE="${TEST_ROOT}/logs/phase3.log"

cat > "${TEST_ROOT}/bin/kubectl" <<'EOF'
#!/bin/bash
printf 'kubectl %s\n' "$*" >> "${TEST_ROOT}/calls"
cat >/dev/null || true
EOF
cat > "${TEST_ROOT}/bin/helm" <<'EOF'
#!/bin/bash
printf 'helm %s\n' "$*" >> "${TEST_ROOT}/calls"
EOF
chmod +x "${TEST_ROOT}/bin/kubectl" "${TEST_ROOT}/bin/helm"

source "${PROJECT_ROOT}/scripts/lib/logger.sh"
export COLOR_RESET COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE
export -f _log_timestamp _log_write log_info log_success log_warn log_error log_substep log_separator
source "${PROJECT_ROOT}/scripts/lib/phase3.sh"
phase3_init
phase3_ensure_namespace kubemate-system
phase3_ensure_namespace kubemate-system
phase3_helm_upgrade traefik kubemate-system ./chart.tgz --set image.tag=v1
printf 'value\n' > "${KF_COMPONENT_RESOURCE_DIR}/alloy.config"
phase3_apply_configmap alloy kubemate-system "$(phase3_resource_path alloy.config)"
phase3_wait_rollout deployment traefik kubemate-system
cp "${PROJECT_ROOT}/scripts/lib/phase3.sh" "${TEST_ROOT}/phase3.sh"
(cd "${TEST_ROOT}" && bash "${PROJECT_ROOT}/scripts/steps/phase3_ecosystem/30-create-namespace.sh")

grep -Fq 'helm upgrade --install traefik ./chart.tgz --namespace kubemate-system --create-namespace --wait --timeout 10m --labels app.kubernetes.io/managed-by=kubefoundry --set image.tag=v1' "${TEST_ROOT}/calls" || fail "Helm 参数顺序错误"
[ "$(phase3_resource_path alloy.config)" = "${KF_COMPONENT_RESOURCE_DIR}/alloy.config" ] || fail "资源路径解析错误"
if phase3_resource_path ../outside >/dev/null 2>&1; then fail "资源目录越界未拒绝"; fi
phase3_log_safe 'token=hidden-value' >/dev/null
grep -Fq '[REDACTED]' "${LOG_FILE}" || fail "敏感字段未脱敏"
if grep -Fq 'hidden-value' "${LOG_FILE}"; then fail "敏感值进入日志"; fi
if grep -Eq '(^|[^[:alpha:]])ssh[[:space:]]' "${PROJECT_ROOT}/scripts/lib/phase3.sh"; then fail "公共库不应执行 SSH"; fi
grep -Fq 'kubectl get namespace kubemate-system' "${TEST_ROOT}/calls" || fail "命名空间步骤未执行就绪检查"
if grep -Fq -- '--dry-run' "${TEST_ROOT}/calls"; then fail "phase3 不应执行 dry-run"; fi

printf 'phase3 common tests passed\n'
