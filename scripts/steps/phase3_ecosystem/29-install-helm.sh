#!/bin/bash

#===============================================================================
# 脚本名称：29-install-helm.sh
# 功能：在主控制节点离线安装 KubeFoundry 受管 Helm
# 作者：KubeFoundry Team
# 版本：0.3.0
#===============================================================================

set -o errexit -o nounset -o pipefail

: "${KF_COMPONENT_RESOURCE_DIR:?缺少任务组件资源目录}"
: "${KF_HELM_SHA256:?缺少 Helm SHA-256 校验和}"

helm_source="${KF_COMPONENT_RESOURCE_DIR}/helm"
marker_dir="/usr/local/lib/kubefoundry"
marker_file="${marker_dir}/helm.sha256"

if [ ! -f "${helm_source}" ]; then
    log_error "Helm 离线介质不存在: ${helm_source}"
    exit 1
fi

actual_checksum="$(sha256sum "${helm_source}" | awk '{print $1}')"
if [ "${actual_checksum}" != "${KF_HELM_SHA256}" ]; then
    log_error "Helm 离线介质校验和不匹配"
    exit 1
fi

existing_helm="$(command -v helm || true)"
if [ -n "${existing_helm}" ] && [ "${existing_helm}" != "/usr/local/bin/helm" ]; then
    log_error "检测到非 KubeFoundry 受管 Helm: ${existing_helm}"
    exit 1
fi

if [ -x "/usr/local/bin/helm" ] && [ -f "${marker_file}" ]; then
    installed_checksum="$(tr -d '[:space:]' < "${marker_file}")"
    if [ "${installed_checksum}" = "${KF_HELM_SHA256}" ]; then
        log_info "KubeFoundry 受管 Helm 已匹配离线介质"
    else
        log_info "更新 KubeFoundry 受管 Helm"
        install -m 0755 "${helm_source}" /usr/local/bin/helm
        printf '%s\n' "${KF_HELM_SHA256}" > "${marker_file}"
    fi
elif [ -e "/usr/local/bin/helm" ]; then
    log_error "检测到未标记的 /usr/local/bin/helm，拒绝覆盖"
    exit 1
else
    mkdir -p "${marker_dir}"
    install -m 0755 "${helm_source}" /usr/local/bin/helm
    printf '%s\n' "${KF_HELM_SHA256}" > "${marker_file}"
fi

helm version --short >/dev/null
helm list -A >/dev/null
log_success "Helm 离线安装并验证完成"
