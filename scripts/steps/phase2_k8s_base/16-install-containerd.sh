#!/bin/bash

#===============================================================================
# 脚本名称：16-install-containerd.sh
# 功能：安装containerd
# 执行机器：所有节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始安装containerd..."

# 所有控制节点执行
cd /tmp/k8s/02.container_runtime

# 解压containerd-1.7.18-linux-amd64.tar.gz
tar Cxzvf /usr/local containerd-1.7.18-linux-amd64.tar.gz

# 创建containerd自启service
cp containerd.service /etc/systemd/system/containerd.service

# 安装runc
install -m 755 runcv1.3.3.amd64 /usr/local/sbin/runc

# 安装cni-plugins
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.8.0.tgz

# 生成默认配置文件
mkdir -p /etc/containerd
cp config-1.7.18.toml /etc/containerd/config.toml

# 安装buildkit
tar Cxzvf /usr/local buildkit-v0.25.2.linux-amd64.tar.gz

# 创建buildkit自启服务并启动
cp buildkit.s* /etc/systemd/system/
systemctl daemon-reload
systemctl enable buildkit.service --now

# 安装nerdctl
tar -zxf nerdctl-2.2.0-linux-amd64.tar.gz
chmod +x nerdctl
mv nerdctl /usr/local/bin/

# 配置镜像仓库地址（使用变量）
mkdir -p /etc/containerd/certs.d/\$registry:5000
cat > /etc/containerd/certs.d/\$registry:5000/hosts.toml <<EOF
server = "http://\$registry:5000"

[host."http://\$registry:5000"]
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

echo "【INFO】: containerd安装完成"
echo "【INFO】: 已安装: containerd 1.7.18, runc 1.3.3, cni-plugins 1.8.0, buildkit 0.25.2, nerdctl 2.2.0"
