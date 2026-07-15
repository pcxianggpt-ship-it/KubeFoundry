#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
DIST_DIR="${TEST_ROOT}/dist"

cleanup() {
    rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

fail() {
    echo "测试失败: $*" >&2
    exit 1
}

for file in package.sh deploy.sh scripts/build/build-jre.sh; do
    [ -f "${PROJECT_ROOT}/${file}" ] || fail "缺少 ${file}"
done

grep -q 'KF_PACKAGE_BASH_REEXEC' "${PROJECT_ROOT}/package.sh" || fail "package.sh 缺少 Bash 兼容切换"
grep -q 'KF_DEPLOY_BASH_REEXEC' "${PROJECT_ROOT}/deploy.sh" || fail "deploy.sh 缺少 Bash 兼容切换"
if grep -Eqi 'python|gunicorn|production_wsgi' "${PROJECT_ROOT}/package.sh" "${PROJECT_ROOT}/deploy.sh"; then
    fail "Java 发布脚本仍包含 Python 或 Gunicorn"
fi

bash "${PROJECT_ROOT}/package.sh" --help | grep -Fq 'v0.2.0-{x86_64|aarch64}' ||
    fail "打包帮助缺少双架构包名"
bash "${PROJECT_ROOT}/deploy.sh" --help | grep -q -- '--port PORT' || fail "部署帮助缺少端口参数"
sh "${PROJECT_ROOT}/package.sh" --help >/dev/null || fail "package.sh 不支持 sh 启动"
sh "${PROJECT_ROOT}/deploy.sh" --help >/dev/null || fail "deploy.sh 不支持 sh 启动"

for arch in x86_64 aarch64; do
    KF_PACKAGE_TEST_MODE=1 KF_TARGET_ARCH="${arch}" KF_DIST_DIR="${DIST_DIR}" \
        bash "${PROJECT_ROOT}/package.sh"
    package="${DIST_DIR}/kubefoundry-web-v0.2.0-${arch}.tar.gz"
    [ -f "${package}" ] || fail "未生成 ${arch} 测试包"

    package_list="$(tar -tzf "${package}")"
    prefix="kubefoundry-web-v0.2.0-${arch}"
    for expected in \
        "${prefix}/runtime/bin/java" \
        "${prefix}/runtime/.architecture" \
        "${prefix}/app/kubefoundry.jar" \
        "${prefix}/web/index.html" \
        "${prefix}/scripts/steps/" \
        "${prefix}/deploy.sh" \
        "${prefix}/VERSION" \
        "${prefix}/ARCHITECTURE" \
        "${prefix}/SHA256SUMS"; do
        grep -Fq "${expected}" <<< "${package_list}" || fail "${arch} 包缺少 ${expected}"
    done

    mkdir -p "${TEST_ROOT}/inspect-${arch}"
    tar -xzf "${package}" -C "${TEST_ROOT}/inspect-${arch}"
    release="${TEST_ROOT}/inspect-${arch}/${prefix}"
    [ "$(cat "${release}/ARCHITECTURE")" = "${arch}" ] || fail "包架构文件错误"
    [ "$(cat "${release}/runtime/.architecture")" = "${arch}" ] || fail "运行时架构错误"
    (cd "${release}" && sha256sum -c SHA256SUMS >/dev/null) || fail "包内校验和错误"
done

PACKAGE="${DIST_DIR}/kubefoundry-web-v0.2.0-x86_64.tar.gz"
mkdir -p "${TEST_ROOT}/deployment/data"
printf 'keep\n' > "${TEST_ROOT}/deployment/data/keep.txt"
(
    cd "${TEST_ROOT}/deployment"
    KF_DEPLOY_TEST_MODE=1 bash "${PROJECT_ROOT}/deploy.sh" --port 11001 "${PACKAGE}"
)

[ -f "${TEST_ROOT}/deployment/data/keep.txt" ] || fail "重复部署删除了 data 目录"
[ -x "${TEST_ROOT}/deployment/app/runtime/bin/java" ] || fail "运行时 Java 不可执行"
[ -f "${TEST_ROOT}/deployment/app/app/kubefoundry.jar" ] || fail "未安装 Java JAR"
[ -f "${TEST_ROOT}/deployment/app/web/index.html" ] || fail "未安装前端"
[ -d "${TEST_ROOT}/deployment/scripts/steps" ] || fail "未安装步骤脚本"

SERVICE_FILE="${TEST_ROOT}/deployment/logs/kubefoundry-web.service.test"
[ -f "${SERVICE_FILE}" ] || fail "测试 service 文件未生成"
grep -Fq "WorkingDirectory=${TEST_ROOT}/deployment/app" "${SERVICE_FILE}" || fail "工作目录错误"
grep -Fq "Environment=KF_DATA_DIR=${TEST_ROOT}/deployment/data" "${SERVICE_FILE}" || fail "数据目录错误"
grep -Fq "Environment=KF_LOG_DIR=${TEST_ROOT}/deployment/logs" "${SERVICE_FILE}" || fail "日志目录错误"
grep -Fq "Environment=KF_WEB_DIR=${TEST_ROOT}/deployment/app/web" "${SERVICE_FILE}" || fail "前端目录错误"
grep -Fq -- "--server.port=11001" "${SERVICE_FILE}" || fail "自定义端口错误"
grep -Fq '/runtime/bin/java -jar ' "${SERVICE_FILE}" || fail "服务未使用包内 Java"

if KF_DEPLOY_TEST_MODE=1 KF_TEST_HOST_ARCH=aarch64 bash "${PROJECT_ROOT}/deploy.sh" "${PACKAGE}" \
    >"${TEST_ROOT}/mismatch.log" 2>&1; then
    fail "部署脚本未拒绝架构不匹配的发布包"
fi
grep -q '架构不匹配' "${TEST_ROOT}/mismatch.log" || fail "架构不匹配错误不清晰"

echo "Java Web 双架构打包部署脚本测试通过"
