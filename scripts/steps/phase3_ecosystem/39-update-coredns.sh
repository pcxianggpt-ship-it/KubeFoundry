#!/bin/bash

#===============================================================================
# 脚本名称：39-update-coredns.sh
# 功能：更新coredns配置
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由任务执行器 export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始更新CoreDNS配置..."

# 1. 执行更新脚本
cd "${INSTALL_MEDIA}/03.setup_file/allyaml"
kubectl apply -f coredns-update.yml
kubectl rollout restart -n kube-system deployment coredns
sleep 5
kubectl rollout restart deployment/traefik-mesh-controller -n kubemate-system

# 2. 编辑coredns配置
kubectl edit deployment coredns -n kube-system
# 在第40行，spec.template.spec下添加以下内容（注意格式对齐）：

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 1
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: k8s-app
            operator: In
            values:
            - kube-dns
        topologyKey: kubernetes.io/hostname

log_info "CoreDNS配置更新完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get pod -n kube-system | grep coredns
# coredns Pod状态应为Running，且分布在不同的节点上
