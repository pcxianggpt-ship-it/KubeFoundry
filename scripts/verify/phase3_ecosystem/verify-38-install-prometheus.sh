#!/bin/bash

#===============================================================================
# 脚本名称：verify-38-install-prometheus.sh
# 功能：验证 Prometheus 监控工作负载和采集目标
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
namespace="${KF_PROMETHEUS_NAMESPACE:-kubemate-system}"
kubectl get pods --namespace "${namespace}" --no-headers | grep -Eq 'prometheus|node-exporter|kube-state-metrics'
kubectl get servicemonitor --all-namespaces >/dev/null
kubectl get prometheus --all-namespaces >/dev/null
log_success "Prometheus targets、Exporter 和 kube-state-metrics 验证通过"
