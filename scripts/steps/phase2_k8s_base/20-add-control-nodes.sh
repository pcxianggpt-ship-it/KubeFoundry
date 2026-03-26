#!/bin/bash

#===============================================================================
# 脚本名称：20-add-control-nodes.sh
# 功能：添加K8S控制节点
# 执行机器：k8sc2和k8sc3节点执行（一台执行完后再执行另一台）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始添加K8S控制节点..."
echo "【说明】: 搭建高可用时执行，单master节点部署可跳过该步骤"

# 使用3.9.1章节中保存的kubeadm join控制节点命令
# 示例（实际命令以k8sc1初始化输出为准）：
kubeadm join k8sc1:6443 --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:be3037375048669762a18c0d820994613d4611c768f524fca5d808ca3caf47da \
  --control-plane --certificate-key 8cc3bc5f73f00cfb37c77413a73c87513dad3142ab3c5052a124387efc8b8742

# 配置kubectl
mkdir -p $HOME/.kube
sudo scp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "【INFO】: 控制节点添加完成"
