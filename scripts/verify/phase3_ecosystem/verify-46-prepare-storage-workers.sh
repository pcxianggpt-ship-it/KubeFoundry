#!/bin/bash

set -o nounset -o pipefail

[ -n "${KF_K8S_HOME:-}" ] || { printf '[ERROR] 验证缺少运行参数: KF_K8S_HOME\n' >&2; exit 20; }
for directory in openebs-root minio-root loki-root; do
    [ -d "${KF_K8S_HOME}/${directory}" ] && [ -w "${KF_K8S_HOME}/${directory}" ] || { printf '[INFO] Worker 存储目录未就绪: %s\n' "${directory}"; exit 10; }
done
timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" df -P "${KF_K8S_HOME}" >/dev/null 2>&1
status=$?
case "${status}" in
    0) printf '[SUCCESS] Worker 存储目录已就绪\n' ;;
    124|137) printf '[ERROR] 验证命令超时\n' >&2; exit 21 ;;
    *) printf '[ERROR] Worker 存储文件系统查询失败\n' >&2; exit 20 ;;
esac
