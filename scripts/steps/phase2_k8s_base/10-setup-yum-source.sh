#!/bin/bash

#===============================================================================
# 脚本名称：10-setup-yum-source.sh
# 功能：配置本地 Kubernetes YUM HTTP 仓库
# 执行机器：主控制节点
# 作者：KubeFoundry Team
# 版本：0.3.2
#===============================================================================

repo_source_name="${1:-}"
web_root="${KF_YUM_WEB_ROOT:-/var/www/html}"
repo_root="${web_root}/repo"
metadata_file="${repo_root}/repodata/repomd.xml"
repo_config="${KF_YUM_LOCAL_REPO_CONFIG:-/etc/yum.repos.d/k8s.repo}"
metadata_url="${KF_YUM_LOCAL_METADATA_URL:-http://127.0.0.1/repo/repodata/repomd.xml}"

if [ ! -f "${repo_source_name}" ]; then
    log_error "YUM 源文件不存在: ${repo_source_name}"
    exit 1
fi

mkdir -p "${web_root}" "$(dirname "${repo_config}")" || exit 1
tar -zxf "${repo_source_name}" -C "${web_root}" || exit 1
if [ ! -f "${metadata_file}" ]; then
    log_error "仓库元数据不存在: ${metadata_file}"
    exit 1
fi

cat > "${repo_config}" <<EOF
# Managed by KubeFoundry v0.3.2
[k8s-yum]
name=KubeFoundry Kubernetes local repository
baseurl=file://${repo_root}/
enabled=1
gpgcheck=0
EOF
[ $? -eq 0 ] || exit 1

yum -q clean all || exit 1
yum -q --disablerepo='*' --enablerepo='k8s-yum' makecache || exit 1
yum -yq --disablerepo='*' --enablerepo='k8s-yum' install httpd || exit 1

# httpd RPM 可能重设 /var/www/html 权限，因此必须在安装软件后再开放仓库路径。
chmod 777 "$(dirname "${web_root}")" "${web_root}" || exit 1
chmod -R 777 "${repo_root}" || exit 1

systemctl enable httpd --now || exit 1

# 集群安装环境要求直接关闭并禁用 firewalld。
systemctl stop firewalld >/dev/null 2>&1 || true
systemctl disable firewalld >/dev/null 2>&1 || true
if systemctl is-active --quiet firewalld; then
    log_error "firewalld 关闭失败"
    exit 1
fi
if systemctl is-enabled --quiet firewalld; then
    log_error "firewalld 禁用失败"
    exit 1
fi

curl --fail --silent --show-error --max-time 10 --output /dev/null "${metadata_url}" || exit 1
log_success "Kubernetes YUM HTTP 仓库配置完成"
