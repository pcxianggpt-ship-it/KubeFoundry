#!/bin/bash

#===============================================================================
# 脚本名称：17-install-registry.sh
# 功能：安装镜像仓库
# 执行机器：镜像仓库执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

REGISTRY_IP="${1:-10.3.66.20}"

log_info "开始安装镜像仓库，IP地址: $REGISTRY_IP"

# 获取 K8S 安装目录
K8S_SOFT=$(get_k8s_soft)

# 2. 安装镜像仓库
sh "${K8S_SOFT}/04.registry/registry_install.sh" "$REGISTRY_IP"
# 参数说明：第一个参数为镜像仓库的IP地址

log_info "镜像仓库安装完成"
