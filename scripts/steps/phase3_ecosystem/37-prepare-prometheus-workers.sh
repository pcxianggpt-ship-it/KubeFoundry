#!/bin/bash

#===============================================================================
# 脚本名称：37-prepare-prometheus-workers.sh
# 功能：在当前 Worker 准备 Prometheus 规范化数据目录
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
prom_data_dir="${KF_K8S_HOME}/prom_data"
mkdir -p -- "${prom_data_dir}"
log_success "当前 Worker Prometheus 数据目录已准备: ${prom_data_dir}"
