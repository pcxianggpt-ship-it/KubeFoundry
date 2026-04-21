#!/bin/bash

#===============================================================================
# 脚本名称：32-configure-nfs-exports.sh
# 功能：判断NFS服务器是否在集群内，如果是则远程配置其/etc/exports文件
# 执行机器：管理节点（本地执行，通过SSH远程配置目标节点）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

log_info "检查NFS服务器是否在集群内..."

nfs_server=$(config_get '.storage.nfs_server')
nfs_path=$(config_get '.storage.nfs_path')

all_node_ips=$(get_all_node_ips)
if echo "$all_node_ips" | grep -qF "$nfs_server"; then
    log_info "NFS服务器(${nfs_server})在集群内，远程配置/etc/exports..."
    export_entry="${nfs_path} *(rw,sync,no_subtree_check,no_root_squash)"
    ssh_exec "$nfs_server" "mkdir -p ${nfs_path} && grep -qF '${nfs_path}' /etc/exports 2>/dev/null || (echo '${export_entry}' >> /etc/exports && exportfs -ra)"
    if [ $? -ne 0 ]; then
        log_error "远程配置NFS服务器/etc/exports失败"
        return 1
    fi
    log_success "NFS服务器(${nfs_server}) /etc/exports配置完成"
else
    log_info "NFS服务器(${nfs_server})不在集群内，跳过/etc/exports配置"
fi

# 重启nfs-server
systemctl restart nfs-server