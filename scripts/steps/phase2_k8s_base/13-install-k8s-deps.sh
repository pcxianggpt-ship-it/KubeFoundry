#!/bin/bash

#===============================================================================
# 脚本名称：13-install-k8s-deps.sh
# 功能：安装K8s依赖包
# 执行机器：所有控制平面和所有工作节点安装
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

PACKAGES="cri-tools kubeadm kubectl kubelet kubernetes-cni nfs-utils"

log_info "开始安装K8s依赖包..."

FAIL_LIST=""
for pkg in $PACKAGES; do
    if yum install -y "$pkg" >/dev/null 2>&1; then
        log_success "${pkg} 安装成功"
    else
        log_error "${pkg} 安装失败，请检查yum源是否包含该包"
        FAIL_LIST="${FAIL_LIST} ${pkg}"
    fi
done

if [ -n "$FAIL_LIST" ]; then
    log_error "以下包安装失败:${FAIL_LIST}"
    log_error "请执行 'yum search <包名>' 确认包名是否正确"
    exit 1
fi

log_success "K8s依赖包安装完成"
log_info "已安装: ${PACKAGES}"
