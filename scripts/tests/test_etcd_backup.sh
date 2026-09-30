#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
SYSTEM_ROOT="${TMP}/root"
BIN="${TMP}/bin"
mkdir -p "${BIN}" "${SYSTEM_ROOT}/etc/kubernetes"
mkdir -p "${SYSTEM_ROOT}/etcd-data"
touch "${SYSTEM_ROOT}/etc/kubernetes/admin.conf"

cat > "${BIN}/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_ETCD_SYSTEMCTL_LOG}"
case "$*" in
  *"show kubefoundry-etcd-backup.service --property Result --value"*) printf 'success\n' ;;
esac
exit 0
EOF
cat > "${BIN}/hostname" <<'EOF'
#!/bin/bash
printf 'cp-a\n'
EOF
cat > "${BIN}/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_ETCD_KUBECTL_LOG}"
args="$*"
last="${!#}"
case "${args}" in
  *"get pods --selector component=etcd"*) printf 'etcd-cp-a\n' ;;
  *"get pod etcd-cp-a"*) printf '%s' "${KF_ETCD_HOST_DATA_DIR}" ;;
  *"snapshot save "*)
    printf 'mock-etcd-snapshot:%s\n' "${last}" > "${last}" ;;
  *"etcdctl --write-out=json snapshot status"*)
    [ -s "${last}" ] || exit 1
    printf '{"hash":1234,"revision":42,"totalKey":100,"totalSize":4096}\n' ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "${BIN}"/*

export PATH="${BIN}:${PATH}"
export PROJECT_ROOT="${ROOT}"
export KF_SYSTEM_ROOT="${SYSTEM_ROOT}"
export KF_ETCD_SYSTEMCTL_LOG="${TMP}/systemctl.log"
export KF_ETCD_KUBECTL_LOG="${TMP}/kubectl.log"
export KF_ETCD_HOST_DATA_DIR="${SYSTEM_ROOT}/etcd-data"
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "$*" >&2; }
export -f log_info log_success log_warn log_error

bash "${ROOT}/scripts/steps/phase3_ecosystem/44-setup-etcd-backup.sh"

backup_script="${SYSTEM_ROOT}/usr/local/libexec/kubefoundry-etcd-backup.sh"
service_unit="${SYSTEM_ROOT}/etc/systemd/system/kubefoundry-etcd-backup.service"
timer_unit="${SYSTEM_ROOT}/etc/systemd/system/kubefoundry-etcd-backup.timer"
backup_dir="${SYSTEM_ROOT}/var/backups/kubefoundry/etcd"

for target in "${backup_script}" "${service_unit}" "${timer_unit}"; do
    [ "$(head -n 1 "${target}")" = '# Managed by KubeFoundry v0.3.2' ]
done
grep -Fq 'OnCalendar=*-*-* 02:10:00' "${timer_unit}"
grep -Fq "ExecStart=/bin/bash ${backup_script}" "${service_unit}"
grep -Fq "ReadWritePaths=${backup_dir} ${KF_ETCD_HOST_DATA_DIR} /run" "${service_unit}"
! grep -Eq 'crontab[[:space:]]+-e|etcdbak\.sh' \
    "${ROOT}/scripts/steps/phase3_ecosystem/44-setup-etcd-backup.sh"

mkdir -p "${backup_dir}"
printf 'user-owned\n' > "${backup_dir}/do-not-delete.txt"
for second in 01 02 03 04 05 06 07 08 09; do
    KF_ETCD_BACKUP_TIMESTAMP="20260829T1200${second}Z" bash "${backup_script}"
done

[ "$(find "${backup_dir}" -maxdepth 1 -type f -name 'kubefoundry-etcd-*.db' | wc -l)" -eq 7 ]
[ ! -e "${backup_dir}/kubefoundry-etcd-20260829T120001Z.db" ]
[ ! -e "${backup_dir}/kubefoundry-etcd-20260829T120002Z.db" ]
[ -e "${backup_dir}/kubefoundry-etcd-20260829T120009Z.db" ]
grep -Fqx 'user-owned' "${backup_dir}/do-not-delete.txt"
bash "${ROOT}/scripts/verify/phase3_ecosystem/verify-44-setup-etcd-backup.sh"

grep -q 'etcdctl --endpoints=https://127.0.0.1:2379' "${KF_ETCD_KUBECTL_LOG}"
! grep -q 'exec etcd-cp-a -c etcd -- env ' "${KF_ETCD_KUBECTL_LOG}"
grep -q 'etcdctl --write-out=json snapshot status' "${KF_ETCD_KUBECTL_LOG}"
[ -z "$(find "${KF_ETCD_HOST_DATA_DIR}" -maxdepth 1 -name '.kubefoundry-etcd-*' -print -quit)" ]
grep -q 'enable --now kubefoundry-etcd-backup.timer' "${KF_ETCD_SYSTEMCTL_LOG}"
grep -q 'start kubefoundry-etcd-backup.service' "${KF_ETCD_SYSTEMCTL_LOG}"

printf '# user file\n' > "${service_unit}"
if bash "${ROOT}/scripts/steps/phase3_ecosystem/44-setup-etcd-backup.sh" >/dev/null 2>&1; then
    printf '未拒绝非 KubeFoundry 所有的 etcd systemd unit\n' >&2
    exit 1
fi

printf 'etcd backup tests passed\n'
