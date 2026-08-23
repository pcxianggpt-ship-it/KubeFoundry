#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
[ -n "${KF_CONTAINERD_ROOT:-}" ] || { printf '[ERROR] 验证缺少运行参数: KF_CONTAINERD_ROOT\n' >&2; exit 20; }
command -v systemctl >/dev/null 2>&1 || { printf '[ERROR] 验证工具不可用: systemctl\n' >&2; exit 20; }
systemctl is-active --quiet containerd || missing "containerd 未运行"
for tool in runc nerdctl; do
    command -v "${tool}" >/dev/null 2>&1 || missing "容器运行时工具未安装: ${tool}"
done
grep -Eq '^[[:space:]]*root[[:space:]]*=[[:space:]]*"'"${KF_CONTAINERD_ROOT}"'"' /etc/containerd/config.toml 2>/dev/null || missing "containerd 数据目录不匹配"
printf '[SUCCESS] containerd 及受管数据目录已就绪\n'
