#!/bin/bash

#===============================================================================
# 脚本名称：21-add-worker-nodes.sh
# 功能：添加K8S工作节点
# 执行机器：所有工作节点（k8sw1-k8sw6）执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始添加K8S工作节点..."

# 使用3.9.1章节中保存的kubeadm join工作节点命令
# 示例（实际命令以k8sc1初始化输出为准）：
kubeadm join k8sc1:6443 --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:abb882fd3462e84cd1c1f9ecf39ca305f6acb8bd8f2ffb72ccf3cba3341df05e

# 如果出现证书错误（x509），在工作节点上执行：
# mkdir -p $HOME/.kube
# sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
# sudo chown $(id -u):$(id -g) $HOME/.kube/config
# export KUBECONFIG=/etc/kubernetes/admin.conf

echo "【INFO】: 工作节点添加完成"

# 验证安装结果
# 在k8sc1控制节点上执行
kubectl get nodes
# 应该看到所有控制节点和工作节点
# 状态为NotReady是正常的，安装CNI插件后会变为Ready
