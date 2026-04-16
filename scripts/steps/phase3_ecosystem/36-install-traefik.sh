#!/bin/bash

#===============================================================================
# 脚本名称：36-install-traefik.sh
# 功能：安装traefik
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装Traefik网关..."

cd "${INSTALL_MEDIA}/03.setup_file/allyaml"
kubectl apply -f 5.traefki-ds.yaml
kubectl apply -f 5.traefki-ds.yaml
kubectl apply -f 6.logfmt-manage.yml

log_info "Traefik网关安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-system | grep traefik
# traefik相关Pod状态应为Running
