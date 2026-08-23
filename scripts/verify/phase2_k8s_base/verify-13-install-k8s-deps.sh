#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
for tool in kubeadm kubectl kubelet crictl; do
    command -v "${tool}" >/dev/null 2>&1 || missing "Kubernetes 依赖未安装: ${tool}"
done
command -v systemctl >/dev/null 2>&1 || { printf '[ERROR] 验证工具不可用: systemctl\n' >&2; exit 20; }
systemctl is-enabled --quiet kubelet || missing "kubelet 未设为开机启动"
printf '[SUCCESS] Kubernetes 依赖已安装\n'
