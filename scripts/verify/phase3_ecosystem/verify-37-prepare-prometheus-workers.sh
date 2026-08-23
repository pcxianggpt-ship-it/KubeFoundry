#!/bin/bash

set -o nounset -o pipefail

[ -n "${KF_K8S_HOME:-}" ] || { printf '[ERROR] 验证缺少运行参数: KF_K8S_HOME\n' >&2; exit 20; }
[ -d "${KF_K8S_HOME}/prom_data" ] && [ -w "${KF_K8S_HOME}/prom_data" ] || { printf '[INFO] Prometheus Worker 数据目录未就绪\n'; exit 10; }
timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" df -P "${KF_K8S_HOME}/prom_data" >/dev/null 2>&1
status=$?
case "${status}" in
    0) printf '[SUCCESS] Prometheus Worker 数据目录已就绪\n' ;;
    124|137) printf '[ERROR] 验证命令超时\n' >&2; exit 21 ;;
    *) printf '[ERROR] Prometheus 数据目录文件系统查询失败\n' >&2; exit 20 ;;
esac
