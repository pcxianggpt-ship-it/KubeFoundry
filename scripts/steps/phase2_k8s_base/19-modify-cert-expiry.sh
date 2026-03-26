#!/bin/bash

#===============================================================================
# 脚本名称：19-modify-cert-expiry.sh
# 功能：修改证书有效期
# 执行机器：k8sc1控制节点上执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始修改证书有效期..."

# 在k8sc1控制节点上执行
vi /etc/kubernetes/manifests/kube-controller-manager.yaml
# 在 spec.containers.command 下面最后一行添加：
# - --cluster-signing-duration=867240h0m0s
# 保存并退出，kube-controller-manager会自动重启

echo "【INFO】: 证书有效期已修改为100年（867240小时）"

# 验证安装结果
# 在k8sc1控制节点上执行
kubeadm certs check-expiration
# 查看证书有效期，应该显示为100年（或配置的时长）
