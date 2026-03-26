#!/bin/bash

#===============================================================================
# 脚本名称：13-install-k8s-deps.sh
# 功能：安装K8s依赖包
# 执行机器：所有控制平面和所有工作节点安装
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

yum install -y cri-tools kubeadm kubectl kubelet kubernetes-cni nfs

echo "【INFO】: K8s依赖包安装完成"
echo "【INFO】: 已安装: cri-tools, kubeadm, kubectl, kubelet, kubernetes-cni, nfs"
