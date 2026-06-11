#!/bin/bash

#===============================================================================
# 脚本名称：38-install-prometheus.sh
# 功能：安装prometheus监控系统
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.1.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"
source "${PROJECT_ROOT}/scripts/lib/ssh.sh"

log_info "开始安装Prometheus监控系统..."

cd "${INSTALL_MEDIA}/03.setup_file/v1.30.14/prometheus"

# 检查目录是否存在
if [ ! -d "${INSTALL_MEDIA}/03.setup_file/v1.30.14/prometheus" ]; then
    log_error "Prometheus 安装目录不存在"
    exit 1
fi

# 获取需要打标签的工作节点（前两个工作节点）
worker_nodes=$(get_all_worker_ips | head -2)

# 给工作节点打标签（用于监控组件调度）
log_info "给工作节点打 prom=true 标签..."
for worker_ip in $worker_nodes; do
    ssh_exec "$worker_ip" "kubectl label node k8sw1 k8sw2 prom=true --overwrite=true 2>/dev/null || true"
done

# 在 prom=true 节点创建数据目录
log_info "在监控节点创建 Prometheus 数据目录..."
for worker_ip in $worker_nodes; do
    ssh_exec "$worker_ip" "mkdir -p /data/prom_data"
done

# 应用本地持久化存储
if [ -f "promlocal-pv.yaml" ]; then
    log_info "应用 Prometheus 本地持久化存储..."
    kubectl apply -f promlocal-pv.yaml
else
    log_warn "promlocal-pv.yaml 不存在，跳过"
fi

# 按顺序安装组件
log_info "安装 Prometheus CRD..."
kubectl apply -f 1-crd

log_info "安装 Prometheus Operator..."
kubectl apply -f 2-prometheusOperator

log_info "安装 Prometheus..."
kubectl apply -f 3-prometheus

if [ -f "additional-scrape-configs.Secret.yaml" ]; then
    log_info "应用 Prometheus 额外抓取配置..."
    kubectl apply -f additional-scrape-configs.Secret.yaml
fi

log_info "安装 Node Exporter..."
kubectl apply -f 4-nodeExporter

log_info "安装 kube-state-metrics..."
kubectl apply -f 5-kubeStateMetrics

log_info "安装 Alertmanager..."
kubectl apply -f 6-alertmanager

if [ -f "8-metrics-server-ha.yaml" ]; then
    log_info "安装 Metrics Server HA..."
    kubectl apply -f 8-metrics-server-ha.yaml
fi

if [ -f "kubernetesControlPlaneRule" ]; then
    log_info "应用 Kubernetes Control Plane 规则..."
    kubectl apply -f kubernetesControlPlaneRule
fi

if [ -f "process-exporter.yaml" ]; then
    log_info "安装 Process Exporter..."
    kubectl apply -f process-exporter.yaml
fi

log_success "Prometheus监控系统安装完成"
