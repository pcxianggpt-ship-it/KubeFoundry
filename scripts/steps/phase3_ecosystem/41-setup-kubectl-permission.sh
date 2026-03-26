#!/bin/bash

#===============================================================================
# 脚本名称：41-setup-kubectl-permission.sh
# 功能：配置普通用户kubectl权限
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始配置普通用户kubectl权限..."

cp -r .kube /home/appusr/
chown -R appusr:appusr /home/appusr/.kube/

echo "【INFO】: 普通用户kubectl权限配置完成"

# 验证安装结果
# 切换到普通用户验证
su - appusr
kubectl get nodes
# 应该能正常列出节点信息
