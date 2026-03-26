#!/bin/bash

#===============================================================================
# 脚本名称：37-install-traefik-mesh.sh
# 功能：安装traefik-mesh
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始安装Traefik Mesh服务网格..."

cd /data/k8s_install/03.setup_file/allyaml
kubectl apply -f 5-1.traefik-mesh.yml

echo "【INFO】: Traefik Mesh服务网格安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-system | grep traefik-mesh
# traefik-mesh相关Pod状态应为Running
