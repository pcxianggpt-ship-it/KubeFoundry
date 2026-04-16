#!/bin/bash

#===============================================================================
# 脚本名称：20-add-control-nodes.sh
# 功能：添加K8S控制节点（非主控制节点执行kubeadm join）
# 执行机器：所有控制节点（主控制节点自动跳过）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 参数1: 主控制节点IP（由exec_script注入）
PRIMARY_CP_IP="$1"

# 获取本机IP
LOCAL_IP=$(hostname -I | awk '{print $1}')

# 如果是主控制节点，跳过
if [ "$LOCAL_IP" = "$PRIMARY_CP_IP" ]; then
    log_info "当前节点(${LOCAL_IP})为主控制节点，跳过join"
    exit 0
fi

log_info "开始添加控制节点 ${LOCAL_IP}..."

# 检查join命令文件
JOIN_FILE="/tmp/k8s/kube_join_master"
if [ ! -f "$JOIN_FILE" ]; then
    log_error "join命令文件不存在: ${JOIN_FILE}"
    exit 1
fi

# 读取并执行join命令
JOIN_CMD=$(cat "$JOIN_FILE")
if [ -z "$JOIN_CMD" ]; then
    log_error "join命令为空: ${JOIN_FILE}"
    exit 1
fi

log_info "执行join命令..."
eval "$JOIN_CMD"
if [ $? -ne 0 ]; then
    log_error "控制节点join失败: ${LOCAL_IP}"
    exit 1
fi

# 配置kubectl
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

log_success "控制节点 ${LOCAL_IP} 添加完成"
