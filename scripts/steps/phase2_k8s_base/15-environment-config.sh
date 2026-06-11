#!/bin/bash

#===============================================================================
# 脚本名称：15-environment-config.sh
# 功能：环境配置
# 执行机器：所有节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

log_info "开始环境配置..."

# 所有控制节点执行

# 1. 设置参数

# 2. 关闭swap
swapoff -a
sed -i '/swap/d' /etc/fstab

# 3. 关闭防火墙
systemctl stop firewalld > /dev/null 2>&1
systemctl disable firewalld > /dev/null 2>&1

# 4. 卸载podman等容器
yum remove podman -y > /dev/null 2>&1
yum remove containerd -y > /dev/null 2>&1

# 5. 彻底删除Docker
if command -v docker &> /dev/null || rpm -qa | grep -q docker; then
    log_info "检测到Docker，开始彻底删除..."
    # 停止docker服务
    systemctl stop docker > /dev/null 2>&1 || true
    systemctl stop docker.socket > /dev/null 2>&1 || true
    # 卸载docker相关软件包
    yum remove docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine -y > /dev/null 2>&1 || true
    # 删除docker相关目录和文件
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    rm -rf /etc/docker
    rm -rf /var/run/docker*
    rm -rf /var/log/docker*
    log_info "Docker已彻底删除"
else
    log_info "未检测到Docker，跳过"
fi

# 6. 配置DNS
sed -i '/nameserver/d' /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# 7. 转发ipv4 ipv6并让iptables看到桥接流量
cat << EOF | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 8. 修改sysctl.conf
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
sed -i '/net.bridge.bridge-nf-call-iptables/d' /etc/sysctl.conf
sed -i '/net.bridge.bridge-nf-call-ip6tables/d' /etc/sysctl.conf
echo net.bridge.bridge-nf-call-iptables=1 >> /etc/sysctl.conf
echo net.bridge.bridge-nf-call-ip6tables=1 >> /etc/sysctl.conf
echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf

# 9. 配置IPv6
sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.all.forwarding/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.default.forwarding/d' /etc/sysctl.conf
echo net.ipv6.conf.all.disable_ipv6=0 >> /etc/sysctl.conf
echo net.ipv6.conf.default.disable_ipv6=0 >> /etc/sysctl.conf
echo net.ipv6.conf.lo.disable_ipv6=0 >> /etc/sysctl.conf
echo net.ipv6.conf.all.forwarding=1 >> /etc/sysctl.conf
echo net.ipv6.conf.default.forwarding=1 >> /etc/sysctl.conf

# 10. 配置inotify参数到/etc/sysctl.d/99-sysctl.conf
sed -i '/fs.inotify.max_queued_events/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/fs.inotify.max_user_instances/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/fs.inotify.max_user_watches/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/user.max_inotify_instances/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/user.max_inotify_watches/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
cat >> /etc/sysctl.d/99-sysctl.conf << EOF
fs.inotify.max_queued_events = 16384
fs.inotify.max_user_instances = 51200
fs.inotify.max_user_watches = 2621440
user.max_inotify_instances = 51200
user.max_inotify_watches = 2621440
EOF

# 11. 应用sysctl配置
sysctl --system > /dev/null

# 12. 启用systemd-resolved
systemctl enable systemd-resolved > /dev/null 2>&1

# 13. 修改open files参数
cat >> /etc/security/limits.conf << EOF
* soft nofile 65535
* hard nofile 65535
EOF

log_info "环境配置完成"
log_info "已配置: swap关闭, 防火墙关闭, Docker删除, DNS配置, IPv4/IPv6转发, inotify参数, open files参数"
