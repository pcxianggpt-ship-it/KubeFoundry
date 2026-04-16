#!/bin/bash

#===============================================================================
# 脚本名称：14-replace-kubeadm.sh
# 功能：替换kubeadm为支持100年证书版本
# 执行机器：仅在k8sc1上执行
# 作者：KubeFoundry Team
# 版本：1.0.0
# 环境变量依赖（由 exec_script_on_single_node 注入）：
#   INSTALL_MEDIA - 安装介质包根目录
#   K8S_VERSION   - K8S版本
#   ARCH          - 系统架构
#===============================================================================

kubeadm_100y_file="${INSTALL_MEDIA}/01.rpm_package/kubeadm-v${K8S_VERSION}-100y-${ARCH}"

# 1. 检查100年版本kubeadm文件是否存在
if [ ! -f "$kubeadm_100y_file" ]; then
    log_error "100年证书版本kubeadm文件不存在: ${kubeadm_100y_file}"
    exit 1
fi

# 2. 备份原始kubeadm
mkdir -p /tmp/k8s
cp /usr/bin/kubeadm /tmp/k8s/kubeadm_bak
log_info "原始kubeadm已备份到: /tmp/k8s/kubeadm_bak"

# 3. 替换kubeadm
scp "$kubeadm_100y_file" /usr/bin/kubeadm
chmod +x /usr/bin/kubeadm

log_success "kubeadm已替换为支持100年证书版本"
