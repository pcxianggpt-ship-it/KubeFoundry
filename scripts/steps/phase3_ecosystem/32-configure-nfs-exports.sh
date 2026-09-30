#!/bin/bash

#===============================================================================
# 脚本名称：32-configure-nfs-exports.sh
# 功能：在 Java 选定的 NFS 节点维护 exports，或验证外部 NFS
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
if [ -f "./managed_config.sh" ]; then source "./managed_config.sh"; else source "${PROJECT_ROOT}/scripts/lib/managed_config.sh"; fi
phase3_init
: "${KF_NFS_SERVER:?缺少 NFS 服务地址}"
: "${KF_NFS_SHARE_PATH:?缺少 NFS 共享目录}"
: "${KF_NFS_EXPORTS_MODE:?缺少 NFS exports 模式}"

managed_marker_begin="# >>>KubeFoundry NFS exports>>>"
managed_marker_end="# <<<KubeFoundry NFS exports<<<"
export_entry="${KF_NFS_SHARE_PATH} *(rw,sync,no_subtree_check,no_root_squash)"
exports_file="${KF_NFS_EXPORTS_FILE:-/etc/exports}"

if [ "${KF_NFS_EXPORTS_MODE}" = "managed" ]; then
    [ "${KF_NODE_IP}" = "${KF_NFS_SERVER}" ] || {
        log_error "当前节点不是配置的 managed NFS 服务节点"
        exit 1
    }
    mkdir -p -- "${KF_NFS_SHARE_PATH}"
    systemctl enable --now nfs-server
    exports_content="$(mktemp)"
    trap 'rm -f "${exports_content}"' EXIT
    printf '%s\n' "${export_entry}" > "${exports_content}"
    kf_replace_managed_block "${exports_file}" "${managed_marker_begin}" \
        "${managed_marker_end}" "${exports_content}" || {
        log_error "NFS exports 受管标记不完整或配置写入失败"
        exit 1
    }
    exportfs -ra
    log_success "managed NFS exports 已幂等配置"
elif [ "${KF_NFS_EXPORTS_MODE}" = "external" ]; then
    command -v showmount >/dev/null 2>&1 || {
        log_error "验证 external NFS 需要 showmount"
        exit 1
    }
    showmount -e "${KF_NFS_SERVER}" | grep -Fq -- "${KF_NFS_SHARE_PATH}" || {
        log_error "external NFS 共享目录不可访问: ${KF_NFS_SHARE_PATH}"
        exit 1
    }
    verify_mount=$(mktemp -d)
    trap 'umount "${verify_mount}" >/dev/null 2>&1 || true; rmdir "${verify_mount}" 2>/dev/null || true' EXIT
    mount -t nfs -o ro "${KF_NFS_SERVER}:${KF_NFS_SHARE_PATH}" "${verify_mount}"
    log_success "external NFS 共享已验证，未修改外部服务器"
else
    log_error "不支持的 NFS exports 模式: ${KF_NFS_EXPORTS_MODE}"
    exit 1
fi
