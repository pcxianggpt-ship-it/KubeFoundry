#!/bin/bash

#===============================================================================
# 脚本名称：12-setup-k8s-repo.sh
# 功能：配置并验证 Kubernetes HTTP YUM 仓库客户端
# 执行机器：除主控制节点外的所有 Kubernetes 节点
# 作者：KubeFoundry Team
# 版本：0.3.2
#===============================================================================

primary_hostname="${PRIMARY_CONTROL_HOSTNAME:-k8sc1}"
repo_config="${KF_YUM_HTTP_REPO_CONFIG:-/etc/yum.repos.d/k8s-http.repo}"
metadata_url="http://${primary_hostname}/repo/repodata/repomd.xml"

fail_step() {
    log_error "$*"
    exit 1
}

command -v curl >/dev/null 2>&1 || fail_step "缺少必需工具: curl"
command -v yum >/dev/null 2>&1 || fail_step "缺少必需工具: yum"
mkdir -p "$(dirname "${repo_config}")" || fail_step "无法创建 YUM Repo 配置目录"

if ! cat > "${repo_config}" <<EOF
# Managed by KubeFoundry v0.3.2
[k8s-repo]
name=KubeFoundry Kubernetes HTTP repository
baseurl=http://${primary_hostname}/repo
enabled=1
gpgcheck=0
EOF
then
    fail_step "无法写入 Kubernetes HTTP Repo 配置"
fi

curl --fail --silent --show-error --max-time 10 --output /dev/null "${metadata_url}" \
    || fail_step "远程访问仓库元数据未返回 HTTP 200: ${metadata_url}"
yum -q clean all || fail_step "YUM 缓存清理失败"
yum -q --disablerepo='*' --enablerepo='k8s-repo' makecache \
    || fail_step "Kubernetes HTTP YUM 仓库缓存创建失败"

log_success "Kubernetes HTTP Repo 配置完成"
