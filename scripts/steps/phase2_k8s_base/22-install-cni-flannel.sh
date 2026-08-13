#!/bin/bash

#===============================================================================
# 脚本名称：22-install-cni-flannel.sh
# 功能：安装CNI插件-Flannel（自动适配单栈/双栈网络）
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
# 环境变量依赖（由 exec_script_on_single_node 注入）：
#   INSTALL_MEDIA - 安装介质包根目录
#   DUAL_STACK    - 是否双栈 (Y/N)
#===============================================================================

readonly POD_SUBNET="10.244.0.0/16"

log_info "开始安装Flannel CNI插件..."

FLANNEL_FILE="${FLANNEL_FILE:-/tmp/k8s/kube-flannel.yml}"

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

if ! kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=180s; then
    log_error "Flannel DaemonSet 未在 180 秒内就绪"
    exit 1
fi

# Registry 使用 nerdctl 时会创建自己的 10.4.0.0/24 CNI 网桥。若 CoreDNS
# 在 Flannel 就绪前启动，可能错误获得 10.4.0.x 地址，导致跨节点 Pod 无法
# 访问集群 DNS。Flannel 就绪后发现异常地址时，滚动重建 CoreDNS。
coredns_ips=$(kubectl get pods -n kube-system -l k8s-app=kube-dns \
    -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}')
coredns_needs_restart=false
while IFS= read -r pod_ip; do
    [ -z "${pod_ip}" ] && continue
    case "${pod_ip}" in
        10.244.*) ;;
        *) coredns_needs_restart=true ;;
    esac
done <<< "${coredns_ips}"

if [ "${coredns_needs_restart}" = true ]; then
    log_warn "检测到 CoreDNS Pod 地址不属于 Flannel 网段，正在滚动重建: ${coredns_ips//$'\n'/,}"
    kubectl rollout restart deployment/coredns -n kube-system
fi
if ! kubectl rollout status deployment/coredns -n kube-system --timeout=180s; then
    log_error "CoreDNS 未在 Flannel 网络中就绪"
    exit 1
fi

log_success "Flannel CNI插件和 CoreDNS 网络已就绪"
