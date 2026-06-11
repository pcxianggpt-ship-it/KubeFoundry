#!/bin/bash

#===============================================================================
# 脚本名称：40-install-metrics-server.sh
# 功能：安装metrics-server
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装Metrics Server..."

# 获取系统架构
ARCH=$(config_get '.paths.arch' 'amd64')

sh "${INSTALL_MEDIA}/03.setup_file/mertics-server/mertics-server-install.sh" "${ARCH}"

log_info "Metrics Server安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get pod -n kube-system | grep metrics-server
# metrics-server Pod状态应为Running

kubectl top nodes
# 应该能看到各节点的资源使用情况
