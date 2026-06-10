#!/bin/bash

#===============================================================================
# 脚本名称：36-install-traefik.sh
# 功能：安装traefik网关（3.3版本）
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.1.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装Traefik网关（3.3版本）..."

cd "${INSTALL_MEDIA}/03.setup_file/v1.30.14/traefik"

# 检查 traefik 3.3 目录是否存在
if [ ! -d "3.3" ]; then
    log_error "Traefik 3.3 目录不存在"
    exit 1
fi

# 应用 traefik 3.3 配置
kubectl apply -f 3.3/

if [ $? -eq 0 ]; then
    log_success "Traefik网关（3.3版本）安装完成"
else
    log_error "Traefik网关安装失败"
    exit 1
fi
