#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }

system_root=${KF_SYSTEM_ROOT:-}
if [ -n "${system_root}" ]; then
    [[ "${system_root}" =~ ^/[A-Za-z0-9._/-]+$ ]] \
        && [ "${system_root}" != / ] && [ ! -L "${system_root}" ] \
        || error "测试系统根目录不安全"
    system_root=${system_root%/}
fi

backup_dir="${system_root}/var/backups/kubefoundry/etcd"
backup_script="${system_root}/usr/local/libexec/kubefoundry-etcd-backup.sh"
service_unit="${system_root}/etc/systemd/system/kubefoundry-etcd-backup.service"
timer_unit="${system_root}/etc/systemd/system/kubefoundry-etcd-backup.timer"
marker='# Managed by KubeFoundry v0.3.2'

command -v systemctl >/dev/null 2>&1 || error "验证工具不可用: systemctl"
for target in "${backup_script}" "${service_unit}" "${timer_unit}"; do
    [ -f "${target}" ] && [ ! -L "${target}" ] || missing "etcd 备份受管文件不存在: ${target}"
    [ "$(head -n 1 "${target}")" = "${marker}" ] || error "etcd 备份文件所有权异常: ${target}"
done
[ "$(stat -c '%a' "${backup_script}")" = 755 ] || error "etcd 备份脚本权限异常"
[ "$(stat -c '%a' "${service_unit}")" = 644 ] || error "etcd 备份 service 权限异常"
[ "$(stat -c '%a' "${timer_unit}")" = 644 ] || error "etcd 备份 timer 权限异常"

systemctl is-enabled --quiet kubefoundry-etcd-backup.timer \
    || missing "etcd 备份 timer 未启用"
systemctl is-active --quiet kubefoundry-etcd-backup.timer \
    || missing "etcd 备份 timer 未运行"
[ "$(systemctl show kubefoundry-etcd-backup.service --property Result --value 2>/dev/null)" = success ] \
    || missing "etcd 备份 service 最近一次执行未成功"

[ -d "${backup_dir}" ] && [ ! -L "${backup_dir}" ] || missing "etcd 备份目录不存在"
[ "$(stat -c '%a' "${backup_dir}")" = 700 ] || error "etcd 备份目录权限异常"

newest=$(find "${backup_dir}" -maxdepth 1 -type f \
    -name 'kubefoundry-etcd-????????T??????Z.db' -printf '%T@ %f\n' 2>/dev/null \
    | sort -nr | awk 'NR == 1 { print $2 }')
[ -n "${newest}" ] || missing "未找到 KubeFoundry etcd 快照"
[[ "${newest}" =~ ^kubefoundry-etcd-[0-9]{8}T[0-9]{6}Z\.db$ ]] \
    || error "etcd 快照文件名不安全"
snapshot="${backup_dir}/${newest}"
[ -s "${snapshot}" ] && [ ! -L "${snapshot}" ] || missing "最新 etcd 快照为空或不安全"
[ "$(stat -c '%a' "${snapshot}")" = 600 ] || error "最新 etcd 快照权限异常"

now=$(date +%s)
modified=$(stat -c '%Y' "${snapshot}")
age=$((now - modified))
[ "${age}" -ge 0 ] && [ "${age}" -le "${KF_ETCD_BACKUP_MAX_AGE_SECONDS:-1800}" ] \
    || missing "最新 etcd 快照不够新鲜"

checksum_file="${snapshot}.sha256"
status_file="${snapshot}.status.json"
[ -f "${checksum_file}" ] && [ ! -L "${checksum_file}" ] || missing "etcd 快照校验和不存在"
[ -f "${status_file}" ] && [ ! -L "${status_file}" ] || missing "etcd 快照状态不存在"
(cd "${backup_dir}" && sha256sum --check --strict "${newest}.sha256" >/dev/null) \
    || error "etcd 快照 SHA-256 校验失败"
revision=$(sed -n 's/.*"revision"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
    "${status_file}")
[[ "${revision}" =~ ^[0-9]+$ ]] && [ "${revision}" -gt 0 ] \
    || error "etcd 快照完整性状态无效"

snapshot_count=$(find "${backup_dir}" -maxdepth 1 -type f \
    -name 'kubefoundry-etcd-????????T??????Z.db' | wc -l)
[ "${snapshot_count}" -le 7 ] || error "etcd 快照超过保留数量"

printf '[SUCCESS] etcd 备份 timer、最近执行和快照完整性验证通过 (revision=%s)\n' \
    "${revision}"
