#!/bin/bash

#===============================================================================
# 脚本名称：19-modify-cert-expiry.sh
# 功能：修改证书有效期为100年
# 执行机器：k8sc1控制节点上执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

MANIFEST="/etc/kubernetes/manifests/kube-controller-manager.yaml"

log_info "开始修改证书有效期..."

# 1. 检查配置文件是否存在
if [ ! -f "$MANIFEST" ]; then
    log_error "kube-controller-manager 配置文件不存在: ${MANIFEST}"
    exit 1
fi

# 2. 检查是否已配置
if grep -q "cluster-signing-duration" "$MANIFEST"; then
    log_success "cluster-signing-duration 参数已存在，跳过"
    exit 0
fi

# 3. 在 spec.containers.command 下添加参数
sed -i '/use-service-account-credentials/a\    - --cluster-signing-duration=867240h0m0s' "$MANIFEST"

# 4. 验证修改结果
if grep -q "cluster-signing-duration" "$MANIFEST"; then
    log_success "已添加证书有效期配置: 867240h0m0s"
else
    log_error "cluster-signing-duration 参数添加失败"
    exit 1
fi

# 5. 等待kube-controller-manager自动重启
log_info "等待kube-controller-manager重启（30秒）..."
sleep 30

# 6. 验证Pod状态
pod_status=$(kubectl get po -n kube-system --no-headers 2>/dev/null | grep 'kube-controller-manager' | awk '{print $3}' | head -1)
if [ "$pod_status" = "Running" ]; then
    log_success "kube-controller-manager 运行正常"
else
    log_error "kube-controller-manager 状态异常: ${pod_status:-Not Found}"
    exit 1
fi
