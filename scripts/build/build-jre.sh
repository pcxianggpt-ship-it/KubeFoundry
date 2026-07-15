#!/bin/bash

#===============================================================================
# 脚本名称：build-jre.sh
# 功能：在目标架构主机上生成 KubeFoundry Java 17 精简运行时
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

set -euo pipefail

OUTPUT_DIR="${1:-}"
TARGET_ARCH="${KF_TARGET_ARCH:-}"
TEST_MODE="${KF_PACKAGE_TEST_MODE:-0}"
JAVA_HOME_VALUE="${KF_JAVA_HOME:-${JAVA_HOME:-}}"
TARGET_JDK_HOME="${KF_TARGET_JDK_HOME:-${JAVA_HOME_VALUE}}"
MODULES="java.base,java.compiler,java.desktop,java.instrument,java.logging,java.management,java.naming,java.net.http,java.prefs,java.rmi,java.scripting,java.security.jgss,java.security.sasl,java.sql,java.transaction.xa,java.xml,jdk.crypto.ec,jdk.unsupported"

normalize_arch() {
    case "$1" in
        x86_64|amd64) printf 'x86_64\n' ;;
        aarch64|arm64) printf 'aarch64\n' ;;
        *) return 1 ;;
    esac
}

fail() { echo "JRE 构建失败: $*" >&2; exit 1; }

[ -n "${OUTPUT_DIR}" ] || fail "缺少输出目录"
TARGET_ARCH="$(normalize_arch "${TARGET_ARCH}")" || fail "目标架构必须是 x86_64 或 aarch64"
rm -rf "${OUTPUT_DIR}"

if [ "${TEST_MODE}" = "1" ]; then
    mkdir -p "${OUTPUT_DIR}/bin"
    printf '#!/bin/sh\necho "test-only Java runtime" >&2\nexit 1\n' > "${OUTPUT_DIR}/bin/java"
    chmod 0755 "${OUTPUT_DIR}/bin/java"
    printf '%s\n' "${TARGET_ARCH}" > "${OUTPUT_DIR}/.architecture"
    : > "${OUTPUT_DIR}/.test-runtime"
    exit 0
fi

HOST_ARCH="$(normalize_arch "$(uname -m)")" || fail "不支持的构建机架构: $(uname -m)"
[ -n "${JAVA_HOME_VALUE}" ] || fail "请通过 KF_JAVA_HOME 或 JAVA_HOME 指定 JDK 17"
[ -x "${JAVA_HOME_VALUE}/bin/java" ] || fail "JDK Java 不存在: ${JAVA_HOME_VALUE}/bin/java"
[ -x "${JAVA_HOME_VALUE}/bin/jlink" ] || fail "JDK 缺少 jlink: ${JAVA_HOME_VALUE}/bin/jlink"
[ -d "${TARGET_JDK_HOME}/jmods" ] || fail "目标 JDK 缺少 jmods: ${TARGET_JDK_HOME}/jmods"

JAVA_MAJOR="$("${JAVA_HOME_VALUE}/bin/java" -version 2>&1 | sed -n '1s/.*version "\([0-9][0-9]*\).*/\1/p')"
[ "${JAVA_MAJOR:-0}" -eq 17 ] || fail "必须使用 JDK 17，实际主版本为 ${JAVA_MAJOR:-未知}"

if [ "${HOST_ARCH}" != "${TARGET_ARCH}" ]; then
    command -v file >/dev/null 2>&1 || fail "交叉构建需要 file 命令"
    [ -f "${TARGET_JDK_HOME}/bin/java" ] || fail "目标 JDK 缺少 Java 启动器"
    case "${TARGET_ARCH}:$(file "${TARGET_JDK_HOME}/bin/java")" in
        x86_64:*x86-64*|aarch64:*aarch64*) ;;
        *) fail "目标 JDK 二进制架构与 ${TARGET_ARCH} 不一致" ;;
    esac
fi

"${JAVA_HOME_VALUE}/bin/jlink" \
    --module-path "${TARGET_JDK_HOME}/jmods" \
    --add-modules "${MODULES}" \
    --no-header-files \
    --no-man-pages \
    --compress=2 \
    --output "${OUTPUT_DIR}"

if [ "${HOST_ARCH}" = "${TARGET_ARCH}" ]; then
    RUNTIME_ARCH="$("${OUTPUT_DIR}/bin/java" -XshowSettings:properties -version 2>&1 |
        sed -n 's/^[[:space:]]*os.arch = //p' | head -n 1)"
    RUNTIME_ARCH="$(normalize_arch "${RUNTIME_ARCH}")" || fail "无法识别运行时架构: ${RUNTIME_ARCH}"
    [ "${RUNTIME_ARCH}" = "${TARGET_ARCH}" ] || fail "运行时架构 ${RUNTIME_ARCH} 与目标架构 ${TARGET_ARCH} 不一致"
else
    case "${TARGET_ARCH}:$(file "${OUTPUT_DIR}/bin/java")" in
        x86_64:*x86-64*|aarch64:*aarch64*) ;;
        *) fail "生成的运行时二进制架构与 ${TARGET_ARCH} 不一致" ;;
    esac
fi
printf '%s\n' "${TARGET_ARCH}" > "${OUTPUT_DIR}/.architecture"
