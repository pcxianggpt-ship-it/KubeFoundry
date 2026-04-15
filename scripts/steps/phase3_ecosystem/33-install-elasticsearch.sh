#!/bin/bash

#===============================================================================
# 脚本名称：33-install-elasticsearch.sh
# 功能：安装elasticsearch
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装Elasticsearch..."

# 获取 K8S 安装目录
K8S_SOFT=$(get_k8s_soft)

cd "${K8S_SOFT}/03.setup_file/allyaml"
kubectl apply -f 2.es-crds.yml
kubectl apply -f 2.es-operator.yml
kubectl apply -f 2.es-skywalking.yml

log_info "Elasticsearch安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get po -A | grep es-skywalking
# es-skywalking相关Pod状态应为Running
