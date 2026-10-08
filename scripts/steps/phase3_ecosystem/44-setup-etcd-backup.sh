#!/bin/bash

#===============================================================================
# 脚本名称：44-setup-etcd-backup.sh
# 功能：安装并立即执行 KubeFoundry 受管 etcd systemd 备份单元
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

set -o errexit -o nounset -o pipefail
if [ -f "./managed_config.sh" ]; then
    source "./managed_config.sh"
else
    source "${PROJECT_ROOT}/scripts/lib/managed_config.sh"
fi

system_root=${KF_SYSTEM_ROOT:-}
if [ -n "${system_root}" ]; then
    [[ "${system_root}" =~ ^/[A-Za-z0-9._/-]+$ ]] \
        && [ "${system_root}" != / ] && [ ! -L "${system_root}" ] || {
            log_error "测试系统根目录不安全"
            exit 1
        }
    system_root=${system_root%/}
fi

backup_dir="${system_root}/var/backups/kubefoundry/etcd"
backup_script="${system_root}/usr/local/libexec/kubefoundry-etcd-backup.sh"
service_unit="${system_root}/etc/systemd/system/kubefoundry-etcd-backup.service"
timer_unit="${system_root}/etc/systemd/system/kubefoundry-etcd-backup.timer"
kubeconfig="${system_root}/etc/kubernetes/admin.conf"
lock_file="${system_root}/run/kubefoundry-etcd-backup.lock"
etcd_pod=$(KUBECONFIG="${kubeconfig}" kubectl -n kube-system get pods \
    --selector component=etcd --field-selector "spec.nodeName=$(hostname)" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sed '/^$/d')
[[ "${etcd_pod}" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ ]] || {
    log_error "无法唯一确定本机 etcd 静态 Pod"
    exit 1
}
etcd_data_host=$(KUBECONFIG="${kubeconfig}" kubectl -n kube-system get pod "${etcd_pod}" \
    -o jsonpath='{.spec.volumes[?(@.name=="etcd-data")].hostPath.path}')
etcd_data_container=$(KUBECONFIG="${kubeconfig}" kubectl -n kube-system get pod "${etcd_pod}" \
    -o jsonpath='{.spec.containers[0].volumeMounts[?(@.name=="etcd-data")].mountPath}')
[[ "${etcd_data_host}" =~ ^/[A-Za-z0-9._/-]+$ ]] \
    && [[ "${etcd_data_container}" =~ ^/[A-Za-z0-9._/-]+$ ]] \
    && [ "${etcd_data_host}" != / ] && [ "${etcd_data_container}" != / ] \
    && [ -d "${etcd_data_host}" ] && [ ! -L "${etcd_data_host}" ] \
    && [ "$(realpath -e -- "${etcd_data_host}")" = "${etcd_data_host}" ] \
    && { [ -z "${KF_ETCD_DATA_DIR:-}" ] || [ "${etcd_data_host}" = "${KF_ETCD_DATA_DIR}" ]; } || {
        log_error "etcd 数据卷路径无效"
        exit 1
    }

for target in "${backup_script}" "${service_unit}" "${timer_unit}"; do
    kf_require_owned_or_absent "${target}" || {
        log_error "etcd 备份配置已存在且不属于 KubeFoundry: ${target}"
        exit 1
    }
done

[ ! -e "${backup_dir}" ] || { [ -d "${backup_dir}" ] && [ ! -L "${backup_dir}" ]; } || {
    log_error "etcd 备份目录不是安全的普通目录: ${backup_dir}"
    exit 1
}

work_dir=$(mktemp -d)
trap 'rm -rf -- "${work_dir}"' EXIT

cat > "${work_dir}/backup.sh" <<'EOF'
# Managed by KubeFoundry v0.3.2
#!/bin/bash
set -o errexit -o nounset -o pipefail

backup_dir=__BACKUP_DIR__
kubeconfig=__KUBECONFIG__
lock_file=__LOCK_FILE__
retain=7
command_timeout=15m
namespace=kube-system
remote_snapshot=""
host_snapshot=""
etcd_pod=""
local_part=""
status_part=""
checksum_part=""

