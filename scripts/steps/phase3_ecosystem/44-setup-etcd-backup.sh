#!/bin/bash

#===============================================================================
# 脚本名称：44-setup-etcd-backup.sh
# 功能：ETCD备份
# 执行机器：主副中心的k8sc1控制节点执行（root权限）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由任务执行器 export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始配置ETCD定时备份..."

crontab -e
# 添加以下内容：
10 2 * * * nohup sh "${INSTALL_MEDIA}/05.crontab/etcdbak.sh" 1 >> /data/crontab_task/etcdbak/etcdbak.log &

# 注意：etcdbak.sh后面的参数：1代表主中心，2代表副中心

log_info "ETCD定时备份配置完成"

# 验证安装结果
# 查看定时任务
crontab -l
# 应该能看到ETCD备份任务

# 查看备份日志
ls -lh /data/crontab_task/etcdbak/
# 应该能看到备份日志文件
