#!/bin/bash

#===============================================================================
# 脚本名称：35-install-loki.sh
# 功能：安装loki日志系统
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.1.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装Loki日志系统..."

# 检查helm是否安装
if ! command -v helm &> /dev/null; then
    log_error "helm 未安装，请先安装 helm"
    exit 1
fi

cd "${INSTALL_MEDIA}/03.setup_file/v1.30.14/helmapp/loki"

# 检查 helm chart 和 values 文件是否存在
if [ ! -f "loki-5.45.0.tgz" ]; then
    log_error "loki helm chart 不存在: loki-5.45.0.tgz"
    exit 1
fi

if [ ! -f "values.yaml" ]; then
    log_error "loki values.yaml 不存在"
    exit 1
fi

# 安装 Loki
helm install loki -n kubemate-system -f values.yaml ./loki-5.45.0.tgz

if [ $? -eq 0 ]; then
    log_success "Loki日志系统安装完成"
else
    log_error "Loki日志系统安装失败"
    exit 1
fi

# 工作节点需要执行以下命令（如使用本地磁盘存储）：
# mkdir -p /data/loki_root
# chown -R 10001:10001 /data/loki_root
