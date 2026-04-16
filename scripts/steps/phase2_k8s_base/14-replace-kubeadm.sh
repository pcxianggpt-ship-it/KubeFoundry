#!/bin/bash

#===============================================================================
# 脚本名称：14-replace-kubeadm.sh
# 功能：替换kubeadm为支持100年证书版本
# 执行机器：仅在k8sc1上执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

install_media=$(config_resolve '.paths.install_media')
k8s_version=$(get_k8s_version)
arch=$(config_resolve '.paths.arch')
kubeadm_100y_file="${install_media}/01.rpm_package/kubeadm-v${k8s_version}-100y-${arch}"

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
cp "$kubeadm_100y_file" /usr/bin/kubeadm
chmod +x /usr/bin/kubeadm

log_success "kubeadm已替换为支持100年证书版本"
