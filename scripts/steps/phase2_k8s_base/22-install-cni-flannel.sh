#!/bin/bash

#===============================================================================
# 脚本名称：22-install-cni-flannel.sh
# 功能：安装CNI插件-Flannel（自动适配单栈/双栈网络）
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
# 环境变量依赖（由 exec_script_on_single_node 注入）：
#   INSTALL_MEDIA - 安装介质包根目录
#   POD_SUBNET    - Pod IPv4网段
#   DUAL_STACK    - 是否双栈 (Y/N)
#===============================================================================

log_info "开始安装Flannel CNI插件..."

FLANNEL_FILE="${INSTALL_MEDIA}/03.setup_file/kube-flannel.yml"

# 1. 检查Flannel配置文件是否存在
if [ ! -f "$FLANNEL_FILE" ]; then
    log_error "Flannel配置文件不存在: ${FLANNEL_FILE}"
    exit 1
fi

# 2. 修改net-conf.json中的Network为实际Pod网段
sed -i "s|\"Network\": \".*\"|\"Network\": \"${POD_SUBNET}\"|" "$FLANNEL_FILE"

# 3. 双栈网络：添加IPv6配置
if [ "$DUAL_STACK" = "Y" ]; then
    log_info "双栈网络，添加IPv6配置..."
    # 在Backend行前插入EnableIPv6和IPv6Network
    sed -i '/"Backend":/i\      "EnableIPv6": true,\n      "IPv6Network": "fd10:244::/56",' "$FLANNEL_FILE"
fi

log_info "Flannel网络配置: Network=${POD_SUBNET}"
[ "$DUAL_STACK" = "Y" ] && log_info "Flannel IPv6网络配置: IPv6Network=fd10:244::/56"

# 4. 安装Flannel
kubectl apply -f "$FLANNEL_FILE"
if [ $? -ne 0 ]; then
    log_error "Flannel安装失败"
    exit 1
fi

log_success "Flannel CNI插件安装完成"
