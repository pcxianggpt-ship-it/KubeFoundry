#!/bin/bash

#===============================================================================
# 脚本名称：45-setup-traefik-cleanup.sh
# 功能：Traefik清理
# 执行机器：主副中心的k8sc1控制节点执行（root权限）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始配置Traefik定时清理..."

# 获取 K8S 安装目录
K8S_SOFT=$(get_k8s_soft)

crontab -e
# 添加以下内容：
0 2 * * * nohup sh "${K8S_SOFT}/05.crontab/traefikClear.sh" >> "${K8S_SOFT}/05.crontab/traefikClear.log" &

log_info "Traefik定时清理配置完成"

# 验证安装结果
# 查看定时任务
crontab -l
# 应该能看到Traefik清理任务

# 查看清理日志
cat "${K8S_SOFT}/05.crontab/traefikClear.log"
# 应该能看到清理日志
