#!/bin/bash

set -o nounset -o pipefail

[ -x /usr/bin/kubeadm ] || { printf '[INFO] 受管 kubeadm 不可执行\n'; exit 10; }
[ -s /tmp/k8s/kubeadm_bak ] || { printf '[INFO] kubeadm 原始备份不存在\n'; exit 10; }
timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" /usr/bin/kubeadm version -o short >/dev/null 2>&1
status=$?
case "${status}" in
    0) printf '[SUCCESS] 长证书 kubeadm 已就绪\n' ;;
    124|137) printf '[ERROR] 验证命令超时\n' >&2; exit 21 ;;
    *) printf '[ERROR] kubeadm 版本查询失败\n' >&2; exit 20 ;;
esac
