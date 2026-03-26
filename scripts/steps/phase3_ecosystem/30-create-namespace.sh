#!/bin/bash

#===============================================================================
# 脚本名称：30-create-namespace.sh
# 功能：创建命名空间
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 创建kubemate-system命名空间..."

kubectl apply -f /data/k8s_install/03.setup_file/allyaml/0.kubemate-namespace.yaml

echo "【INFO】: 命名空间创建完成"

# 验证安装结果
# 在k8sc1控制节点上执行
kubectl get namespace
# 应该看到 kubemate-system 命名空间
