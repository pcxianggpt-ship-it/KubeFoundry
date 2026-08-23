#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
for variable in KF_NFS_SERVER KF_NFS_SHARE_PATH KF_NFS_WORKER_MOUNT_PATH; do
    [ -n "${!variable:-}" ] || error "验证缺少运行参数: ${variable}"
done
if [ "${KF_NFS_EXPORTS_MODE:-}" = managed ] && [ "${KF_NODE_IP:-}" = "${KF_NFS_SERVER}" ]; then
    printf '[SUCCESS] 受管 NFS 服务节点无需自挂载\n'
    exit 0
fi
command -v findmnt >/dev/null 2>&1 || error "验证工具不可用: findmnt"
source_path=$(timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" findmnt -n -o SOURCE --target "${KF_NFS_WORKER_MOUNT_PATH}" 2>/dev/null)
status=$?
case "${status}" in
    124|137) printf '[ERROR] 验证命令超时\n' >&2; exit 21 ;;
    0) ;;
    *) missing "NFS 工作节点挂载不存在" ;;
esac
[ "${source_path}" = "${KF_NFS_SERVER}:${KF_NFS_SHARE_PATH}" ] || missing "NFS 工作节点挂载来源不匹配"
grep -qF '# >>>KubeFoundry NFS fstab>>>' "${KF_NFS_FSTAB_FILE:-/etc/fstab}" 2>/dev/null || missing "NFS fstab 受管块不存在"
printf '[SUCCESS] 当前 Worker NFS 挂载已就绪\n'
