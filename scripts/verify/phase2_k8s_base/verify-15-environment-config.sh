#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
for tool in swapon sysctl grep; do
    command -v "${tool}" >/dev/null 2>&1 || { printf '[ERROR] 验证工具不可用: %s\n' "${tool}" >&2; exit 20; }
done
for managed_file in \
    /etc/modules-load.d/kubefoundry-k8s.conf \
    /etc/sysctl.d/99-kubefoundry-k8s.conf \
    /etc/security/limits.d/99-kubefoundry.conf \
    /etc/systemd/system/kubefoundry-disable-swap.service; do
    [ -f "${managed_file}" ] || missing "KubeFoundry 受管配置不存在: ${managed_file}"
    grep -Fqx '# Managed by KubeFoundry v0.3.2' "${managed_file}" || \
        missing "KubeFoundry 受管标记缺失: ${managed_file}"
done
[ -z "$(swapon --show --noheadings 2>/dev/null)" ] || missing "swap 仍处于启用状态"
for sysctl_key in net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables; do
    if ! sysctl_value=$(sysctl -n "${sysctl_key}"); then
        printf '[ERROR] 读取内核参数失败: %s\n' "${sysctl_key}" >&2
        exit 20
    fi
    [ "${sysctl_value}" = 1 ] || missing "内核参数未生效: ${sysctl_key}=${sysctl_value}，期望 1"
done

grep -qw overlay /proc/modules 2>/dev/null || missing "overlay 内核模块未加载"
grep -qw br_netfilter /proc/modules 2>/dev/null || missing "br_netfilter 内核模块未加载"
printf '[SUCCESS] 当前节点 Kubernetes 环境参数已就绪\n'
