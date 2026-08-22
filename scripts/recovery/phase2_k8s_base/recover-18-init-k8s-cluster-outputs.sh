#!/bin/bash

#===============================================================================
# 脚本名称：recover-18-init-k8s-cluster-outputs.sh
# 功能：集群已初始化时受控恢复 Join 任务产物
# 作者：KubeFoundry Team
# 版本：0.3.2
#===============================================================================

set -o errexit -o nounset -o pipefail
umask 077

command -v timeout >/dev/null 2>&1 || { log_error "缺少 timeout，无法安全恢复 Join 产物"; exit 1; }
command -v kubeadm >/dev/null 2>&1 || { log_error "缺少 kubeadm，无法恢复 Join 产物"; exit 1; }
[ -r /etc/kubernetes/admin.conf ] || { log_error "Kubernetes 管理配置不可读"; exit 1; }

worker_join=$(timeout --foreground 60s kubeadm token create --ttl 2h --print-join-command)
if ! [[ "${worker_join}" =~ ^kubeadm[[:space:]]+join[[:space:]]+[^[:space:]]+:[0-9]+[[:space:]]+--token[[:space:]]+[a-z0-9]{6}\.[a-z0-9]{16}[[:space:]]+--discovery-token-ca-cert-hash[[:space:]]+sha256:[0-9a-f]{64} ]]; then
    log_error "kubeadm 生成的 Worker Join 命令格式无效"
    exit 1
fi

certificate_key=$(timeout --foreground 60s kubeadm init phase upload-certs --upload-certs \
    2>/dev/null | tail -1 | tr -d '[:space:]')
if ! [[ "${certificate_key}" =~ ^[0-9a-f]{64}$ ]]; then
    log_error "kubeadm 生成的控制平面证书密钥格式无效"
    exit 1
fi

mkdir -p /tmp/k8s
install -m 0600 /dev/null /tmp/k8s/kube_join_nodes
install -m 0600 /dev/null /tmp/k8s/kube_join_master
printf '%s\n' "${worker_join}" > /tmp/k8s/kube_join_nodes
printf '%s --control-plane --certificate-key %s\n' \
    "${worker_join}" "${certificate_key}" > /tmp/k8s/kube_join_master

log_success "Join 任务产物已受控恢复"
