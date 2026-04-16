#!/bin/bash

#===============================================================================
# 脚本名称：32-install-nfs.sh
# 功能：安装NFS插件（安装nfs包、安装helm、helm部署nfs provisioner）
# 执行机器：所有控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
# 环境变量依赖（由 exec_script_on_single_node 注入）：
#   INSTALL_MEDIA   - 安装介质包根目录
#   NFS_SERVER      - NFS服务器IP
#   NFS_PATH        - NFS共享路径
#   NFS_MOUNT_POINT - NFS本地挂载点
#   STORAGE_CLASS   - StorageClass名称
#   REGISTRY_HOSTNAME - 镜像仓库主机名
#   ARCH            - 系统架构
#===============================================================================

log_info "开始安装NFS插件..."

# 1. 参数校验
if [ -z "$NFS_SERVER" ] || [ -z "$NFS_PATH" ]; then
    log_error "NFS配置缺失，请检查config.yaml中的storage配置"
    exit 1
fi

log_info "NFS配置: 服务器=${NFS_SERVER}, 路径=${NFS_PATH}, 挂载点=${NFS_MOUNT_POINT:-/data/nfs_root}"


# 3. 启动nfs-server
systemctl enable nfs-server >/dev/null 2>&1
systemctl start nfs-server >/dev/null 2>&1
log_success "nfs-server 已启动"

# 4. 配置NFS挂载（仅非NFS服务器节点）
local_ip=$(hostname -I | awk '{print $1}')
if [ "$local_ip" != "$NFS_SERVER" ] && [ -n "$NFS_MOUNT_POINT" ]; then
    mkdir -p "$NFS_MOUNT_POINT"
    # 添加fstab自动挂载（避免重复添加）
    if ! grep -q "$NFS_PATH" /etc/fstab 2>/dev/null; then
        echo "${NFS_SERVER}:${NFS_PATH} ${NFS_MOUNT_POINT} nfs defaults 0 0" >> /etc/fstab
    fi
    mount -t nfs "${NFS_SERVER}:${NFS_PATH}" "$NFS_MOUNT_POINT" 2>/dev/null
    log_success "NFS挂载配置完成: ${NFS_MOUNT_POINT}"
fi


# 6. 使用helm安装NFS provisioner
HELM_CHART_DIR="${INSTALL_MEDIA}/03.setup_file/allyaml/nfs-subdir-external-provisioner"
if [ ! -d "$HELM_CHART_DIR" ]; then
    log_error "helm chart目录不存在: ${HELM_CHART_DIR}"
    exit 1
fi

# 检查是否已安装
if helm list 2>/dev/null | grep -q nfs-subdir-external-provisioner; then
    log_info "nfs-subdir-external-provisioner 已安装，跳过"
else
    helm install nfs-subdir-external-provisioner "$HELM_CHART_DIR" \
        --set image.repository="${REGISTRY_HOSTNAME}:5000/nfs/nfs-subdir-external-provisioner" \
        --set image.tag="v4.0.2" \
        --set nfs.server="$NFS_SERVER" \
        --set nfs.path="$NFS_PATH" \
        --set storageClass.name="$STORAGE_CLASS" \
        --set storageClass.defaultClass=true

    if [ $? -ne 0 ]; then
        log_error "NFS provisioner helm安装失败"
        exit 1
    fi
    log_success "NFS provisioner helm安装成功"
fi

log_success "NFS插件安装完成"
