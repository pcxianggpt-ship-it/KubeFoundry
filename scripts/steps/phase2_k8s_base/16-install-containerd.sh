#!/bin/bash

#===============================================================================
# 脚本名称：16-install-containerd.sh
# 功能：安装containerd
# 执行机器：所有节点执行
# 作者：KubeFoundry Team
# 版本：1.1.0
# 环境变量依赖（由 exec_script_on_single_node 注入）：
#   ARCH        - 系统架构（amd64/arm64）
#   REGISTRY_IP - 镜像仓库IP地址
#   CONTAINERD_ROOT - containerd 数据目录
#===============================================================================

# 参数校验
if [[ -z "$ARCH" ]]; then
    log_error "缺少环境变量 ARCH（系统架构）"
    exit 1
fi

if [[ -z "${CONTAINERD_ROOT:-}" ]]; then
    log_error "缺少环境变量 CONTAINERD_ROOT（containerd 数据目录）"
    exit 1
fi

log_info "开始安装containerd（架构: ${ARCH}）..."

# 所有控制节点执行
cd /tmp/k8s/02.container_runtime

# 解压containerd
tar Cxzvf /usr/local containerd-1.7.18-linux-${ARCH}.tar.gz

# 创建containerd自启service
cp containerd.service /etc/systemd/system/containerd.service

# 安装runc
install -m 755 runcv1.3.3.${ARCH} /usr/local/sbin/runc

# 安装cni-plugins
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-${ARCH}-v1.8.0.tgz

# 生成默认配置文件
mkdir -p /etc/containerd
cp config-1.7.18.toml /etc/containerd/config.toml

# 配置 containerd 数据目录，避免使用镜像默认的 /var/lib/containerd。
mkdir -p "${CONTAINERD_ROOT}"
if ! grep -Eq '^[[:space:]]*root[[:space:]]*=' /etc/containerd/config.toml; then
    log_error "containerd 配置模板缺少 root 字段"
    exit 1
fi
if ! sed -i -E "0,/^[[:space:]]*root[[:space:]]*=/s|^[[:space:]]*root[[:space:]]*=.*$|root = \"${CONTAINERD_ROOT}\"|" /etc/containerd/config.toml; then
    log_error "containerd 数据目录配置写入失败"
    exit 1
fi

# 安装buildkit
tar Cxzvf /usr/local buildkit-v0.25.2.linux-${ARCH}.tar.gz

# 创建buildkit自启服务并启动
cp buildkit.s* /etc/systemd/system/
systemctl daemon-reload
systemctl enable buildkit.service --now

# 安装nerdctl
tar -zxf nerdctl-2.2.0-linux-${ARCH}.tar.gz
chmod +x nerdctl
mv nerdctl /usr/local/bin/

# 配置镜像仓库地址（使用IP）
mkdir -p /etc/containerd/certs.d/${REGISTRY_IP}:5000
cat > /etc/containerd/certs.d/${REGISTRY_IP}:5000/hosts.toml <<EOF
server = "http://${REGISTRY_IP}:5000"

[host."http://${REGISTRY_IP}:5000"]
  capabilities = ["pull", "resolve", "push"]
EOF

# 配置镜像仓库地址（使用域名）
mkdir -p /etc/containerd/certs.d/registry:5000
cat > /etc/containerd/certs.d/registry:5000/hosts.toml <<EOF
server = "http://registry:5000"

[host."http://registry:5000"]
  capabilities = ["pull", "resolve", "push"]
EOF

# 启动containerd
systemctl daemon-reload
systemctl enable --now containerd

log_info "containerd安装完成"
log_info "已安装: containerd 1.7.18, runc 1.3.3, cni-plugins 1.8.0, buildkit 0.25.2, nerdctl 2.2.0"
