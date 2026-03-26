#!/bin/bash

#===============================================================================
# 脚本名称：33-install-elasticsearch.sh
# 功能：安装elasticsearch
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始安装Elasticsearch..."

cd /data/k8s_install/03.setup_file/allyaml
kubectl apply -f 2.es-crds.yml
kubectl apply -f 2.es-operator.yml
kubectl apply -f 2.es-skywalking.yml

echo "【INFO】: Elasticsearch安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get po -A | grep es-skywalking
# es-skywalking相关Pod状态应为Running
