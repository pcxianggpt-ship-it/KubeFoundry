#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
managed_block_complete() {
    local file="$1" begin="$2" end="$3"
    [ "$(grep -Fxc "${begin}" "${file}" 2>/dev/null || true)" -eq 1 ] &&
        [ "$(grep -Fxc "${end}" "${file}" 2>/dev/null || true)" -eq 1 ] &&
        awk -v begin="${begin}" -v end="${end}" '
            $0 == begin { inside = 1; next }
            $0 == end && inside { complete = 1; inside = 0 }
            END { exit(complete && !inside ? 0 : 1) }
        ' "${file}"
}
for variable in KF_NODE_IP KF_NFS_SERVER KF_NFS_SHARE_PATH KF_NFS_EXPORTS_MODE; do
    [ -n "${!variable:-}" ] || error "验证缺少运行参数: ${variable}"
done

case "${KF_NFS_EXPORTS_MODE}" in
    managed)
        [ "${KF_NODE_IP}" = "${KF_NFS_SERVER}" ] || error "当前节点不是受管 NFS 服务节点"
        [ -d "${KF_NFS_SHARE_PATH}" ] || missing "NFS 共享目录不存在"
        systemctl is-active --quiet nfs-server || missing "nfs-server 未运行"
        managed_block_complete "${KF_NFS_EXPORTS_FILE:-/etc/exports}" \
            '# >>>KubeFoundry NFS exports>>>' '# <<<KubeFoundry NFS exports<<<' || \
            missing "NFS exports 受管块不完整"
        ;;
    external)
        exports=$(timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" showmount -e "${KF_NFS_SERVER}" 2>/dev/null)
        status=$?
        case "${status}" in
            124|137) printf '[ERROR] 验证命令超时\n' >&2; exit 21 ;;
            0) ;;
            *) error "外部 NFS 查询失败" ;;
        esac
        printf '%s\n' "${exports}" | grep -Fq -- "${KF_NFS_SHARE_PATH}" || missing "外部 NFS 共享目录不存在"
        ;;
    *) error "NFS exports 模式无效" ;;
esac
printf '[SUCCESS] NFS exports 已就绪\n'
