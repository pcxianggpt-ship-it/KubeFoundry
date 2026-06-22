#!/bin/bash

#===============================================================================
# 脚本名称：18-init-k8s-cluster.sh
# 功能：初始化K8S集群（自动生成cluster.yaml，支持单栈/双栈）
# 执行机器：仅在k8sc1（第一个控制节点）上执行
# 作者：KubeFoundry Team
# 版本：1.0.0
# 环境变量依赖（由 exec_script_on_single_node 注入）：
#   K8S_VERSION       - K8S版本
#   KUBELET_ROOT      - kubelet数据目录
#   ETCD_DATA_DIR     - etcd数据目录
#   POD_SUBNET        - Pod网段
#   SERVICE_SUBNET    - Service网段
#   DUAL_STACK        - 是否双栈 (Y/N)
#   REGISTRY_HOSTNAME - 镜像仓库主机名
#===============================================================================

log_info "开始初始化K8S集群..."

# 1. 参数校验
if [ -z "$K8S_VERSION" ]; then
    log_error "缺少环境变量 K8S_VERSION"
    exit 1
fi

# 2. 获取本机IPv4地址
ipv4=$(hostname -I | awk '{print $1}')
if [ -z "$ipv4" ]; then
    log_error "无法获取本机IPv4地址"
    exit 1
fi
log_info "本机IPv4地址: ${ipv4}"

# 3. 双栈网络IPv6地址
if [ "$DUAL_STACK" = "Y" ]; then
    ipv6=$(ip -6 addr show scope global | grep -v 'fd00:42::171' | head -2 | awk '/inet6/ {print $2}' | cut -d'/' -f1)
    if [ -z "$ipv6" ]; then
        log_error "启用双栈但无法获取本机IPv6地址"
        exit 1
    fi
    log_info "本机IPv6地址: ${ipv6}"
else
    ipv6=""
fi

# 4. 显示配置信息
log_info "配置信息："
log_info "  K8S版本: ${K8S_VERSION}"
log_info "  双栈网络: ${DUAL_STACK}"
log_info "  IPv4地址: ${ipv4}"
log_info "  Pod网段: ${POD_SUBNET}"
log_info "  Service网段: ${SERVICE_SUBNET}"
log_info "  Kubelet目录: ${KUBELET_ROOT}"
log_info "  Etcd目录: ${ETCD_DATA_DIR}"
log_info "  镜像仓库: ${REGISTRY_HOSTNAME}:5000/registry.k8s.io"

# 5. 配置kubelet数据目录
mkdir -p /tmp/k8s
echo "KUBELET_EXTRA_ARGS='--root-dir=${KUBELET_ROOT}'" > /etc/sysconfig/kubelet
log_success "kubelet数据目录已配置: ${KUBELET_ROOT}"

# 6. 生成cluster.yaml
local_hostname=$(hostname)

if [ "$DUAL_STACK" = "Y" ]; then
cat << EOF | tee /tmp/k8s/cluster.yaml > /dev/null
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
bootstrapTokens:
- token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
  groups:
  - system:bootstrappers:kubeadm:default-node-token
localAPIEndpoint:
  advertiseAddress: "${ipv4}"
  bindPort: 6443
nodeRegistration:
  imagePullPolicy: IfNotPresent
  taints: null
  kubeletExtraArgs:
    node-ip: "${ipv4},${ipv6}"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: ${K8S_VERSION}
clusterName: kubernetes
certificatesDir: /etc/kubernetes/pki
controlPlaneEndpoint: "${local_hostname}:6443"
imageRepository: ${REGISTRY_HOSTNAME}:5000/registry.k8s.io
networking:
  podSubnet: "${POD_SUBNET},fd10:244::/56"
  serviceSubnet: "${SERVICE_SUBNET},fd10:96::/112"
  dnsDomain: cluster.local
apiServer:
  timeoutForControlPlane: 4m0s
controllerManager:
  extraArgs:
    cluster-cidr: "${POD_SUBNET},fd10:244::/56"
    node-cidr-mask-size-ipv4: "24"
    node-cidr-mask-size-ipv6: "64"
