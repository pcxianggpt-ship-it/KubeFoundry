#!/bin/bash

#===============================================================================
# 脚本名称：15-environment-config.sh
# 功能：环境配置
# 执行机器：所有节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始环境配置..."

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

# 5. 配置DNS
sed -i '/nameserver/d' /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# 6. 转发ipv4 ipv6并让iptables看到桥接流量
cat << EOF | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 7. 修改sysctl.conf
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
sed -i '/net.bridge.bridge-nf-call-iptables/d' /etc/sysctl.conf
sed -i '/net.bridge.bridge-nf-call-ip6tables/d' /etc/sysctl.conf
echo net.bridge.bridge-nf-call-iptables=1 >> /etc/sysctl.conf
echo net.bridge.bridge-nf-call-ip6tables=1 >> /etc/sysctl.conf
echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf

# 8. 配置IPv6
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

# 9. 应用sysctl配置
sysctl --system > /dev/null

# 10. 启用systemd-resolved
systemctl enable systemd-resolved > /dev/null 2>&1

# 11. 修改open files参数
cat >> /etc/security/limits.conf << EOF
* soft nofile 65535
* hard nofile 65535
EOF

echo "【INFO】: 环境配置完成"
echo "【INFO】: 已配置: swap关闭, 防火墙关闭, DNS配置, IPv4/IPv6转发, open files参数"
