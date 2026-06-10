#!/bin/bash

#===============================================================================
# 脚本名称：48-install-alloy.sh
# 功能：安装Grafana Alloy可观测性代理
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装Grafana Alloy可观测性代理..."

# 检查helm是否安装
if ! command -v helm &> /dev/null; then
    log_error "helm 未安装，请先安装 helm"
    exit 1
fi

cd "${INSTALL_MEDIA}/03.setup_file/v1.30.14/helmapp/alloy"

# 检查 helm chart 和 values 文件是否存在
if [ ! -f "alloy-1.4.0.tgz" ]; then
    log_error "Alloy helm chart 不存在: alloy-1.4.0.tgz"
    exit 1
fi

if [ ! -f "alloy-values.yaml" ]; then
    log_error "Alloy values.yaml 不存在"
    exit 1
fi

if [ ! -f "alloy.config" ]; then
    log_error "Alloy 配置文件 alloy.config 不存在"
    exit 1
fi

# 1. 创建 ConfigMap（从配置文件）
log_info "创建 Alloy ConfigMap..."
kubectl create cm -n kubemate-system --from-file=congfig.alloy=alloy.config --dry-run=client -o yaml | kubectl apply -f -

if [ $? -ne 0 ]; then
    log_warn "ConfigMap 创建可能失败，继续安装..."
fi

# 2. 安装 Alloy
log_info "安装 Alloy Helm Chart..."
helm install alloy -n kubemate-system -f alloy-values.yaml ./alloy-1.4.0.tgz

if [ $? -eq 0 ]; then
    log_success "Grafana Alloy可观测性代理安装完成"
else
    log_error "Grafana Alloy可观测性代理安装失败"
    exit 1
fi