scheduler: {}
dns: {}
etcd:
  local:
    dataDir: ${ETCD_DATA_DIR}
EOF
else
cat << EOF | tee /tmp/k8s/cluster.yaml > /dev/null
apiVersion: kubeadm.k8s.io/v1beta3
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "${ipv4}"
  bindPort: 6443
nodeRegistration:
  imagePullPolicy: IfNotPresent
  taints: null
---
apiServer:
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta3
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns: {}
etcd:
  local:
    dataDir: ${ETCD_DATA_DIR}
imageRepository: ${REGISTRY_HOSTNAME}:5000/registry.k8s.io
kind: ClusterConfiguration
kubernetesVersion: ${K8S_VERSION}
controlPlaneEndpoint: "${local_hostname}:6443"
networking:
  dnsDomain: cluster.local
  podSubnet: ${POD_SUBNET}
  serviceSubnet: ${SERVICE_SUBNET}
scheduler: {}
EOF
fi

# 检查配置文件是否生成成功
if [ ! -f /tmp/k8s/cluster.yaml ]; then
    log_error "集群配置文件生成失败"
    exit 1
fi
log_success "cluster.yaml 已生成"

# 7. 初始化集群
log_info "开始初始化Kubernetes集群..."
kubeadm init --upload-certs --config /tmp/k8s/cluster.yaml > /tmp/k8s/k8s-init-cluster.log 2>&1

if [ $? -ne 0 ]; then
    log_error "集群初始化失败，最近20行日志："
    tail -20 /tmp/k8s/k8s-init-cluster.log
    exit 1
fi

# 8. 配置kubectl
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf
log_success "kubectl 已配置"

# 9. 生成 kubeadm join 命令
worker_join_cmd=$(kubeadm token create --print-join-command)
if [ -z "$worker_join_cmd" ]; then
    log_error "工作节点 join 命令生成失败"
    exit 1
fi

certificate_key=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1 | tr -d '[:space:]')
if [ -z "$certificate_key" ]; then
    log_error "控制节点 certificate key 生成失败"
    exit 1
fi

printf '%s\n' "$worker_join_cmd" > /tmp/k8s/kube_join_nodes
printf '%s --control-plane --certificate-key %s\n' "$worker_join_cmd" "$certificate_key" > /tmp/k8s/kube_join_master

log_success "kubeadm join 命令已保存"
log_info "  控制节点: /tmp/k8s/kube_join_master"
log_info "  工作节点: /tmp/k8s/kube_join_nodes"

# 10. 等待Pod启动
log_info "等待系统Pod启动（60秒）..."
sleep 60

# 11. 检查关键系统Pod状态
log_info "检查系统Pod状态..."

critical_pod_count=0
critical_fail_count=0
for component in kube-controller-manager kube-apiserver kube-scheduler etcd; do
    pod_status=$(kubectl get po -n kube-system --no-headers 2>/dev/null | grep "$component" | awk '{print $3}' | head -1)
    critical_pod_count=$((critical_pod_count + 1))
    if [ "$pod_status" = "Running" ]; then
        log_success "${component} 启动成功"
    else
        log_error "${component} 启动失败 (状态: ${pod_status:-Not Found})"
        critical_fail_count=$((critical_fail_count + 1))
    fi
done

# 检查 kube-proxy
proxy_status=$(kubectl get po -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq)
if [ "$proxy_status" = "Running" ]; then
    log_success "kube-proxy 启动成功"
else
    log_error "kube-proxy 启动失败 (状态: ${proxy_status:-Not Found})"
    critical_fail_count=$((critical_fail_count + 1))
fi

if [ "$critical_fail_count" -gt 0 ]; then
    log_error "关键系统Pod未全部运行，请检查集群状态"
    kubectl get po -n kube-system
    exit 1
fi

log_success "K8S集群初始化完成"
log_info "集群访问信息："
log_info "  配置文件: /etc/kubernetes/admin.conf"
log_info "  用户配置: $HOME/.kube/config"
log_info "  查看节点: kubectl get nodes"
log_info "  查看Pod: kubectl get po -A"
