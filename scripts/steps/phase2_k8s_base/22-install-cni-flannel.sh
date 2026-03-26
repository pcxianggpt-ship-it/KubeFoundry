#!/bin/bash

#===============================================================================
# 脚本名称：22-install-cni-flannel.sh
# 功能：安装CNI插件-Flannel
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始安装Flannel CNI插件..."

# 1. 查看kube-flannel.yml中的网络配置
cd /data/k8s_install/03.setup_file
vi kube-flannel.yml
# 确认网络配置与cluster.yaml中的网段一致

# 2. 安装Flannel
kubectl apply -f /data/k8s_install/03.setup_file/kube-flannel.yml

echo "【INFO】: Flannel CNI插件安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

# 验证节点状态
kubectl get nodes
# 所有节点的状态应为Ready

# 验证Pod状态
kubectl get pods -A
# 所有Pod（包括coredns）的状态应为Running或Completed
# kube-flannel-ds Pods应在每个节点上运行

# 故障排查：
# 如果Pod没有正常运行（READY显示为0/1），查看详细信息
# kubectl describe pod kube-flannel-ds-xxxx -n kube-flannel
# 查看Events和Logs部分的错误信息
