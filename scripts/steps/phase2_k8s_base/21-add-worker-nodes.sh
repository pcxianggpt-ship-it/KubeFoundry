#!/bin/bash

#===============================================================================
# 脚本名称：21-add-worker-nodes.sh
# 功能：添加K8S工作节点
# 执行机器：所有工作节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

log_info "开始添加工作节点..."

JOIN_CMD="$1"
if [ -z "$JOIN_CMD" ] && [ -f /tmp/k8s/kube_join_nodes ]; then
    JOIN_CMD=$(cat /tmp/k8s/kube_join_nodes)
fi

if [ -z "$JOIN_CMD" ]; then
    log_error "join命令为空"
    exit 1
fi

log_info "执行join命令..."
eval "$JOIN_CMD"
if [ $? -ne 0 ]; then
    log_error "工作节点join失败"
    exit 1
fi

log_success "工作节点添加完成"
