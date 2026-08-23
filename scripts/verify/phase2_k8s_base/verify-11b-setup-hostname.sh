#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
[ -n "${KF_NODE_HOSTNAME:-}" ] || { printf '[ERROR] 验证缺少运行参数: KF_NODE_HOSTNAME\n' >&2; exit 20; }
[ -n "${KF_NODE_IP:-}" ] || { printf '[ERROR] 验证缺少运行参数: KF_NODE_IP\n' >&2; exit 20; }
[ "$(hostname)" = "${KF_NODE_HOSTNAME}" ] || missing "当前节点主机名未配置"
grep -qF '# >>>KubeFoundry>>>' /etc/hosts 2>/dev/null || missing "/etc/hosts 受管块不存在"
awk -v ip="${KF_NODE_IP}" -v host="${KF_NODE_HOSTNAME}" '$1 == ip { for (i=2; i<=NF; i++) if ($i == host) found=1 } END { exit !found }' /etc/hosts || missing "当前节点 hosts 映射不完整"
printf '[SUCCESS] 当前节点主机名和 hosts 已就绪\n'
