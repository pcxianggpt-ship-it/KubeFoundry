#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
run() {
    command -v timeout >/dev/null 2>&1 || error "验证工具不可用: timeout"
    command -v "$1" >/dev/null 2>&1 || error "验证工具不可用: $1"
    timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" "$@"
    local status=$?
    case "${status}" in 124|137) printf '[ERROR] 验证命令超时\n' >&2; exit 21 ;; esac
    return "${status}"
}

if command -v nerdctl >/dev/null 2>&1; then
    container_cmd=nerdctl
elif command -v docker >/dev/null 2>&1; then
    container_cmd=docker
else
    error "无法验证 Registry：未找到容器运行时"
fi
running=$(run "${container_cmd}" inspect --format '{{.State.Running}}' registry 2>/dev/null); status=$?
[ "${status}" -ne 21 ] || exit 21
[ "${status}" -eq 0 ] && [ "${running}" = true ] || missing "Registry 容器未运行"
running=$(run "${container_cmd}" inspect --format '{{.State.Running}}' registry-ui-5080 2>/dev/null); status=$?
[ "${status}" -ne 21 ] || exit 21
[ "${status}" -eq 0 ] && [ "${running}" = true ] || missing "Registry UI 容器未运行"
run curl --fail --silent --show-error "http://127.0.0.1:${KF_REGISTRY_PORT:-5000}/v2/" >/dev/null 2>&1 || error "Registry API 不可用"
printf '[SUCCESS] Registry 和 UI 已就绪\n'
