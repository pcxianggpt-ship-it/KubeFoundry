#!/bin/bash

#===============================================================================
# 脚本名称：38-install-prometheus.sh
# 功能：安装prometheus
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始安装Prometheus监控系统..."

cd /data/k8s_install/03.setup_file/allyaml/prometheus
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

echo "【INFO】: Prometheus监控系统安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-monitoring-system
# prometheus相关Pod状态应为Running
