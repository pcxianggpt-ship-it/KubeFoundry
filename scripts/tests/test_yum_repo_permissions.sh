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
export ACL_MARKER="${TEST_ROOT}/acl-ready"
export KF_YUM_WEB_ROOT="${TEST_ROOT}/www/html"
export KF_YUM_LOCAL_REPO_CONFIG="${TEST_ROOT}/repos/k8s.repo"
export KF_YUM_LOCAL_METADATA_URL="http://127.0.0.1/repo/repodata/repomd.xml"
export KF_YUM_HTTP_REPO_CONFIG="${TEST_ROOT}/repos/k8s-http.repo"
export PRIMARY_CONTROL_HOSTNAME="cp-1"
export LOG_FILE="${TEST_ROOT}/yum-test.log"

mock_command() {
    local name="$1"
    shift
    {
        printf '#!/bin/bash\n'
        printf '%s\n' "$@"
    } > "${TEST_ROOT}/bin/${name}"
    chmod +x "${TEST_ROOT}/bin/${name}"
}

mock_command yum 'printf "yum %s\\n" "$*" >> "${CALLS_FILE}"'
mock_command systemctl 'printf "systemctl %s\\n" "$*" >> "${CALLS_FILE}"; if [ "$*" = "is-active --quiet firewalld" ]; then [ "${FIREWALL_ACTIVE:-0}" = 1 ]; fi'
mock_command firewall-cmd 'printf "firewall-cmd %s\\n" "$*" >> "${CALLS_FILE}"'
mock_command ps 'printf "root httpd\\napache httpd\\n"'
mock_command getent '[ "$1" = passwd ] && [ "$2" = apache ]'
mock_command setfacl 'printf "setfacl %s\\n" "$*" >> "${CALLS_FILE}"; : > "${ACL_MARKER}"'
mock_command runuser 'printf "runuser %s\\n" "$*" >> "${CALLS_FILE}"; [ -f "${ACL_MARKER}" ]'
mock_command getenforce 'printf "Enforcing\\n"'
mock_command semanage 'printf "semanage %s\\n" "$*" >> "${CALLS_FILE}"'
mock_command restorecon 'printf "restorecon %s\\n" "$*" >> "${CALLS_FILE}"'
mock_command stat 'printf "system_u:object_r:httpd_sys_content_t:s0\\n"'
mock_command curl 'printf "curl %s\\n" "$*" >> "${CALLS_FILE}"; [ -f "${ACL_MARKER}" ]'

source "${PROJECT_ROOT}/scripts/lib/logger.sh"
export COLOR_RESET COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE
export -f _log_timestamp _log_write log_info log_success log_warn log_error log_substep log_separator

if curl --fail --silent http://127.0.0.1/repo/repodata/repomd.xml; then
    fail "父目录缺少搜索权限时未复现 HTTP 403"
fi

mock_command ps 'printf "root httpd\\n"'
if KF_HTTPD_USER_DETECT_ATTEMPTS=1 bash -c 'source "$1"; source "$2" "$3"' _ \
    "${PROJECT_ROOT}/scripts/lib/logger.sh" \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/10-setup-yum-source.sh" \
    "${TEST_ROOT}/k8s-repo-source.tar.gz" >/dev/null 2>&1; then
    fail "无法确认 httpd 实际账户时安装未安全失败"
fi
mock_command ps 'printf "root httpd\\napache httpd\\n"'
export FIREWALL_ACTIVE=1

bash -c 'source "$1"; source "$2" "$3"' _ \
    "${PROJECT_ROOT}/scripts/lib/logger.sh" \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/10-setup-yum-source.sh" \
    "${TEST_ROOT}/k8s-repo-source.tar.gz"

[ -f "${KF_YUM_LOCAL_REPO_CONFIG}" ] || fail "本地 Repo 配置未生成"
grep -Fq '# Managed by KubeFoundry v0.3.2' "${KF_YUM_LOCAL_REPO_CONFIG}" \
    || fail "本地 Repo 缺少受管标记"
grep -Fq "setfacl -m u:apache:--x ${TEST_ROOT}/www" "${CALLS_FILE}" \
    || fail "未设置父目录最小遍历 ACL"
grep -Fq "setfacl -m u:apache:--x ${TEST_ROOT}/www/html" "${CALLS_FILE}" \
    || fail "未设置 Web 根目录最小遍历 ACL"
grep -Fq 'semanage fcontext -a -t httpd_sys_content_t' "${CALLS_FILE}" \
    || fail "未登记仓库 SELinux 标签"
grep -Fq "restorecon -RF ${TEST_ROOT}/www/html/repo" "${CALLS_FILE}" \
    || fail "未恢复仓库 SELinux 标签"
grep -Fq 'firewall-cmd --permanent --add-service=http' "${CALLS_FILE}" \
    || fail "firewalld 运行时未按最小范围开放 HTTP 服务"
grep -Fq "curl --fail --silent --show-error --max-time 10 --output /dev/null ${KF_YUM_LOCAL_METADATA_URL}" "${CALLS_FILE}" \
    || fail "服务端未校验仓库 HTTP 200"
grep -Fq "yum -q --disablerepo=* --enablerepo=k8s-yum makecache" "${CALLS_FILE}" \
    || fail "服务端未限制目标仓库刷新缓存"

first_acl_count=$(grep -c '^setfacl ' "${CALLS_FILE}")
bash -c 'source "$1"; source "$2" "$3"' _ \
    "${PROJECT_ROOT}/scripts/lib/logger.sh" \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/10-setup-yum-source.sh" \
    "${TEST_ROOT}/k8s-repo-source.tar.gz"
second_acl_count=$(grep -c '^setfacl ' "${CALLS_FILE}")
[ "${second_acl_count}" -eq $((first_acl_count * 2)) ] \
    || fail "重复执行产生了不稳定的 ACL 操作"

if grep -Eq 'chmod[[:space:]]+(-R[[:space:]]+)?777|setenforce|chown' \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/10-setup-yum-source.sh"; then
    fail "YUM 权限修复包含过度授权或关闭 SELinux"
fi

bash -c 'source "$1"; vf_verify_base 10-setup-yum-source' _ \
    "${PROJECT_ROOT}/scripts/lib/verify.sh"

bash -c 'source "$1"; source "$2"' _ \
    "${PROJECT_ROOT}/scripts/lib/logger.sh" \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/12-setup-k8s-repo.sh"
grep -Fq '# Managed by KubeFoundry v0.3.2' "${KF_YUM_HTTP_REPO_CONFIG}" \
    || fail "HTTP Repo 缺少受管标记"
grep -Fq 'baseurl=http://cp-1/repo' "${KF_YUM_HTTP_REPO_CONFIG}" \
    || fail "HTTP Repo 地址不匹配"
grep -Fq 'yum -q --disablerepo=* --enablerepo=k8s-repo makecache' "${CALLS_FILE}" \
    || fail "客户端未限制目标仓库刷新缓存"
bash -c 'source "$1"; vf_verify_base 12-setup-k8s-repo' _ \
    "${PROJECT_ROOT}/scripts/lib/verify.sh"

printf 'yum repository permission tests passed\n'
