#!/bin/bash

#===============================================================================
# 脚本名称：46-prepare-storage-workers.sh
# 功能：在当前 Worker 准备受管存储数据目录
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
for directory in /data/openebs-root /data/minio-root /data/loki-root; do
    mkdir -p -- "${directory}"
done
log_success "当前 Worker 存储目录已准备"
