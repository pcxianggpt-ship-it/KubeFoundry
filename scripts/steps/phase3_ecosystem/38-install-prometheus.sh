#!/bin/bash

#===============================================================================
# 脚本名称：38-install-prometheus.sh
# 功能：安装prometheus
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装Prometheus监控系统..."

cd "${INSTALL_MEDIA}/03.setup_file/allyaml/prometheus"
kubectl create -f 1-crd.yml
kubectl apply -f 2-namespace.yml
kubectl apply -f 3-rbac.yml
kubectl apply -f 4-prometheus-operator.yml
kubectl apply -f 5-additional-scrape-configs.yml
kubectl apply -f 6-prometheus.yml
kubectl apply -f 7-alertmanager.yml
kubectl apply -f 8-prometheus-rule.yml
kubectl apply -f node-exporter.yml
kubectl apply -f kube-state-metrics.yml

log_info "Prometheus监控系统安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-monitoring-system
# prometheus相关Pod状态应为Running
