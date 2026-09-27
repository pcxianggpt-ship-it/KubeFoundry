#!/bin/bash

#===============================================================================
# 脚本名称：15-environment-config.sh
# 功能：使用 KubeFoundry 独立配置文件准备 Kubernetes 节点环境
# 执行机器：所有节点执行
# 作者：KubeFoundry Team
# 版本：1.1.0
#===============================================================================

set -o errexit -o nounset -o pipefail
source ./managed_config.sh

log_info "开始环境配置..."

for managed_file in \
    /etc/systemd/system/kubefoundry-disable-swap.service \
    /etc/modules-load.d/kubefoundry-k8s.conf \
    /etc/sysctl.d/99-kubefoundry-k8s.conf \
    /etc/security/limits.d/99-kubefoundry.conf; do
    kf_require_owned_or_absent "${managed_file}" || {
        log_error "配置文件已存在且不属于 KubeFoundry: ${managed_file}"
        exit 1
    }
done

# 当前安装立即关闭 swap，并通过独立 unit 确保重启后仍关闭。
swapoff -a
cat > /etc/systemd/system/kubefoundry-disable-swap.service <<'EOF'
# Managed by KubeFoundry v0.3.2
[Unit]
Description=Disable swap for Kubernetes nodes managed by KubeFoundry
Before=kubelet.service

[Service]
Type=oneshot
ExecStart=/sbin/swapoff -a
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# firewalld 必须直接关闭。
systemctl stop firewalld >/dev/null 2>&1 || true
systemctl disable firewalld >/dev/null 2>&1 || true

# 移除与离线 containerd 产物冲突的 RPM，不删除用户 Docker 配置或数据。
yum remove podman containerd -y >/dev/null 2>&1 || true

cat > /etc/modules-load.d/kubefoundry-k8s.conf <<'EOF'
# Managed by KubeFoundry v0.3.2
overlay
br_netfilter
EOF
chmod 0644 /etc/modules-load.d/kubefoundry-k8s.conf
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-kubefoundry-k8s.conf <<'EOF'
# Managed by KubeFoundry v0.3.2
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
fs.inotify.max_queued_events = 16384
fs.inotify.max_user_instances = 51200
fs.inotify.max_user_watches = 2621440
user.max_inotify_instances = 51200
user.max_inotify_watches = 2621440
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
chmod 0644 /etc/sysctl.d/99-kubefoundry-k8s.conf
# procps 最后加载 /etc/sysctl.conf；通过可撤销标记块覆盖旧值，保留用户配置。
sysctl_block=$(mktemp)
trap 'rm -f -- "${sysctl_block}"' EXIT
printf '%s\n' 'net.ipv4.ip_forward = 1' \
    'net.bridge.bridge-nf-call-iptables = 1' \
    'net.bridge.bridge-nf-call-ip6tables = 1' > "${sysctl_block}"
kf_replace_managed_block /etc/sysctl.conf \
    '# >>>KubeFoundry sysctl>>>' '# <<<KubeFoundry sysctl<<<' "${sysctl_block}" || {
    log_error "无法更新 /etc/sysctl.conf 受管标记块，请检查文件类型和标记完整性"
    exit 1
}
if ! sysctl --system; then
    log_error "加载 sysctl 配置失败，请检查上方错误"
    exit 1
fi
for sysctl_key in net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables; do
    if ! sysctl_value=$(sysctl -n "${sysctl_key}"); then
        log_error "读取内核参数失败: ${sysctl_key}"
        exit 1
    fi
    if [ "${sysctl_value}" != 1 ]; then
        log_error "内核参数未生效: ${sysctl_key}=${sysctl_value}，期望 1"
        exit 1
    fi
done

cat > /etc/security/limits.d/99-kubefoundry.conf <<'EOF'
# Managed by KubeFoundry v0.3.2
* soft nofile 65535
* hard nofile 65535
EOF
chmod 0644 /etc/security/limits.d/99-kubefoundry.conf

systemctl daemon-reload
systemctl enable --now kubefoundry-disable-swap.service >/dev/null

log_success "环境配置完成"
log_info "已配置: swap 关闭、防火墙关闭、KubeFoundry 独立 modules/sysctl/limits 配置"
