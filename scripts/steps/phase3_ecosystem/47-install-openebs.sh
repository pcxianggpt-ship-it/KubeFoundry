#!/bin/bash

#===============================================================================
# 脚本名称：47-install-openebs.sh
# 功能：安装OpenEBS存储系统
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"
source "${PROJECT_ROOT}/scripts/lib/ssh.sh"

log_info "开始安装OpenEBS存储系统..."

# 检查helm是否安装
if ! command -v helm &> /dev/null; then
    log_error "helm 未安装，请先安装 helm"
    exit 1
fi

# 获取所有控制节点
control_nodes=$(get_all_control_plane_ips)

# 1. 在所有控制节点创建存储目录
log_info "在所有控制节点创建 OpenEBS 存储目录..."
for cp_ip in $control_nodes; do
    ssh_exec "$cp_ip" "mkdir -p /data/openebs-root"
    if [ $? -eq 0 ]; then
        log_success "节点 $cp_ip 目录创建成功"
    else
        log_error "节点 $cp_ip 目录创建失败"
        exit 1
    fi
done

cd "${INSTALL_MEDIA}/03.setup_file/v1.30.14/helmapp/openebs"

# 检查 helm chart 和 values 文件是否存在
if [ ! -f "openebs-4.2.0.tgz" ]; then
    log_error "OpenEBS helm chart 不存在: openebs-4.2.0.tgz"
    exit 1
fi

if [ ! -f "openebs-values.yaml" ]; then
    log_error "OpenEBS values.yaml 不存在"
    exit 1
fi

# 2. 应用 StorageClass
if [ -f "openebssc.yaml" ]; then
    log_info "应用 OpenEBS StorageClass..."
    kubectl apply -f openebssc.yaml
else
    log_warn "openebssc.yaml 不存在，跳过"
fi

# 3. 安装 OpenEBS
log_info "安装 OpenEBS Helm Chart..."
helm install openebs -n kubemate-system -f openebs-values.yaml ./openebs-4.2.0.tgz

if [ $? -eq 0 ]; then
    log_success "OpenEBS存储系统安装完成"
else
    log_error "OpenEBS存储系统安装失败"
    exit 1
fi
