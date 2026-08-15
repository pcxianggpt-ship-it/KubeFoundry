#!/bin/bash

#===============================================================================
# 脚本名称：46-prepare-storage-workers.sh
# 功能：在当前 Worker 准备受管存储数据目录
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
work_dir="${KF_K8S_HOME:?缺少 Kubernetes 工作目录}"
case "${work_dir}" in
    /*) ;;
    *) log_error "Kubernetes 工作目录必须是绝对路径: ${work_dir}"; exit 1 ;;
esac
case "${work_dir}" in
    /|*..*|*$'\n'*|*$'\r'*)
        log_error "Kubernetes 工作目录不安全: ${work_dir}"
        exit 1
        ;;
esac
[[ "${work_dir}" =~ ^/[A-Za-z0-9._/-]+$ ]] || {
    log_error "Kubernetes 工作目录包含不支持的字符: ${work_dir}"
    exit 1
}
work_dir="${work_dir%/}"

for directory in \
    "${work_dir}/openebs-root" \
    "${work_dir}/minio-root" \
    "${work_dir}/loki-root"; do
    mkdir -p -- "${directory}"
done
log_success "当前 Worker 存储目录已在 Kubernetes 工作目录下准备完成: ${work_dir}"
