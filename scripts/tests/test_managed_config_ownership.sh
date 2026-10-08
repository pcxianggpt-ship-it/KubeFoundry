#!/bin/bash

set -o errexit -o nounset -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

export KF_MANAGED_STATE_DIR="${TEST_ROOT}/state"
source "${PROJECT_ROOT}/scripts/lib/managed_config.sh"

environment_script="${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/15-environment-config.sh"
for managed_path in \
    /etc/modules-load.d/kubefoundry-k8s.conf \
    /etc/sysctl.d/99-kubefoundry-k8s.conf \
    /etc/security/limits.d/99-kubefoundry.conf \
    /etc/systemd/system/kubefoundry-disable-swap.service; do
    grep -Fq "${managed_path}" "${environment_script}"
done
if grep -Eq '/etc/security/limits\.conf|/etc/sysctl\.d/99-sysctl\.conf' \
    "${environment_script}"; then
    printf '[FAIL] 环境脚本仍修改用户共享配置\n' >&2
    exit 1
fi

containerd_script="${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/16-install-containerd.sh"
grep -Fq 'kf_install_replacement' "${containerd_script}"
grep -Fq '# Managed by KubeFoundry v0.3.2' "${containerd_script}"

target="${TEST_ROOT}/config.toml"
source_file="${TEST_ROOT}/new.toml"
printf '%s\n' 'user-original = true' > "${target}"
printf '%s\n' '# Managed by KubeFoundry v0.3.2' 'managed = true' > "${source_file}"

foreign_file="${TEST_ROOT}/foreign.conf"
printf '%s\n' 'user-content' '# Managed by KubeFoundry v0.3.2' > "${foreign_file}"
if kf_require_owned_or_absent "${foreign_file}"; then
    printf '[FAIL] 错误接受了非首行所有权标记\n' >&2
    exit 1
fi

kf_install_replacement "${source_file}" "${target}" test.config 0644
[ "$(stat -c '%a' "${KF_MANAGED_STATE_DIR}")" = 700 ]
[ "$(stat -c '%a' "${KF_MANAGED_MANIFEST}")" = 600 ]
[ "$(stat -c '%a' "${KF_MANAGED_STATE_DIR}/baseline/test.config")" = 600 ]
grep -Fqx 'user-original = true' "${KF_MANAGED_STATE_DIR}/baseline/test.config"
awk -F '\t' '$1 == "test.config" && $3 ~ /^[0-9a-f]{64}$/ && $5 ~ /^[0-9a-f]{64}$/ { found = 1 } END { exit !found }' \
    "${KF_MANAGED_MANIFEST}"

# 重复安装只更新受管版本，不改写首次基线。
kf_install_replacement "${source_file}" "${target}" test.config 0644
[ "$(wc -l < "${KF_MANAGED_MANIFEST}")" -eq 1 ]
grep -Fqx 'user-original = true' "${KF_MANAGED_STATE_DIR}/baseline/test.config"

# 写入已完成但清单仍为 PENDING 的中断可在内容匹配时续跑。
awk -F '\t' -v OFS='\t' '{ $5 = "PENDING"; print }' "${KF_MANAGED_MANIFEST}" > "${KF_MANAGED_MANIFEST}.tmp"
mv "${KF_MANAGED_MANIFEST}.tmp" "${KF_MANAGED_MANIFEST}"
chmod 0600 "${KF_MANAGED_MANIFEST}"
kf_install_replacement "${source_file}" "${target}" test.config 0644
! grep -Fq $'\tPENDING\t' "${KF_MANAGED_MANIFEST}"

# 用户在安装后改过整体替换文件时，必须拒绝覆盖。
printf '%s\n' 'user-changed = true' > "${target}"
if kf_install_replacement "${source_file}" "${target}" test.config 0644; then
    printf '[FAIL] 未拒绝覆盖用户后续修改\n' >&2
    exit 1
fi
grep -Fqx 'user-changed = true' "${target}"

block_file="${TEST_ROOT}/hosts"
block_content="${TEST_ROOT}/hosts.content"
printf '%s\n' '127.0.0.1 localhost' > "${block_file}"
printf '%s\n' '10.0.0.1 cp-a' > "${block_content}"
kf_replace_managed_block "${block_file}" '# >>>KubeFoundry>>>' '# <<<KubeFoundry<<<' "${block_content}"
kf_replace_managed_block "${block_file}" '# >>>KubeFoundry>>>' '# <<<KubeFoundry<<<' "${block_content}"
[ "$(grep -Fxc '# >>>KubeFoundry>>>' "${block_file}")" -eq 1 ]
[ "$(grep -Fxc '# <<<KubeFoundry<<<' "${block_file}")" -eq 1 ]
grep -Fqx '127.0.0.1 localhost' "${block_file}"

printf '%s\n' '# >>>KubeFoundry>>>' >> "${block_file}"
if kf_replace_managed_block "${block_file}" '# >>>KubeFoundry>>>' '# <<<KubeFoundry<<<' "${block_content}"; then
    printf '[FAIL] 未拒绝不完整的受管标记块\n' >&2
    exit 1
fi

printf '[PASS] 受管配置基线、冲突保护和标记块验证通过\n'
