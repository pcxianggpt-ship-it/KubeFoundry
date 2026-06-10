#!/bin/bash

#===============================================================================
# 脚本名称：49-install-minio.sh
# 功能：安装MinIO对象存储系统
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装MinIO对象存储系统..."

cd "${INSTALL_MEDIA}/03.setup_file/v1.30.14/helmapp/minio"

# 检查 minio-operator.yaml 是否存在
if [ ! -f "minio-operator.yaml" ]; then
    log_error "minio-operator.yaml 不存在"
    exit 1
fi

# 1. 安装 MinIO Operator
log_info "安装 MinIO Operator..."
# 注意：需要先修改 minio-operator.yaml 中的 image 字段为实际镜像地址
kubectl apply -f minio-operator.yaml

if [ $? -eq 0 ]; then
    log_success "MinIO Operator 安装完成"

    # 2. 获取 Operator Token（用于控制台登录）
    log_info "等待 MinIO Console 就绪..."
    sleep 10

    log_info "获取 MinIO Console Token..."
    token=$(kubectl get secret -n kubemate-system console-sa-secret -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

    if [ -n "$token" ]; then
        log_info "================================================"
        log_info "MinIO Console Token: ${token}"
        log_info "================================================"
        log_info "请使用浏览器访问 MinIO Console 创建存储实例"
        log_info "默认访问地址: http://<k8sc1_ip>:<minio_console_port>"
        log_info "================================================"
    else
        log_warn "未能获取 Token，Secret 可能还未就绪"
        log_info "稍后可使用以下命令获取："
        log_info "kubectl get secret -n kubemate-system console-sa-secret -o jsonpath='{.data.token}' | base64 -d"
    fi

    log_success "MinIO对象存储系统安装完成"
else
    log_error "MinIO Operator 安装失败"
    exit 1
fi
