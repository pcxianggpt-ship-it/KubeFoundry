#!/bin/bash

#===============================================================================
# 脚本名称：40-install-metrics-server.sh
# 功能：安装metrics-server
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始安装Metrics Server..."

sh /data/k8s_install/03.setup_file/mertics-server/mertics-server-install.sh amd64

echo "【INFO】: Metrics Server安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get pod -n kube-system | grep metrics-server
# metrics-server Pod状态应为Running

kubectl top nodes
# 应该能看到各节点的资源使用情况
