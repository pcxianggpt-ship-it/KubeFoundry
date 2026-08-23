#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
for tool in swapon sysctl grep; do
    command -v "${tool}" >/dev/null 2>&1 || { printf '[ERROR] 验证工具不可用: %s\n' "${tool}" >&2; exit 20; }
done
[ -z "$(swapon --show --noheadings 2>/dev/null)" ] || missing "swap 仍处于启用状态"
[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = 1 ] || missing "IPv4 转发未启用"
[ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null)" = 1 ] || missing "桥接 iptables 转发未启用"
grep -qw overlay /proc/modules 2>/dev/null || missing "overlay 内核模块未加载"
grep -qw br_netfilter /proc/modules 2>/dev/null || missing "br_netfilter 内核模块未加载"
printf '[SUCCESS] 当前节点 Kubernetes 环境参数已就绪\n'
