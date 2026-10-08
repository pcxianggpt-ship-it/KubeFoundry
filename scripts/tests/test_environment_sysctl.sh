#!/bin/bash

#===============================================================================
# 脚本名称：test_environment_sysctl.sh
# 功能：验证 DNS 兜底、sysctl 覆盖修复、幂等性及失败诊断
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
printf 'nameserver 8.8.8.8\n' > "${TEST_ROOT}/expected-resolv"
cmp "${TEST_ROOT}/expected-resolv" "${TEST_ROOT}/etc/resolv.conf"
[ "$(cat "${TEST_ROOT}/value")" = 1 ]
run_step
cmp "${TEST_ROOT}/expected-resolv" "${TEST_ROOT}/etc/resolv.conf"
[ "$(grep -Fc '# >>>KubeFoundry sysctl>>>' "${TEST_ROOT}/etc/sysctl.conf")" = 1 ]
grep -Fxq 'net.ipv4.ip_forward=0' "${TEST_ROOT}/etc/sysctl.conf"
# 已有 IPv4、IPv6 或缩进的 nameserver 时，内容及文件时间保持不变。
for content in 'nameserver 10.0.0.2' $'\t nameserver\t2001:db8::53' $'nameserver 10.0.0.2\nnameserver 10.0.0.3'; do
    printf '%s' "${content}" > "${TEST_ROOT}/etc/resolv.conf"
    cp -p "${TEST_ROOT}/etc/resolv.conf" "${TEST_ROOT}/expected-resolv"
    run_step
    cmp "${TEST_ROOT}/expected-resolv" "${TEST_ROOT}/etc/resolv.conf"
    [ "$(stat -c '%y' "${TEST_ROOT}/expected-resolv")" = "$(stat -c '%y' "${TEST_ROOT}/etc/resolv.conf")" ]
done
# 空文件、只有注释、无末尾换行和空 nameserver 指令均补充一条，重复执行不重复追加。
for content in '' $'# nameserver 10.0.0.2\nsearch example.internal\n' 'search example.internal' $'nameserver\nnameserver # missing address\nnameserver ; missing address\n'; do
    printf '%s' "${content}" > "${TEST_ROOT}/etc/resolv.conf"
    printf '%s' "${content}" > "${TEST_ROOT}/expected-resolv"
    if [ -n "${content}" ] && [[ "${content}" != *$'\n' ]]; then
        printf '\n' >> "${TEST_ROOT}/expected-resolv"
    fi
    printf 'nameserver 8.8.8.8\n' >> "${TEST_ROOT}/expected-resolv"
    run_step
    run_step
    cmp "${TEST_ROOT}/expected-resolv" "${TEST_ROOT}/etc/resolv.conf"
done
# 跟随系统常见的 resolv.conf 符号链接，不替换链接本身。
mv "${TEST_ROOT}/etc/resolv.conf" "${TEST_ROOT}/resolver.conf"
ln -s ../resolver.conf "${TEST_ROOT}/etc/resolv.conf"
printf 'nameserver 10.0.0.2\n' > "${TEST_ROOT}/resolver.conf"
cp "${TEST_ROOT}/resolver.conf" "${TEST_ROOT}/expected-resolv"
run_step
cmp "${TEST_ROOT}/expected-resolv" "${TEST_ROOT}/resolver.conf"
[ "$(readlink "${TEST_ROOT}/etc/resolv.conf")" = ../resolver.conf ]
printf 'search example.internal' > "${TEST_ROOT}/resolver.conf"
printf 'search example.internal\nnameserver 8.8.8.8\n' > "${TEST_ROOT}/expected-resolv"
run_step
cmp "${TEST_ROOT}/expected-resolv" "${TEST_ROOT}/resolver.conf"
[ -L "${TEST_ROOT}/etc/resolv.conf" ]
# 读取异常或写入失败必须中止，输出可定位的错误。
rm "${TEST_ROOT}/etc/resolv.conf"
mkdir "${TEST_ROOT}/etc/resolv.conf"
if run_step; then echo 'FAIL: DNS 读取异常未失败'; exit 1; fi
grep -q 'ERROR.*读取.*resolv.conf' "${TEST_ROOT}/output"
rmdir "${TEST_ROOT}/etc/resolv.conf"
ln -s ../missing-parent/resolv.conf "${TEST_ROOT}/etc/resolv.conf"
if run_step; then cat "${TEST_ROOT}/output"; echo 'FAIL: DNS 写入异常未失败'; exit 1; fi
grep -q 'ERROR.*写入.*resolv.conf' "${TEST_ROOT}/output"
rm "${TEST_ROOT}/etc/resolv.conf"
run_step
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
sed -e "s|/etc/|${TEST_ROOT}/etc/|g" -e "s|/proc/modules|${TEST_ROOT}/modules|g" \
    "${PROJECT_ROOT}/scripts/verify/phase2_k8s_base/verify-15-environment-config.sh" > "${TEST_ROOT}/verify.sh"
printf 'overlay\nbr_netfilter\n' > "${TEST_ROOT}/modules"
printf '#!/bin/bash\nexit 0\n' > "${TEST_ROOT}/bin/swapon"
chmod +x "${TEST_ROOT}/bin/swapon"
bash "${TEST_ROOT}/verify.sh" > "${TEST_ROOT}/output" 2>&1
for content in '' '# nameserver 8.8.8.8' 'nameserver # missing address'; do
    printf '%s' "${content}" > "${TEST_ROOT}/etc/resolv.conf"
    code=0
    bash "${TEST_ROOT}/verify.sh" > "${TEST_ROOT}/output" 2>&1 || code=$?
    [ "${code}" = 10 ]
    grep -q '尚未配置 nameserver' "${TEST_ROOT}/output"
done
rm "${TEST_ROOT}/etc/resolv.conf"
code=0
bash "${TEST_ROOT}/verify.sh" > "${TEST_ROOT}/output" 2>&1 || code=$?
[ "${code}" = 10 ]
printf '\t nameserver\t2001:db8::53\n' > "${TEST_ROOT}/etc/resolv.conf"
bash "${TEST_ROOT}/verify.sh" > "${TEST_ROOT}/output" 2>&1
for mode in FAIL_READ WRONG_VALUE; do
    export "${mode}=1"
    code=0
    bash "${TEST_ROOT}/verify.sh" > "${TEST_ROOT}/output" 2>&1 || code=$?
    if [ "${mode}" = FAIL_READ ]; then [ "${code}" = 20 ]; else [ "${code}" = 10 ]; fi
    unset "${mode}"
done
printf '[PASS] DNS 兜底与保留、sysctl 覆盖、幂等、回滚和失败诊断通过\n'
