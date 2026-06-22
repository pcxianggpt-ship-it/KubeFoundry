#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "${TEST_ROOT}"
    rm -rf "${PROJECT_ROOT}/dist"
}
trap cleanup EXIT

fail() {
    echo "测试失败: $*" >&2
    exit 1
}

[ -f "${PROJECT_ROOT}/package.sh" ] || fail "package.sh 不存在"
[ -f "${PROJECT_ROOT}/deploy.sh" ] || fail "deploy.sh 不存在"

grep -q 'exec bash "\$0" "\$@"' "${PROJECT_ROOT}/package.sh" ||
    fail "package.sh 缺少 sh 到 Bash 的兼容切换"
grep -q 'exec bash "\$0" "\$@"' "${PROJECT_ROOT}/deploy.sh" ||
    fail "deploy.sh 缺少 sh 到 Bash 的兼容切换"

for requirement in \
    "Jinja2==3.1.2" \
    "itsdangerous==2.1.2" \
    "click==8.1.7" \
    "MarkupSafe==2.1.5" \
    "importlib-metadata==6.7.0" \
    "zipp==3.15.0" \
    "packaging==23.2"; do
    grep -qx "${requirement}" "${PROJECT_ROOT}/web/backend/requirements.txt" ||
        fail "缺少 Python 3.7 兼容依赖锁定: ${requirement}"
done

bash "${PROJECT_ROOT}/package.sh" --help | grep -q "kubefoundry-web-v" ||
    fail "package.sh 帮助信息缺少发布包名称"
bash "${PROJECT_ROOT}/deploy.sh" --help | grep -q -- "--port PORT" ||
    fail "deploy.sh 帮助信息缺少端口参数"
bash "${PROJECT_ROOT}/deploy.sh" --help | grep -q "10001" ||
    fail "deploy.sh 默认端口不是 10001"
sh "${PROJECT_ROOT}/package.sh" --help | grep -q "kubefoundry-web-v" ||
    fail "package.sh 不支持通过 sh 启动"
sh "${PROJECT_ROOT}/deploy.sh" --help | grep -q -- "--port PORT" ||
    fail "deploy.sh 不支持通过 sh 启动"

KF_PACKAGE_TEST_MODE=1 bash "${PROJECT_ROOT}/package.sh"
PACKAGE="${PROJECT_ROOT}/dist/kubefoundry-web-v0.1.0.tar.gz"
[ -f "${PACKAGE}" ] || fail "测试发布包未生成"

package_list="$(tar -tzf "${PACKAGE}")"
for expected in \
    "kubefoundry-web-v0.1.0/deploy.sh" \
    "kubefoundry-web-v0.1.0/backend/app.py" \
    "kubefoundry-web-v0.1.0/frontend-dist/index.html" \
    "kubefoundry-web-v0.1.0/vendor/.keep" \
    "kubefoundry-web-v0.1.0/requirements.txt" \
    "kubefoundry-web-v0.1.0/VERSION" \
    "kubefoundry-web-v0.1.0/SHA256SUMS"; do
    grep -q "${expected}" <<< "${package_list}" ||
        fail "发布包缺少 ${expected}"
done

mkdir -p "${TEST_ROOT}/deployment/data"
echo "keep" > "${TEST_ROOT}/deployment/data/keep.txt"
(
    cd "${TEST_ROOT}/deployment"
    KF_DEPLOY_TEST_MODE=1 bash "${PROJECT_ROOT}/deploy.sh" --port 11001 "${PACKAGE}"
)

[ -f "${TEST_ROOT}/deployment/data/keep.txt" ] ||
    fail "重复部署删除了 data 目录"
[ -f "${TEST_ROOT}/deployment/app/backend/production_wsgi.py" ] ||
    fail "未生成生产 WSGI 入口"

SERVICE_FILE="${TEST_ROOT}/deployment/logs/kubefoundry-web.service.test"
[ -f "${SERVICE_FILE}" ] || fail "测试 service 文件未生成"
grep -q "WorkingDirectory=${TEST_ROOT}/deployment/app/backend" "${SERVICE_FILE}" ||
    fail "service 工作目录不正确"
grep -q "KF_DB_PATH=${TEST_ROOT}/deployment/data/kubefoundry.db" "${SERVICE_FILE}" ||
    fail "service 数据库路径不正确"
grep -q "0.0.0.0:11001" "${SERVICE_FILE}" ||
    fail "service 自定义端口不正确"

grep -q "bash package.sh" "${PROJECT_ROOT}/README.md" ||
    fail "README 缺少一键打包命令"
grep -q "sudo bash deploy.sh" "${PROJECT_ROOT}/README.md" ||
    fail "README 缺少一键部署命令"
grep -q "10001" "${PROJECT_ROOT}/doc/v0.1.0/web-wizard-v0.1.0-usage.md" ||
    fail "使用说明缺少生产端口"
grep -q '${PWD}/data' "${PROJECT_ROOT}/doc/v0.1.0/web-wizard-v0.1.0-usage.md" ||
    fail "使用说明缺少数据目录"

echo "Web 打包部署脚本测试通过"
