#!/bin/bash

#===============================================================================
# 脚本名称：46-setup-log-cleanup.sh
# 功能：应用日志清理
# 执行机器：所有工作节点执行（root权限）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始配置应用日志定时清理..."

crontab -e
# 添加以下内容：
0 2 * * * nohup sh /data/k8s_install/05.crontab/logback.sh >> /data/k8s_install/05.crontab/logback.log &

echo "【INFO】: 应用日志定时清理配置完成"

# 验证安装结果
# 在工作节点上验证

# 查看定时任务
crontab -l
# 应该能看到应用日志清理任务

# 查看清理日志
cat /data/k8s_install/05.crontab/logback.log
# 应该能看到清理日志
