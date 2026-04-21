#!/bin/bash

#===============================================================================
# 脚本名称：12-setup-k8s-repo.sh
# 功能：配置本地k8s repo源客户端
# 执行机器：除k8sc1外，所有服务器执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

cat <<EOF | tee /etc/yum.repos.d/k8s-http.repo > /dev/null
[k8s-repo]
name=http
baseurl=http://k8sc1/repo
enabled=1
gpgcheck=0
EOF

yum -q clean all
yum -q makecache

log_info "k8s HTTP repo源配置完成"
