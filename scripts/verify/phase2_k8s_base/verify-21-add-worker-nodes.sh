#!/bin/bash

set -o nounset -o pipefail

[ -s /etc/kubernetes/kubelet.conf ] || { printf '[INFO] 当前 Worker 尚未加入集群\n'; exit 10; }
[ -s /var/lib/kubelet/kubeadm-flags.env ] || { printf '[INFO] Worker kubeadm 参数不完整\n'; exit 10; }
command -v systemctl >/dev/null 2>&1 || { printf '[ERROR] 验证工具不可用: systemctl\n' >&2; exit 20; }
systemctl is-active --quiet kubelet || { printf '[INFO] kubelet 未运行\n'; exit 10; }
printf '[SUCCESS] 当前 Worker 已加入集群\n'
