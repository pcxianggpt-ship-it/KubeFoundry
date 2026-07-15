#!/bin/bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BACKEND_DIR="${PROJECT_ROOT}/web/backend-java"
FRONTEND_DIR="${PROJECT_ROOT}/web/frontend"
TEST_ROOT=$(mktemp -d)
API_PORT=${KF_SMOKE_API_PORT:-11001}
WEB_PORT=${KF_SMOKE_WEB_PORT:-15173}
BACKEND_PID=""
FRONTEND_PID=""

cleanup() {
    if [ -n "${FRONTEND_PID}" ]; then
        kill "${FRONTEND_PID}" 2>/dev/null || true
        wait "${FRONTEND_PID}" 2>/dev/null || true
    fi
    if [ -n "${BACKEND_PID}" ]; then
        kill "${BACKEND_PID}" 2>/dev/null || true
        wait "${BACKEND_PID}" 2>/dev/null || true
    fi
    rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT INT TERM

fail() {
    echo "Java Web 冒烟测试失败: $*" >&2
    [ -f "${TEST_ROOT}/backend.log" ] && tail -n 40 "${TEST_ROOT}/backend.log" >&2
    [ -f "${TEST_ROOT}/frontend.log" ] && tail -n 20 "${TEST_ROOT}/frontend.log" >&2
    exit 1
}

for command in java mvn npm curl sed; do
    command -v "${command}" >/dev/null 2>&1 || fail "缺少命令: ${command}"
done

java_major=$(java -version 2>&1 | sed -n '1s/.*version "\([0-9][0-9]*\).*/\1/p')
[ "${java_major:-0}" -ge 17 ] || fail "需要 Java 17 或更高版本"

(cd "${BACKEND_DIR}" && mvn -q -DskipTests package)

KF_DATA_DIR="${TEST_ROOT}/data" \
    java -jar "${BACKEND_DIR}/target/kubefoundry-backend-0.2.0.jar" \
    --server.port="${API_PORT}" >"${TEST_ROOT}/backend.log" 2>&1 &
BACKEND_PID=$!

(
    cd "${FRONTEND_DIR}"
    KF_API_TARGET="http://127.0.0.1:${API_PORT}" \
        npm run dev -- --host 127.0.0.1 --port "${WEB_PORT}" --strictPort
) >"${TEST_ROOT}/frontend.log" 2>&1 &
FRONTEND_PID=$!

base_url="http://127.0.0.1:${WEB_PORT}"
ready=0
for _ in $(seq 1 90); do
    if health=$(curl -fsS "${base_url}/api/health" 2>/dev/null); then
        case "${health}" in
            *'"status":"ok"'*'"version":"0.2.0"'*) ready=1; break ;;
        esac
    fi
    sleep 1
done
[ "${ready}" -eq 1 ] || fail "Java 后端或前端代理未就绪"

cluster_json='{"name":"smoke-contract","k8s_version":"1.30.14","pod_subnet":"10.244.0.0/16","service_subnet":"10.96.0.0/16"}'
cluster_response=$(curl -fsS -X POST -H 'Content-Type: application/json' \
    --data-binary "${cluster_json}" "${base_url}/api/clusters") || fail "创建集群失败"
cluster_id=$(printf '%s' "${cluster_response}" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
[ -n "${cluster_id}" ] || fail "创建集群响应缺少 id"

node_secret=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)
[ "${#node_secret}" -eq 24 ] || fail "无法生成临时节点凭据"
printf '{"hostname":"smoke-node","ip":"127.0.0.1","role":"control_plane","ssh_user":"root","ssh_port":1,"password":"%s"}' \
    "${node_secret}" >"${TEST_ROOT}/node.json"
node_response=$(curl -fsS -X POST -H 'Content-Type: application/json' \
    --data-binary @"${TEST_ROOT}/node.json" "${base_url}/api/clusters/${cluster_id}/nodes") ||
    fail "添加节点失败"
rm -f "${TEST_ROOT}/node.json"
case "${node_response}" in
    *"${node_secret}"*) fail "节点响应泄漏临时凭据" ;;
esac
unset node_secret
case "${node_response}" in
    *'"hostname":"smoke-node"'*'"has_password":true'*) ;;
    *) fail "节点响应缺少关键字段" ;;
esac

test_response=$(curl -fsS -X POST "${base_url}/api/clusters/${cluster_id}/node-test") ||
    fail "节点测试任务创建失败"
job_id=$(printf '%s' "${test_response}" | sed -n 's/.*"job_id":\([0-9][0-9]*\).*/\1/p')
[ -n "${job_id}" ] || fail "节点测试响应缺少 job_id"

terminal=0
for _ in $(seq 1 30); do
    job_response=$(curl -fsS "${base_url}/api/jobs/${job_id}") || fail "任务查询失败"
    case "${job_response}" in
        *'"job_type":"node_test"'*'"status":"failed"'*) terminal=1; break ;;
        *'"job_type":"node_test"'*'"status":"success"'*) terminal=1; break ;;
    esac
    sleep 1
done
[ "${terminal}" -eq 1 ] || fail "节点测试任务未进入终态"

curl -sS -N --max-time 8 -D "${TEST_ROOT}/sse.headers" \
    "${base_url}/api/jobs/${job_id}/events" >"${TEST_ROOT}/sse.body" || true
grep -qi '^Content-Type: text/event-stream' "${TEST_ROOT}/sse.headers" ||
    fail "SSE 响应类型不正确"
grep -q 'event:job.status' "${TEST_ROOT}/sse.body" || fail "SSE 缺少任务状态事件"

jobs_response=$(curl -fsS "${base_url}/api/jobs?cluster_id=${cluster_id}") || fail "任务列表查询失败"
case "${jobs_response}" in
    *"\"id\":${job_id}"*'"job_type":"node_test"'*) ;;
    *) fail "任务列表缺少节点测试任务" ;;
esac

echo "Java Web 端到端冒烟测试通过"
