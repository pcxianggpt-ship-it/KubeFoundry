#!/bin/bash

#===============================================================================
# 脚本名称：31-install-kubemate-ui.sh
# 功能：安装kubemate管理界面（本地执行）
# 执行机器：管理节点
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

log_info "开始安装kubemate管理界面..."

kubectl create cm kubemate-etc -n kubemate-system --from-file=k8s_config.yml=/root/.kube/config

install_media=$(config_resolve '.paths.install_media')
KUBEMATE_FILE="${install_media}/03.setup_file/v1.30.14/kubemate.yml"

# 1. 检查配置文件
if [ ! -f "$KUBEMATE_FILE" ]; then
    log_error "kubemate配置文件不存在: ${KUBEMATE_FILE}"
    exit 1
fi

# 2. 修改hostAliases中的IP为主控节点IP（sed精确替换，不影响其他资源）
primary_cp=$(get_all_control_plane_ips | head -1)
sed -i "s/- ip: .*/- ip: ${primary_cp}/" "$KUBEMATE_FILE"
log_info "已将hostAliases IP修改为: ${primary_cp}"

# 3. 安装kubemate（执行两遍，避免CRD未就绪错误）
kubectl apply -f "$KUBEMATE_FILE"
sleep 5
kubectl apply -f "$KUBEMATE_FILE"

log_success "kubemate管理界面安装完成"
log_info "访问地址: http://${primary_cp}:30088"
