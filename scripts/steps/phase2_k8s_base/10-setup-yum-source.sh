#!/bin/bash

#===============================================================================
# 脚本名称：10-setup-yum-source.sh
# 功能：配置本地yum源
# 执行机器：控制平面（主）k8sc1
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

repo_source_name="$1"

# 1. 验证/var/www/html/$1文件是否存在
if [ ! -f "$repo_source_name" ]; then
    echo "【ERROR】: YUM源文件不存在: $repo_source_name"
    exit 1
fi

echo "【INFO】: 找到YUM源文件: $repo_source_name"

mkdir -p /var/www/html/

tar -zxf $repo_source_name -C /var/www/html/

# 2. 添加.repo文件
cat << EOF | tee /etc/yum.repos.d/k8s.repo > /dev/null
[k8s-yum]
name=rhel7
baseurl=file:///var/www/html/repo/
enabled=1
gpgcheck=0
EOF


# 3. 刷新缓存
yum -q clean all
yum -q makecache


# 4. 验证k8s yum源是否存在
echo "【INFO】: 验证k8s yum源..."
if [ $(yum -q search kubelet | wc -l)  -gt "0" ]; then
    echo "【SUCCESS】: 本地yum源已经安装"
    echo "【INFO】: kubelet包搜索结果:"
    yum search kubelet | head -5
else
    log_error "本地yum源安装失败，无法找到kubelet包"
    exit 1
fi


# 5. 安装httpd并开机自启动服务

yum -yq install httpd
systemctl enable httpd --now


# 关闭防火墙
echo "【INFO】: 关闭防火墙服务"
systemctl stop firewalld >/dev/null 2>&1
systemctl disable firewalld >/dev/null 2>&1
