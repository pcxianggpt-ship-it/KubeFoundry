#!/bin/bash

#===============================================================================
# 脚本名称：32-install-nfs.sh
# 功能：安装NFS插件
# 执行机器：所有节点
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装NFS插件..."

# 获取 K8S 安装目录
K8S_SOFT=$(get_k8s_soft)

# 1. 验证系统是否自带nfs
systemctl status nfs-server

# 2. 如果不存在nfs-server，安装nfs（所有控制节点执行）
cd "${K8S_SOFT}/01.rpm_package/nfs"
rpm -ivh *.rpm

# 3. 启动nfs-server（所有控制节点执行）
systemctl enable nfs-server && systemctl start nfs-server

# 4. 验证NAS挂载（一般已由系统岗挂载好）
# mount -t nfs 10.3.5.221:/kvmdata/nfsdata/xdnfs /data/nas_root

# 5. 修改nfs配置（仅在k8sc1控制节点执行）
cd "${K8S_SOFT}/03.setup_file/allyaml"
vi nfs-value.yaml
# 修改为NAS server提供的IP和访问路径

# 6. 配置开机自动挂载（所有控制节点执行）
vi /etc/fstab
# 添加：10.3.5.221:/kvmdata/nfsdata/xdnfs /data/nas_root nfs defaults 0 0

# 7. 安装helm（仅在k8sc1控制节点执行）
cp "${K8S_SOFT}/03.setup_file/allyaml/linux-amd64/helm" /usr/local/bin/helm

# 8. 安装nfs provisioner（仅在k8sc1控制节点执行）
cd "${K8S_SOFT}/03.setup_file/allyaml"
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/ -f nfs-value.yaml

log_info "NFS插件安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

# 1. 检查nfs provisioner Pod状态
kubectl get pod
# Pod状态应为Running

# 2. 验证NAS挂载
df -h | grep nas_root
# 应该看到挂载的NFS存储