cleanup() {
    [ -z "${local_part}" ] || rm -f -- "${local_part}"
    [ -z "${status_part}" ] || rm -f -- "${status_part}"
    [ -z "${checksum_part}" ] || rm -f -- "${checksum_part}"
    [ -z "${host_snapshot}" ] || rm -f -- "${host_snapshot}"
}
trap cleanup EXIT

[ -r "${kubeconfig}" ] || { printf '[ERROR] Kubernetes 管理配置不可读\n' >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { printf '[ERROR] 缺少 kubectl\n' >&2; exit 1; }
command -v timeout >/dev/null 2>&1 || { printf '[ERROR] 缺少 timeout\n' >&2; exit 1; }
command -v flock >/dev/null 2>&1 || { printf '[ERROR] 缺少 flock\n' >&2; exit 1; }

mkdir -p "$(dirname "${lock_file}")"
exec 9>"${lock_file}"
flock -n 9 || { printf '[INFO] etcd 备份任务已在运行\n'; exit 0; }

[ ! -L "${backup_dir}" ] || { printf '[ERROR] etcd 备份目录不能是符号链接\n' >&2; exit 1; }
install -d -m 0700 "${backup_dir}"
[ "$(stat -c '%a' "${backup_dir}")" = 700 ] || {
    printf '[ERROR] etcd 备份目录权限异常\n' >&2
    exit 1
}

node_name=$(hostname)
etcd_pod=$(timeout --foreground 30s env KUBECONFIG="${kubeconfig}" kubectl \
    --namespace "${namespace}" get pods --selector component=etcd \
    --field-selector "spec.nodeName=${node_name}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sed '/^$/d')
[ "$(printf '%s\n' "${etcd_pod}" | wc -l)" -eq 1 ] \
    && [[ "${etcd_pod}" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ ]] || {
        printf '[ERROR] 无法唯一确定本机 etcd 静态 Pod\n' >&2
        exit 1
    }

timestamp=${KF_ETCD_BACKUP_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}
[[ "${timestamp}" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || {
    printf '[ERROR] etcd 备份时间戳格式无效\n' >&2
    exit 1
}
filename="kubefoundry-etcd-${timestamp}.db"
final_snapshot="${backup_dir}/${filename}"
[ ! -e "${final_snapshot}" ] || {
    printf '[ERROR] 同名 etcd 备份已经存在: %s\n' "${filename}" >&2
    exit 1
}
snapshot_name=".kubefoundry-etcd-${timestamp}-$$.db"
remote_snapshot="__ETCD_DATA_CONTAINER__/${snapshot_name}"
host_snapshot="__ETCD_DATA_HOST__/${snapshot_name}"
[ ! -e "${host_snapshot}" ] || { printf '[ERROR] etcd 临时快照已存在\n' >&2; exit 1; }
local_part="${backup_dir}/.${filename}.part"
status_part="${backup_dir}/.${filename}.status.json.part"
checksum_part="${backup_dir}/.${filename}.sha256.part"

timeout --foreground "${command_timeout}" env KUBECONFIG="${kubeconfig}" kubectl \
    --namespace "${namespace}" exec "${etcd_pod}" -c etcd -- \
    etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
    --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
    snapshot save "${remote_snapshot}" >/dev/null
[ -s "${host_snapshot}" ] && [ ! -L "${host_snapshot}" ] || {
    printf '[ERROR] etcd 临时快照不存在或不安全\n' >&2
    exit 1
}

status_json=$(timeout --foreground "${command_timeout}" env KUBECONFIG="${kubeconfig}" \
    kubectl --namespace "${namespace}" exec "${etcd_pod}" -c etcd -- \
    etcdctl --write-out=json snapshot status "${remote_snapshot}")
revision=$(printf '%s\n' "${status_json}" \
    | sed -n 's/.*"revision"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
[[ "${revision}" =~ ^[0-9]+$ ]] && [ "${revision}" -gt 0 ] || {
    printf '[ERROR] etcd 快照完整性状态无效\n' >&2
    exit 1
}

remote_sha=$(sha256sum "${host_snapshot}" | awk '{print $1}')
[[ "${remote_sha}" =~ ^[0-9a-f]{64}$ ]] || {
    printf '[ERROR] etcd Pod 内快照校验和无效\n' >&2
    exit 1
}

cp -- "${host_snapshot}" "${local_part}"
chmod 0600 "${local_part}"
[ -s "${local_part}" ] || { printf '[ERROR] etcd 快照为空\n' >&2; exit 1; }
local_sha=$(sha256sum "${local_part}" | awk '{print $1}')
[ "${local_sha}" = "${remote_sha}" ] || {
    printf '[ERROR] etcd 快照传输校验失败\n' >&2
    exit 1
}

printf '%s\n' "${status_json}" > "${status_part}"
printf '%s  %s\n' "${local_sha}" "${filename}" > "${checksum_part}"
chmod 0600 "${status_part}" "${checksum_part}"
mv -f -- "${local_part}" "${final_snapshot}"
mv -f -- "${status_part}" "${final_snapshot}.status.json"
mv -f -- "${checksum_part}" "${final_snapshot}.sha256"
local_part=""
status_part=""
checksum_part=""

rm -f -- "${host_snapshot}"
remote_snapshot=""
host_snapshot=""

mapfile -t snapshots < <(find "${backup_dir}" -maxdepth 1 -type f \
    -name 'kubefoundry-etcd-????????T??????Z.db' -printf '%f\n' | sort -r)
for ((index=retain; index<${#snapshots[@]}; index++)); do
    old="${backup_dir}/${snapshots[index]}"
    rm -f -- "${old}" "${old}.status.json" "${old}.sha256"
done

printf '[SUCCESS] etcd 快照已生成并验证: %s (revision=%s)\n' "${filename}" "${revision}"
EOF

sed -i "s|__BACKUP_DIR__|${backup_dir}|g; s|__KUBECONFIG__|${kubeconfig}|g; s|__LOCK_FILE__|${lock_file}|g; s|__ETCD_DATA_HOST__|${etcd_data_host}|g; s|__ETCD_DATA_CONTAINER__|${etcd_data_container}|g" \
    "${work_dir}/backup.sh"

cat > "${work_dir}/backup.service" <<EOF
# Managed by KubeFoundry v0.3.2
[Unit]
Description=KubeFoundry etcd snapshot backup
After=kubelet.service
Wants=kubelet.service

[Service]
Type=oneshot
ExecStart=/bin/bash ${backup_script}
TimeoutStartSec=20min
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
NoNewPrivileges=true
PrivateTmp=true
# /home 下的 etcd 数据目录需保持可见，写入由 ReadWritePaths 放行。
ProtectHome=read-only
ProtectSystem=strict
ReadWritePaths=${backup_dir} ${etcd_data_host} /run
EOF

cat > "${work_dir}/backup.timer" <<'EOF'
# Managed by KubeFoundry v0.3.2
[Unit]
Description=Run KubeFoundry etcd snapshot backup daily

[Timer]
OnCalendar=*-*-* 02:10:00
Persistent=true
Unit=kubefoundry-etcd-backup.service

[Install]
WantedBy=timers.target
EOF

install_managed_file() {
    local source="$1" target="$2" mode="$3" temporary
    mkdir -p "$(dirname "${target}")"
    temporary="$(dirname "${target}")/.kubefoundry-$(basename "${target}").$$"
    install -m "${mode}" "${source}" "${temporary}"
    mv -f -- "${temporary}" "${target}"
}

install_managed_file "${work_dir}/backup.sh" "${backup_script}" 0755
install_managed_file "${work_dir}/backup.service" "${service_unit}" 0644
install_managed_file "${work_dir}/backup.timer" "${timer_unit}" 0644
install -d -m 0700 "${backup_dir}"

systemctl daemon-reload
systemctl enable --now kubefoundry-etcd-backup.timer >/dev/null
systemctl start kubefoundry-etcd-backup.service
[ "$(systemctl show kubefoundry-etcd-backup.service --property Result --value)" = success ] || {
    log_error "首次 etcd 备份服务执行失败"
    exit 1
}

log_success "etcd 备份单元已安装，首次快照已生成并验证"
