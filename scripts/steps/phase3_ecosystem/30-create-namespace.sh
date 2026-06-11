#!/bin/bash

#===============================================================================
# 脚本名称：30-create-namespace.sh
# 功能：创建命名空间
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "创建kubemate-system命名空间..."

kubectl create ns kubemate-system

log_info "命名空间创建完成"

# 验证安装结果
# 在k8sc1控制节点上执行
kubectl get namespace
# 应该看到 kubemate-system 命名空间
