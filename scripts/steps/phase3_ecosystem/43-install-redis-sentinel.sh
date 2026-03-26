#!/bin/bash

#===============================================================================
# 脚本名称：43-install-redis-sentinel.sh
# 功能：安装redis哨兵模式
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始安装Redis哨兵模式..."

cd /data/k8s_install/03.setup_file/allyaml/redis
kubectl create ns redis-sentinel
kubectl apply -f redis-sentinel/redis-pv.yml
kubectl apply -f redis-sentinel/storageclass.yml
helm install -n redis-sentinel redis-ha allyaml/redis-ha

echo "【INFO】: Redis哨兵模式安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get pod -n redis-sentinel
# redis相关Pod状态应为Running
