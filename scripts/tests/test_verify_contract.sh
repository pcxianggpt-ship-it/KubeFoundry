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

verify_wrapper() {
    local directory="$1" key="$2" script
    script="${directory}/verify-${key}.sh"
    [ -f "${script}" ] || fail "缺少验证脚本: ${key}"
    [ ! -L "${script}" ] || fail "验证脚本不能是符号链接: ${key}"
    bash -n "${script}" || fail "验证脚本语法错误: ${key}"
    grep -Fq "verify_step \"${key}\"" "${script}" || fail "验证脚本键不匹配: ${key}"
    grep -Eq "(^|[|[:space:]])${key}([|)])" "${library}" 2>/dev/null \
        || fail "验证公共库缺少步骤实现: ${key}"
    if grep -Eq 'PROJECT_ROOT|config\.sh|ssh_exec|(^|[^[:alnum:]_])ssh[[:space:]]' "${script}"; then
        fail "验证脚本含控制端依赖或嵌套 SSH: ${key}"
    fi
    if LC_ALL=C grep -q $'\r' "${script}"; then fail "验证脚本不是 LF: ${key}"; fi
    if grep -Eq '(^|[;&|[:space:]])(read|select)[[:space:]]' "${script}"; then
        fail "验证脚本包含交互命令: ${key}"
    fi
}

library="${PROJECT_ROOT}/scripts/lib/verify.sh"
[ -f "${library}" ] && [ ! -L "${library}" ] || fail "验证公共库不可用"

for key in "${base_steps[@]}"; do
    verify_wrapper "${PROJECT_ROOT}/scripts/verify/phase2_k8s_base" "${key}"
done
for key in "${component_steps[@]}"; do
    verify_wrapper "${PROJECT_ROOT}/scripts/verify/phase3_ecosystem" "${key}"
done

bash -n "${library}" || fail "验证公共库语法错误"
if LC_ALL=C grep -q $'\r' "${library}"; then fail "验证公共库不是 LF"; fi
if grep -Eq 'PROJECT_ROOT|config\.sh|ssh_exec|(^|[^[:alnum:]_])ssh[[:space:]]' "${library}"; then
    fail "验证公共库含控制端依赖或嵌套 SSH"
fi
if grep -Eq '(^|[;&|[:space:]])(mkdir|rm|mv|cp|install|mount|umount|sed[[:space:]]+-i|kubectl[[:space:]]+(apply|create|delete|label|patch|annotate))[[:space:]]' "${library}"; then
    fail "验证公共库包含修改目标状态的命令"
fi
if grep -E 'exit[[:space:]]+[0-9]+' "${library}" | grep -Ev 'exit[[:space:]]+(0|10|20|21)([;[:space:]]|$)' >/dev/null; then
    fail "验证公共库包含非法退出码"
fi

run_helper() {
    local helper="$1"
    set +e
    bash -c 'log_info(){ :; }; log_success(){ :; }; log_error(){ :; }; source "$1"; "$2" test' \
        bash "${library}" "${helper}" >/dev/null 2>&1
    local status=$?
    set -e
    printf '%s\n' "${status}"
}
[ "$(run_helper vf_satisfied)" -eq 0 ] || fail "已满足退出码应为 0"
[ "$(run_helper vf_missing)" -eq 10 ] || fail "未满足退出码应为 10"
[ "$(run_helper vf_error)" -eq 20 ] || fail "验证异常退出码应为 20"
[ "$(run_helper vf_timeout)" -eq 21 ] || fail "验证超时退出码应为 21"

first_result=$(run_helper vf_missing)
second_result=$(run_helper vf_missing)
[ "${first_result}" = "${second_result}" ] || fail "同一模拟环境重复验证结果不一致"

recovery="${PROJECT_ROOT}/scripts/recovery/phase2_k8s_base/recover-18-init-k8s-cluster-outputs.sh"
[ -f "${recovery}" ] && [ ! -L "${recovery}" ] || fail "Join 产物恢复脚本不可用"
bash -n "${recovery}" || fail "Join 产物恢复脚本语法错误"
if grep -Eq 'log_(info|success|warn|error).*(worker_join|certificate_key|token)' "${recovery}"; then
    fail "Join 产物恢复脚本可能输出敏感值"
fi

printf 'verify contract tests passed\n'
