#!/bin/bash

#===============================================================================
# 脚本名称：31-install-kubemate-ui.sh
# 功能：安装kubemate管理界面
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装kubemate管理界面..."

# 1. 修改配置文件
cd "${INSTALL_MEDIA}/03.setup_file/allyaml"
vi 1.kubemate.yml
# 修改第730行，改为k8sc1的IP地址（如：10.3.66.18）

# 2. 安装kubemate（执行两遍，如果出现no matches错误）
kubectl apply -f 1.kubemate.yml
kubectl apply -f 1.kubemate.yml

log_info "kubemate管理界面安装完成"

# 验证安装结果
# 1. 检查Pod状态
kubectl get pods -n kubemate-system
# 所有Pod状态应为Running

# 2. 访问Web界面
# 浏览器访问：http://10.3.66.18:30088
# 默认用户名密码：admin / 000000als
