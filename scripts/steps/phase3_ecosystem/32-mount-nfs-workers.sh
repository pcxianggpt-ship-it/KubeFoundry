#!/bin/bash

#===============================================================================
# 脚本名称：32-mount-nfs-workers.sh
# 功能：配置Worker节点挂载NFS（跳过NFS服务器节点本身）
# 执行机器：管理节点（本地执行，通过SSH远程配置Worker节点）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

nfs_server=$(config_get '.storage.nfs_server')
nfs_path=$(config_get '.storage.nfs_path')
nfs_mount_point=$(config_get '.storage.nfs_mount_point')

worker_ips=$(get_all_worker_ips)
if [ -z "$worker_ips" ]; then
    log_info "无Worker节点，跳过NFS挂载"
    return 0
fi

log_info "配置Worker节点挂载NFS..."
while IFS= read -r wip; do
    [ -z "$wip" ] && continue
    if [ "$wip" = "$nfs_server" ]; then
        continue
    fi
    ssh_exec "$wip" "mkdir -p ${nfs_mount_point} && grep -q '${nfs_server}:${nfs_path}' /etc/fstab 2>/dev/null || echo '${nfs_server}:${nfs_path} ${nfs_mount_point} nfs defaults 0 0' >> /etc/fstab; mountpoint -q ${nfs_mount_point} || mount -t nfs ${nfs_server}:${nfs_path} ${nfs_mount_point}"
    if [ $? -ne 0 ]; then
        log_warn "Worker节点(${wip}) NFS挂载失败"
    else
        log_success "Worker节点(${wip}) NFS挂载完成"
    fi
done <<< "$worker_ips"
