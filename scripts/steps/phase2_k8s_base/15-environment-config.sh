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

# 11. 配置内核与网络优化参数
sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.netfilter.nf_conntrack_max/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.netfilter.nf_conntrack_tcp_timeout_established/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.netfilter.nf_conntrack_tcp_timeout_time_wait/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.core.somaxconn/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.core.rmem_max/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.core.wmem_max/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.core.default_qdisc/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_slow_start_after_idle/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_keepalive_time/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_keepalive_intvl/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_keepalive_probes/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp_timestamps/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/vm.swappiness/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/vm.min_free_kbytes/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/fs.file-max/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
sed -i '/vm.max_map_count/d' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
cat >> /etc/sysctl.d/99-sysctl.conf << EOF
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 131072
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 8388608 16777216
net.ipv4.tcp_wmem = 4096 8388608 16777216
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_timestamps = 1
vm.swappiness = 10
vm.min_free_kbytes = 524288
fs.file-max = 2097152
vm.max_map_count = 262144
EOF

# 12. 应用sysctl配置
sysctl --system > /dev/null

# 13. 启用systemd-resolved
systemctl enable systemd-resolved > /dev/null 2>&1
systemctl restart systemd-resolved > /dev/null 2>&1

# 14. 修改open files参数
cat >> /etc/security/limits.conf << EOF
* soft nofile 65535
* hard nofile 65535
EOF

log_info "环境配置完成"
log_info "已配置: swap关闭, 防火墙关闭, Docker删除, DNS配置, IPv4/IPv6转发, inotify参数, 内核与网络优化参数, open files参数"
