#!/bin/bash

#===============================================================================
# 脚本名称：35-install-loki.sh
# 功能：安装loki
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装Loki日志系统..."

cd "${INSTALL_MEDIA}/03.setup_file/allyaml"
kubectl apply -f 4.loki.yml
kubectl apply -f 4.loki-sec.yml

log_info "Loki日志系统安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-system | grep loki
# loki相关Pod状态应为Running

# 工作节点需要执行以下命令：
# 如果使用本地磁盘存储loki数据，所有工作节点执行
# mkdir -p /data/loki_root
# chown -R 10001:10001 /data/loki_root
