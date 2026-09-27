#!/bin/bash

#===============================================================================
# 脚本名称：test_environment_sysctl.sh
# 功能：验证 sysctl 覆盖修复、幂等性及失败诊断
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================
set -euo pipefail
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export TEST_ROOT
mkdir -p "${TEST_ROOT}"/{bin,etc/systemd/system,etc/modules-load.d,etc/sysctl.d,etc/security/limits.d}
cp "${PROJECT_ROOT}/scripts/lib/managed_config.sh" "${TEST_ROOT}/managed_config.sh"
sed "s|/etc/|${TEST_ROOT}/etc/|g" "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/15-environment-config.sh" > "${TEST_ROOT}/step.sh"
printf 'net.ipv4.ip_forward=0\n# user configuration\n' > "${TEST_ROOT}/etc/sysctl.conf"
cp "${TEST_ROOT}/etc/sysctl.conf" "${TEST_ROOT}/original"
ln -s ../sysctl.conf "${TEST_ROOT}/etc/sysctl.d/99-sysctl.conf"
for command in swapoff systemctl yum modprobe; do
    printf '#!/bin/bash\nexit 0\n' > "${TEST_ROOT}/bin/${command}"
done
cat > "${TEST_ROOT}/bin/sysctl" <<'MOCK'
#!/bin/bash
if [ "$1" = --system ]; then
    [ "${FAIL_LOAD:-0}" = 0 ] || exit 1
    awk -F= '/^net.ipv4.ip_forward[[:space:]]*=/ { gsub(/ /,"",$2); value=$2 } END { print value }' \
        "${TEST_ROOT}/etc/sysctl.d/99-kubefoundry-k8s.conf" "${TEST_ROOT}/etc/sysctl.conf" > "${TEST_ROOT}/value"
else
    [ "${FAIL_READ:-0}" = 0 ] || exit 1
    if [ "${WRONG_VALUE:-0}" = 1 ]; then echo 0
    elif [ "$2" = net.ipv4.ip_forward ]; then cat "${TEST_ROOT}/value"
    else echo 1; fi
fi
MOCK
chmod +x "${TEST_ROOT}/bin/"*
export PATH="${TEST_ROOT}/bin:${PATH}"
log_info() { echo "$*"; }
log_success() { echo "SUCCESS $*"; }
log_error() { echo "ERROR $*"; }
export -f log_info log_success log_error
run_step() { (cd "${TEST_ROOT}" && bash ./step.sh) > "${TEST_ROOT}/output" 2>&1; }
run_step
[ "$(cat "${TEST_ROOT}/value")" = 1 ]
run_step
[ "$(grep -Fc '# >>>KubeFoundry sysctl>>>' "${TEST_ROOT}/etc/sysctl.conf")" = 1 ]
grep -Fxq 'net.ipv4.ip_forward=0' "${TEST_ROOT}/etc/sysctl.conf"
for failure in FAIL_LOAD FAIL_READ WRONG_VALUE; do
    export "${failure}=1"
    if run_step; then echo "FAIL: ${failure} 未失败"; exit 1; fi
    ! grep -q SUCCESS "${TEST_ROOT}/output"
    grep -q ERROR "${TEST_ROOT}/output"
    unset "${failure}"
done
# 使用实际重置函数移除标记块，确认原配置完整保留。
sed '/^require_safe_work_dir "${KF_K8S_HOME:-}"/,$d' \
    "${PROJECT_ROOT}/scripts/steps/reset/reset-kubernetes-node.sh" > "${TEST_ROOT}/reset-functions.sh"
source "${TEST_ROOT}/reset-functions.sh"
remove_managed_block "${TEST_ROOT}/etc/sysctl.conf" '# >>>KubeFoundry sysctl>>>' '# <<<KubeFoundry sysctl<<<'
cmp "${TEST_ROOT}/original" "${TEST_ROOT}/etc/sysctl.conf"
# 校验脚本读取错误返回 20，值错误返回 10。
sed "s|/etc/|${TEST_ROOT}/etc/|g" "${PROJECT_ROOT}/scripts/verify/phase2_k8s_base/verify-15-environment-config.sh" > "${TEST_ROOT}/verify.sh"
printf '#!/bin/bash\nexit 0\n' > "${TEST_ROOT}/bin/swapon"
chmod +x "${TEST_ROOT}/bin/swapon"
for mode in FAIL_READ WRONG_VALUE; do
    export "${mode}=1"
    code=0
    bash "${TEST_ROOT}/verify.sh" > "${TEST_ROOT}/output" 2>&1 || code=$?
    if [ "${mode}" = FAIL_READ ]; then [ "${code}" = 20 ]; else [ "${code}" = 10 ]; fi
    unset "${mode}"
done
printf '[PASS] sysctl 覆盖、幂等、回滚和失败诊断通过\n'
