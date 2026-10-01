#!/bin/bash

#===============================================================================
# 脚本名称：38-install-prometheus.sh
# 功能：在主控制节点按介质目录顺序安装 Prometheus 监控组件
# 版本：0.3.1
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init

resource_dir=$(phase3_resource_path .)
prom_data_dir="${KF_K8S_HOME}/prom_data"

required_resources=(
    "promlocal-pv.yaml"
    "1-crd"
    "2-prometheusOperator"
    "3-prometheus"
    "4-nodeExporter"
    "5-kubeStateMetrics"
    "6-alertmanager"
    "7-kubernetesControlPlaneRule"
    "8-metrics-server-ha.yaml"
)

for resource in "${required_resources[@]}"; do
    [ -e "${resource_dir}/${resource}" ] || {
        log_error "Prometheus 安装资源不存在: ${resource_dir}/${resource}"
        exit 1
    }
done

mapfile -t worker_nodes < <(kubectl get nodes \
    -l '!node-role.kubernetes.io/control-plane,!node-role.kubernetes.io/master' \
    -o name)
[ "${#worker_nodes[@]}" -gt 0 ] || {
    log_error "未找到可用于部署 Prometheus 的工作节点"
    exit 1
}

kubectl label "${worker_nodes[@]}" kubefoundry.io/prometheus=true --overwrite=true

rendered_pv=$(mktemp)
trap 'rm -f -- "${rendered_pv}"' EXIT
sed -e "s|/data/prom_data|${prom_data_dir}|g" \
    -e 's|key: prom$|key: kubefoundry.io/prometheus|' \
    "${resource_dir}/promlocal-pv.yaml" > "${rendered_pv}"

phase3_apply_managed "${rendered_pv}"
phase3_apply_managed "${resource_dir}/1-crd"
phase3_apply_managed "${resource_dir}/2-prometheusOperator"
phase3_apply_managed "${resource_dir}/3-prometheus"
phase3_apply_managed "${resource_dir}/4-nodeExporter"
phase3_apply_managed "${resource_dir}/5-kubeStateMetrics"
phase3_apply_managed "${resource_dir}/6-alertmanager"
# Kubernetes 1.30 的 kubectl 不支持 wait --for=create，轮询 Operator 创建的 Service。
alertmanager_service_ready=false
for ((attempt = 0; attempt < 30; attempt++)); do
    if kubectl get service alertmanager-operated --namespace kubemate-system >/dev/null 2>&1; then
        alertmanager_service_ready=true
        break
    fi
    sleep 2
done
[ "${alertmanager_service_ready}" = true ] || {
    log_error "Alertmanager 无头 Service 未创建"
    exit 1
}
kubectl patch service alertmanager-operated --namespace kubemate-system \
    --type=merge -p '{"spec":{"publishNotReadyAddresses":true}}' >/dev/null || {
    log_error "Alertmanager 无头 Service 就绪地址配置失败"
    exit 1
}
phase3_apply_managed "${resource_dir}/7-kubernetesControlPlaneRule"
phase3_apply_managed "${resource_dir}/8-metrics-server-ha.yaml"

log_success "Prometheus 监控组件安装命令执行完成"
