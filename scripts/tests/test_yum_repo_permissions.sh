#!/bin/bash

set -o errexit -o nounset -o pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
export TEST_ROOT
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/source/repo/repodata" \
    "${TEST_ROOT}/www" "${TEST_ROOT}/repos"
printf '<repomd/>\n' > "${TEST_ROOT}/source/repo/repodata/repomd.xml"
tar -czf "${TEST_ROOT}/k8s-repo-source.tar.gz" -C "${TEST_ROOT}/source" repo

export PATH="${TEST_ROOT}/bin:${PATH}"
export CALLS_FILE="${TEST_ROOT}/calls"
export KF_YUM_WEB_ROOT="${TEST_ROOT}/www/html"
export KF_YUM_LOCAL_REPO_CONFIG="${TEST_ROOT}/repos/k8s.repo"
export KF_YUM_LOCAL_METADATA_URL="http://127.0.0.1/repo/repodata/repomd.xml"
export KF_YUM_HTTP_REPO_CONFIG="${TEST_ROOT}/repos/k8s-http.repo"
export PRIMARY_CONTROL_HOSTNAME="cp-1"
export LOG_FILE="${TEST_ROOT}/yum-test.log"

cat > "${TEST_ROOT}/bin/yum" <<'EOF'
#!/bin/bash
printf 'yum %s\n' "$*" >> "${CALLS_FILE}"
EOF
cat > "${TEST_ROOT}/bin/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >> "${CALLS_FILE}"
if [ "$*" = "is-active --quiet firewalld" ] || [ "$*" = "is-enabled --quiet firewalld" ]; then exit 3; fi
EOF
cat > "${TEST_ROOT}/bin/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >> "${CALLS_FILE}"
EOF
chmod +x "${TEST_ROOT}/bin/yum" "${TEST_ROOT}/bin/systemctl" "${TEST_ROOT}/bin/curl"

source "${PROJECT_ROOT}/scripts/lib/logger.sh"
export COLOR_RESET COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE
export -f _log_timestamp _log_write log_info log_success log_warn log_error log_substep log_separator

bash -c 'source "$1"; source "$2" "$3"' _ \
    "${PROJECT_ROOT}/scripts/lib/logger.sh" \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/10-setup-yum-source.sh" \
    "${TEST_ROOT}/k8s-repo-source.tar.gz"

[ "$(stat -c '%a' "${TEST_ROOT}/www")" = 777 ] || fail "仓库父目录权限不是 777"
[ "$(stat -c '%a' "${KF_YUM_WEB_ROOT}")" = 777 ] || fail "Web 根目录权限不是 777"
[ "$(stat -c '%a' "${TEST_ROOT}/www/html/repo/repodata/repomd.xml")" = 777 ] \
    || fail "仓库文件权限不是 777"
grep -Fq 'systemctl stop firewalld' "${CALLS_FILE}" || fail "未直接关闭 firewalld"
grep -Fq 'systemctl disable firewalld' "${CALLS_FILE}" || fail "未禁用 firewalld"
grep -Fq 'yum -q --disablerepo=* --enablerepo=k8s-yum makecache' "${CALLS_FILE}" \
    || fail "服务端未限制目标仓库刷新缓存"
grep -Fq 'yum -yq --disablerepo=* --enablerepo=k8s-yum install httpd' "${CALLS_FILE}" \
    || fail "服务端未仅从目标仓库安装 httpd"
grep -Fq "curl --fail --silent --show-error --max-time 10 --output /dev/null ${KF_YUM_LOCAL_METADATA_URL}" \
    "${CALLS_FILE}" || fail "服务端未校验仓库 HTTP 200"

if grep -Eq 'setfacl|semanage|restorecon|policycoreutils|getfacl|getenforce|sshpass' \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/10-setup-yum-source.sh"; then
    fail "服务端脚本仍依赖额外的系统管理工具"
fi
# 重复执行仍保持相同配置和权限。
bash -c 'source "$1"; source "$2" "$3"' _ \
    "${PROJECT_ROOT}/scripts/lib/logger.sh" \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/10-setup-yum-source.sh" \
    "${TEST_ROOT}/k8s-repo-source.tar.gz"
bash -c 'source "$1"; vf_verify_base 10-setup-yum-source' _ \
    "${PROJECT_ROOT}/scripts/lib/verify.sh"

bash -c 'source "$1"; source "$2"' _ \
    "${PROJECT_ROOT}/scripts/lib/logger.sh" \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/12-setup-k8s-repo.sh"
bash -c 'source "$1"; vf_verify_base 12-setup-k8s-repo' _ \
    "${PROJECT_ROOT}/scripts/lib/verify.sh"

printf 'yum repository permission tests passed\n'
