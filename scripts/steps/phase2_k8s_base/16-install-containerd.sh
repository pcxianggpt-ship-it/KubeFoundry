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

set -o errexit -o nounset -o pipefail
source ./managed_config.sh

# 参数校验
if [[ -z "${ARCH:-}" ]]; then
    log_error "缺少环境变量 ARCH（系统架构）"
    exit 1
fi

if [[ -z "${REGISTRY_IP:-}" ]]; then
    log_error "缺少环境变量 REGISTRY_IP（镜像仓库 IP）"
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

# 创建 containerd 自启 service，首次替换前保留受保护基线。
kf_install_replacement containerd.service /etc/systemd/system/containerd.service \
    containerd.service 0644 || { log_error "containerd service 存在未受管变更"; exit 1; }

# 安装runc
install -m 755 runcv1.3.3.${ARCH} /usr/local/sbin/runc

# 安装cni-plugins
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-${ARCH}-v1.8.0.tgz

# 生成默认配置文件
mkdir -p /etc/containerd
containerd_config="$(mktemp)"
trap 'rm -f "${containerd_config}"' EXIT
cp config-1.7.18.toml "${containerd_config}"

# 配置 containerd 数据目录，避免使用镜像默认的 /var/lib/containerd。
mkdir -p "${CONTAINERD_ROOT}"
if ! grep -Eq '^[[:space:]]*root[[:space:]]*=' "${containerd_config}"; then
    log_error "containerd 配置模板缺少 root 字段"
    exit 1
fi
if ! sed -i -E "0,/^[[:space:]]*root[[:space:]]*=/s|^[[:space:]]*root[[:space:]]*=.*$|root = \"${CONTAINERD_ROOT}\"|" "${containerd_config}"; then
    log_error "containerd 数据目录配置写入失败"
    exit 1
fi
kf_install_replacement "${containerd_config}" /etc/containerd/config.toml \
    containerd.config 0644 || { log_error "containerd 配置存在未受管变更"; exit 1; }

# 安装buildkit
tar Cxzvf /usr/local buildkit-v0.25.2.linux-${ARCH}.tar.gz

# 创建 buildkit 自启服务并启动
for buildkit_unit in buildkit.service buildkit.socket; do
    [ -f "${buildkit_unit}" ] || continue
    kf_install_replacement "${buildkit_unit}" "/etc/systemd/system/${buildkit_unit}" \
        "${buildkit_unit}" 0644 || { log_error "${buildkit_unit} 存在未受管变更"; exit 1; }
done
systemctl daemon-reload
systemctl enable buildkit.service --now

# 安装nerdctl
tar -zxf nerdctl-2.2.0-linux-${ARCH}.tar.gz
chmod +x nerdctl
mv nerdctl /usr/local/bin/

write_registry_hosts() {
    local target="$1" server="$2" temporary
    if [ -e "${target}" ] && ! grep -Fqx '# Managed by KubeFoundry v0.3.2' "${target}"; then
        log_error "Registry 配置已存在且不属于 KubeFoundry: ${target}"
        return 1
    fi
    temporary="${target}.tmp.$$"
    cat > "${temporary}" <<EOF
# Managed by KubeFoundry v0.3.2
server = "http://${server}"

[host."http://${server}"]
  capabilities = ["pull", "resolve", "push"]
EOF
    chmod 0644 "${temporary}"
    mv -f "${temporary}" "${target}"
}

# 配置镜像仓库地址（使用 IP）
mkdir -p "/etc/containerd/certs.d/${REGISTRY_IP}:5000"
write_registry_hosts "/etc/containerd/certs.d/${REGISTRY_IP}:5000/hosts.toml" "${REGISTRY_IP}:5000"

# 配置镜像仓库地址（使用域名）
mkdir -p /etc/containerd/certs.d/registry:5000
write_registry_hosts /etc/containerd/certs.d/registry:5000/hosts.toml registry:5000

# 启动containerd
systemctl daemon-reload
systemctl enable --now containerd

log_info "containerd安装完成"
log_info "已安装: containerd 1.7.18, runc 1.3.3, cni-plugins 1.8.0, buildkit 0.25.2, nerdctl 2.2.0"
