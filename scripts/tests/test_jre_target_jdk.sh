#!/bin/bash

#===============================================================================
# 脚本名称：test_jre_target_jdk.sh
# 功能：验证发布包构建入口的目标 JDK 选择与架构保护
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

set -euo pipefail
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export MOCK_JLINK_LOG="${TEST_ROOT}/jlink.log"
mkdir -p "${TEST_ROOT}/bin"
printf '#!/bin/bash\nprintf "x86_64\\n"\n' > "${TEST_ROOT}/bin/uname"
cat > "${TEST_ROOT}/bin/file" <<'EOF'
#!/bin/bash
arch=$(cat "$(dirname "$1")/../.mock-arch")
case "${arch}" in x86_64) arch=x86-64 ;; esac
printf '%s: ELF 64-bit %s\n' "$1" "${arch}"
EOF
for jdk in host arm explicit; do
    mkdir -p "${TEST_ROOT}/${jdk}/bin" "${TEST_ROOT}/${jdk}/jmods"
    if [ "${jdk}" = host ]; then arch=x86_64; else arch=aarch64; fi
    printf '%s\n' "${arch}" > "${TEST_ROOT}/${jdk}/.mock-arch"
    cat > "${TEST_ROOT}/${jdk}/bin/java" <<'EOF'
#!/bin/bash
printf 'openjdk version "17.0.17"\n' >&2
if [ "${1:-}" = -XshowSettings:properties ]; then
    printf '    os.arch = %s\n' "$(cat "$(dirname "$0")/../.mock-arch")" >&2
fi
EOF
done
cat > "${TEST_ROOT}/host/bin/jlink" <<'EOF'
#!/bin/bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
    case "$1" in
        --module-path) module_path="$2"; shift 2 ;;
        --output) output="$2"; shift 2 ;;
        *) shift ;;
    esac
done
printf '%s\n' "${module_path}" > "${MOCK_JLINK_LOG}"
mkdir -p "${output}/bin"
cp "${module_path}/../bin/java" "${output}/bin/java"
cp "${module_path}/../.mock-arch" "${output}/.mock-arch"
EOF
chmod +x "${TEST_ROOT}/bin/"* "${TEST_ROOT}/"*/bin/*
export PATH="${TEST_ROOT}/bin:${PATH}"
export KF_JAVA_HOME="${TEST_ROOT}/host" KF_ARM_JAVA_HOME="${TEST_ROOT}/arm"
unset KF_TARGET_JDK_HOME
TARGET_ARCH=aarch64
TEST_MODE=0
# 调用实际发布脚本的构建入口，防止 package.sh 再次覆盖目标 JDK 回退规则。
sed -n '/^build_runtime() {/,/^}/p' "${PROJECT_ROOT}/package.sh" > "${TEST_ROOT}/package-runtime.sh"
source "${TEST_ROOT}/package-runtime.sh"
build_runtime "${TEST_ROOT}/release"
[ "$(cat "${MOCK_JLINK_LOG}")" = "${TEST_ROOT}/arm/jmods" ]
[ "$(cat "${TEST_ROOT}/release/runtime/.architecture")" = aarch64 ]

export KF_TARGET_JDK_HOME="${TEST_ROOT}/explicit"
build_runtime "${TEST_ROOT}/release"
[ "$(cat "${MOCK_JLINK_LOG}")" = "${TEST_ROOT}/explicit/jmods" ]
export KF_TARGET_JDK_HOME="${TEST_ROOT}/host"
if build_runtime "${TEST_ROOT}/release" > "${TEST_ROOT}/failure.log" 2>&1; then
    echo 'FAIL: 显式指定错误架构的目标 JDK 未被拒绝' >&2; exit 1
fi
grep -Fq "${TEST_ROOT}/host/bin/java" "${TEST_ROOT}/failure.log"
unset KF_TARGET_JDK_HOME KF_ARM_JAVA_HOME
if build_runtime "${TEST_ROOT}/release" > "${TEST_ROOT}/failure.log" 2>&1; then
    echo 'FAIL: 未提供 ARM JDK 时错误接受了宿主 JDK' >&2; exit 1
fi
grep -Fq '请设置 KF_TARGET_JDK_HOME' "${TEST_ROOT}/failure.log"

export KF_ARM_JAVA_HOME="${TEST_ROOT}/arm"
TARGET_ARCH=x86_64
build_runtime "${TEST_ROOT}/release"
[ "$(cat "${MOCK_JLINK_LOG}")" = "${TEST_ROOT}/host/jmods" ]
[ "$(cat "${TEST_ROOT}/release/runtime/.architecture")" = x86_64 ]
printf '[PASS] 目标 JDK 回退、显式优先级、错误架构保护和原生构建通过\n'
