#!/bin/bash

#===============================================================================
# 脚本名称：18-init-k8s-cluster.sh
# 功能：初始化K8S集群
# 执行机器：仅在k8sc1（第一个控制节点）上执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始初始化K8S集群..."

# 1. 设置集群初始化文件
cd /data/k8s_install/03.setup_file
vi cluster.yaml
# 修改以下配置：
# - controlPlaneEndpoint: 设置为控制平面地址（如：10.3.66.18:6443）
# - advertiseAddress: 修改为本机IP
# - podSubnet: Pod网络网段
# - serviceSubnet: Service网络网段

# 2. 配置kubelet路径
echo KUBELET_EXTRA_ARGS='--root-dir=/data/kubelet_root' > /etc/sysconfig/kubelet

# 3. 初始化并启动集群
cd /data/k8s_install/03.setup_file
kubeadm init --upload-certs --config cluster.yaml
# 记录输出中的kubeadm join命令，供后续添加节点使用

# 4. 配置kubectl
mkdir -p $HOME/.kube
sudo scp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

# 5. 将kubeadm join命令保存到本地（重要！）
# 从第3步的输出中复制以下命令到本地文件：
# - 控制节点加入命令（包含--control-plane参数）
# - 工作节点加入命令（不包含--control-plane参数）

echo "【INFO】: K8S集群初始化完成"
echo "【INFO】: 请记录kubeadm join命令，用于后续添加节点"

# 验证安装结果
# 在k8sc1控制节点上执行
kubectl get nodes
# 应该看到k8sc1节点，状态为NotReady（正常，需要安装CNI插件）

kubectl get pods -A
# 查看所有命名空间的Pod状态
# coredns可能显示为Pending，需要安装CNI插件后才会正常运行
