#!/bin/bash

#===============================================================================
# 脚本名称：30-create-namespace.sh
# 功能：创建命名空间
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "创建kubemate-system命名空间..."

# 获取 K8S 安装目录
K8S_SOFT=$(get_k8s_soft)

kubectl apply -f "${K8S_SOFT}/03.setup_file/allyaml/0.kubemate-namespace.yaml"

log_info "命名空间创建完成"

# 验证安装结果
# 在k8sc1控制节点上执行
kubectl get namespace
# 应该看到 kubemate-system 命名空间
