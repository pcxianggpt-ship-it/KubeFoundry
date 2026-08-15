#!/bin/bash

#===============================================================================
# 脚本名称：47-install-openebs.sh
# 功能：在主控节点幂等安装 OpenEBS
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
resource_dir=$(phase3_resource_path .)
chart_file="${resource_dir}/openebs-4.2.0.tgz"
[ -f "${chart_file}" ] || {
    log_error "OpenEBS Helm Chart 压缩包不存在: ${chart_file}"
    exit 1
}

values_file="${resource_dir}/openebs-values.yaml"
storage_class_file="${resource_dir}/openebssc.yaml"
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

rendered_storage_class=""
openebs_path_values=$(mktemp)
cleanup() {
    [ -z "${rendered_storage_class}" ] || rm -f -- "${rendered_storage_class}"
    rm -f -- "${openebs_path_values}"
}
trap cleanup EXIT

cat > "${openebs_path_values}" <<EOF
localpv-provisioner:
  localpv:
    basePath: "${work_dir}/openebs-root"
  hostpathClass:
    basePath: "${work_dir}/openebs-root"
EOF

if [ -f "${storage_class_file}" ]; then
    grep -q '__KUBERNETES_WORK_DIR__' "${storage_class_file}" || {
        log_error "OpenEBS StorageClass 缺少工作目录占位符: ${storage_class_file}"
        exit 1
    }
    rendered_storage_class=$(mktemp)
    storage_class_content=$(<"${storage_class_file}")
    printf '%s\n' "${storage_class_content//__KUBERNETES_WORK_DIR__/${work_dir}}" \
        > "${rendered_storage_class}"
    phase3_apply_managed "${rendered_storage_class}"
fi
if helm status openebs --namespace kubemate-system >/dev/null 2>&1; then
    log_info "OpenEBS Helm Release 已存在，跳过重复安装"
else
    if [ -f "${values_file}" ]; then
        helm install openebs --namespace kubemate-system "${chart_file}" \
            -f "${values_file}" -f "${openebs_path_values}"
    else
        helm install openebs --namespace kubemate-system "${chart_file}" \
            -f "${openebs_path_values}"
    fi
fi
kubectl get storageclass >/dev/null
deployments=$(kubectl get deployment --namespace kubemate-system --no-headers 2>/dev/null \
    | awk '$1 ~ /openebs/ { print $1 }')
while IFS= read -r name; do
    [ -z "${name}" ] || phase3_wait_rollout deployment "${name}" kubemate-system
done <<< "${deployments}"
log_success "OpenEBS 已幂等安装并通过控制面检查"
