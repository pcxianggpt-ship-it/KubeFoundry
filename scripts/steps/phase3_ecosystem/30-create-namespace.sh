#!/bin/bash

#===============================================================================
# 脚本名称：30-create-namespace.sh
# 功能：创建命名空间
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：0.3.1
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init

log_info "创建kubemate-system命名空间..."

phase3_ensure_namespace kubemate-system

log_info "命名空间创建完成"

kubectl get namespace kubemate-system >/dev/null
log_success "kubemate-system 命名空间已就绪"
