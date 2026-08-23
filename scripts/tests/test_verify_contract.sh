#!/bin/bash

set -o errexit -o nounset -o pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

base_steps=(
    10-setup-yum-source 11b-setup-hostname 12-setup-k8s-repo 13-install-k8s-deps
    14-replace-kubeadm 15-environment-config 16-install-containerd 17-install-registry
    18-init-k8s-cluster 19-modify-cert-expiry 20-add-control-nodes 21-add-worker-nodes
    22-install-cni-flannel 23-configure-coredns-affinity
)
component_steps=(
    29-install-helm 30-create-namespace 32-configure-nfs-exports 32-install-nfs
    32-mount-nfs-workers 31-install-kubemate-ui 36-install-traefik
    46-prepare-storage-workers 47-install-openebs 49-install-minio 35-install-loki
    48-install-alloy 37-prepare-prometheus-workers 38-install-prometheus
)

verify_script() {
    local script="$1"
    [ -f "${script}" ] || fail "缺少验证脚本: ${script}"
    [ ! -L "${script}" ] || fail "验证脚本不能是符号链接: ${script}"
    bash -n "${script}" || fail "验证脚本语法错误: ${script}"
    if LC_ALL=C grep -q $'\r' "${script}"; then fail "验证脚本不是 LF: ${script}"; fi
    if grep -Eq 'verify-lib\.sh|verify_step|scripts/lib/verify\.sh' "${script}"; then
        fail "验证脚本仍依赖公共验证库: ${script}"
    fi
    if grep -Eq 'PROJECT_ROOT|config\.sh|ssh_exec|(^|[^[:alnum:]_])ssh[[:space:]]' "${script}"; then
        fail "验证脚本含控制端依赖或嵌套 SSH: ${script}"
    fi
    if grep -Eq '(^|[;&|[:space:]])(read|select)[[:space:]]' "${script}"; then
        fail "验证脚本包含交互命令: ${script}"
    fi
    if grep -Eq '(^|[;&|[:space:]])(mkdir|rm|mv|cp|install|mount|umount|sed[[:space:]]+-i|kubectl[[:space:]]+(apply|create|delete|label|patch|annotate))[[:space:]]' "${script}"; then
        fail "验证脚本包含修改目标状态的命令: ${script}"
    fi
    if grep -E 'exit[[:space:]]+[0-9]+' "${script}" | grep -Ev 'exit[[:space:]]+(0|10|20|21)([;[:space:]]|$)' >/dev/null; then
        fail "验证脚本包含非法退出码: ${script}"
    fi
}

[ ! -e "${PROJECT_ROOT}/scripts/lib/verify.sh" ] || fail "验证公共库尚未删除"
for key in "${base_steps[@]}"; do
    verify_script "${PROJECT_ROOT}/scripts/verify/phase2_k8s_base/verify-${key}.sh"
done
for key in "${component_steps[@]}"; do
    verify_script "${PROJECT_ROOT}/scripts/verify/phase3_ecosystem/verify-${key}.sh"
done

grep -Fq 'deployment/kubemate-appx' "${PROJECT_ROOT}/scripts/verify/phase3_ecosystem/verify-31-install-kubemate-ui.sh" || fail "Kubemate 验证未只等待自身 Deployment"
grep -Fq 'get daemonset -A' "${PROJECT_ROOT}/scripts/verify/phase3_ecosystem/verify-36-install-traefik.sh" || fail "Traefik 验证未查询 DaemonSet"
grep -Fq 'rollout status "daemonset/${name}"' "${PROJECT_ROOT}/scripts/verify/phase3_ecosystem/verify-36-install-traefik.sh" || fail "Traefik 验证未等待 DaemonSet rollout"

set +e
env -u KF_NODE_HOSTNAME -u KF_NODE_IP bash "${PROJECT_ROOT}/scripts/verify/phase2_k8s_base/verify-11b-setup-hostname.sh" >/dev/null 2>&1
[ "$?" -eq 20 ] || fail "缺少运行参数应返回 20"
KF_YUM_LOCAL_REPO_CONFIG="${TEST_ROOT}/missing.repo" bash "${PROJECT_ROOT}/scripts/verify/phase2_k8s_base/verify-10-setup-yum-source.sh" >/dev/null 2>&1
[ "$?" -eq 10 ] || fail "状态未满足应返回 10"
mkdir -p "${TEST_ROOT}/data/prom_data" "${TEST_ROOT}/bin"
KF_K8S_HOME="${TEST_ROOT}/data" bash "${PROJECT_ROOT}/scripts/verify/phase3_ecosystem/verify-37-prepare-prometheus-workers.sh" >/dev/null 2>&1
[ "$?" -eq 0 ] || fail "状态满足应返回 0"
printf '#!/bin/bash\nexit 124\n' > "${TEST_ROOT}/bin/timeout"
chmod +x "${TEST_ROOT}/bin/timeout"
PATH="${TEST_ROOT}/bin:${PATH}" KF_K8S_HOME="${TEST_ROOT}/data" bash "${PROJECT_ROOT}/scripts/verify/phase3_ecosystem/verify-37-prepare-prometheus-workers.sh" >/dev/null 2>&1
[ "$?" -eq 21 ] || fail "验证超时应返回 21"
set -e

recovery="${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/18-recover-k8s-keys.sh"
[ -f "${recovery}" ] && [ ! -L "${recovery}" ] || fail "Join 产物恢复脚本不可用"
bash -n "${recovery}" || fail "Join 产物恢复脚本语法错误"
if grep -Eq 'log_(info|success|warn|error).*(worker_join|certificate_key|token)' "${recovery}"; then
    fail "Join 产物恢复脚本可能输出敏感值"
fi

printf 'verify contract tests passed\n'
