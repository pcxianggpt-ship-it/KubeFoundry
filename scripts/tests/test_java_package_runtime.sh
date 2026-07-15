#!/bin/bash

set -euo pipefail

PACKAGE="${1:-}"
PORT="${KF_PACKAGE_SMOKE_PORT:-12001}"
TEST_ROOT="$(mktemp -d)"
APP_PID=""

cleanup() {
    if [ -n "${APP_PID}" ]; then
        kill "${APP_PID}" 2>/dev/null || true
        wait "${APP_PID}" 2>/dev/null || true
    fi
    rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT INT TERM

fail() {
    echo "发布包运行时冒烟失败: $*" >&2
    [ -f "${TEST_ROOT}/application.log" ] && tail -n 80 "${TEST_ROOT}/application.log" >&2
    exit 1
}

[ -f "${PACKAGE}" ] || fail "请指定发布包"
for name in tar sha256sum curl grep sed; do
    command -v "${name}" >/dev/null 2>&1 || fail "缺少命令: ${name}"
done

tar -xzf "${PACKAGE}" -C "${TEST_ROOT}"
RELEASE_DIR="$(find "${TEST_ROOT}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -x "${RELEASE_DIR}/runtime/bin/java" ] || fail "包内 Java 不可执行"
[ ! -f "${RELEASE_DIR}/runtime/.test-runtime" ] || fail "不能对测试运行时执行真实冒烟"
(cd "${RELEASE_DIR}" && sha256sum -c SHA256SUMS >/dev/null) || fail "文件校验失败"

DATA_DIR="${TEST_ROOT}/data"
LOG_DIR="${TEST_ROOT}/logs"
mkdir -p "${DATA_DIR}" "${LOG_DIR}"

start_app() {
    KF_DATA_DIR="${DATA_DIR}" KF_LOG_DIR="${LOG_DIR}" KF_WEB_DIR="${RELEASE_DIR}/web" \
        "${RELEASE_DIR}/runtime/bin/java" -jar "${RELEASE_DIR}/app/kubefoundry.jar" \
        --server.port="${PORT}" >"${TEST_ROOT}/application.log" 2>&1 &
    APP_PID=$!
    local ready=0
    for _ in $(seq 1 90); do
        if curl -fsS "http://127.0.0.1:${PORT}/api/health" 2>/dev/null | grep -q '"status":"ok"'; then
            ready=1
            break
        fi
        sleep 1
    done
    [ "${ready}" -eq 1 ] || fail "服务未就绪"
}

stop_app() {
    kill "${APP_PID}"
    wait "${APP_PID}" || true
    APP_PID=""
}

start_app
curl -fsS "http://127.0.0.1:${PORT}/" | grep -q '<div id="app"></div>' || fail "首页未加载前端"
curl -fsS "http://127.0.0.1:${PORT}/jobs/9/execution" | grep -q '<div id="app"></div>' ||
    fail "浏览器深层路由未回退到前端"

cluster_response="$(curl -fsS -X POST -H 'Content-Type: application/json' \
    --data-binary '{"name":"package-smoke","k8s_version":"1.30.14","pod_subnet":"10.244.0.0/16","service_subnet":"10.96.0.0/16"}' \
    "http://127.0.0.1:${PORT}/api/clusters")" || fail "创建集群失败"
cluster_id="$(printf '%s' "${cluster_response}" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')"
[ -n "${cluster_id}" ] || fail "创建集群响应缺少 id"
find "${DATA_DIR}" -maxdepth 1 -name 'kubefoundry.mv.db' -type f | grep -q . || fail "H2 数据文件未创建"

stop_app
start_app
curl -fsS "http://127.0.0.1:${PORT}/api/clusters/${cluster_id}" | grep -q '"name":"package-smoke"' ||
    fail "服务重启后 H2 数据未恢复"

echo "Java 发布包运行时冒烟测试通过"
