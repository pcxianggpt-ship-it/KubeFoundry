#!/bin/bash

#===============================================================================
# 脚本名称：14-replace-kubeadm.sh
# 功能：替换kubeadm为支持100年证书版本
# 执行机器：仅在k8sc1上执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 确保临时目录存在
mkdir -p /tmp/k8s

# 备份原始kubeadm
cp /usr/bin/kubeadm /tmp/k8s/kubeadm_bak
kubeadm_100y_file="$data_path/01.rpm_package/kubeadm-$k8s_version-100y-$arch_type"
scp "$kubeadm_100y_file" /usr/bin/kubeadm

echo "【INFO】: kubeadm已替换为支持100年证书版本"
echo "【INFO】: 原始kubeadm已备份到: /tmp/k8s/kubeadm_bak"
