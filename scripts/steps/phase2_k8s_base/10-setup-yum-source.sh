#!/bin/bash

#===============================================================================
# 脚本名称：10-setup-yum-source.sh
# 功能：使用最小权限配置本地 Kubernetes YUM HTTP 仓库
# 执行机器：主控制节点
# 作者：KubeFoundry Team
# 版本：0.3.2
#===============================================================================

repo_source_name="$1"
web_root="${KF_YUM_WEB_ROOT:-/var/www/html}"
repo_root="${web_root}/repo"
metadata_file="${repo_root}/repodata/repomd.xml"
local_repo_config="${KF_YUM_LOCAL_REPO_CONFIG:-/etc/yum.repos.d/k8s.repo}"
local_metadata_url="${KF_YUM_LOCAL_METADATA_URL:-http://127.0.0.1/repo/repodata/repomd.xml}"

fail_step() {
    log_error "$*"
    exit 1
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || fail_step "缺少必需工具: $1"
}

detect_httpd_user() {
    local detected="" attempt attempts="${KF_HTTPD_USER_DETECT_ATTEMPTS:-5}"
    [[ "${attempts}" =~ ^[1-9][0-9]*$ ]] || fail_step "httpd 账户检测次数无效"
    for ((attempt = 1; attempt <= attempts; attempt++)); do
        detected=$(ps -eo user=,comm= 2>/dev/null | awk '$2 == "httpd" && $1 != "root" { print $1; exit }')
        [ -n "${detected}" ] && break
        sleep 1
    done
    [[ "${detected}" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] \
        || fail_step "无法确认 httpd 实际运行账户"
    getent passwd "${detected}" >/dev/null 2>&1 \
        || fail_step "httpd 运行账户不存在: ${detected}"
    HTTPD_USER="${detected}"
}

apply_repo_acl() {
    local httpd_user="$1" parent
    require_tool setfacl
    require_tool find
    require_tool runuser

    for parent in "$(dirname "${web_root}")" "${web_root}"; do
        [ -d "${parent}" ] || fail_step "仓库父目录不存在: ${parent}"
        setfacl -m "u:${httpd_user}:--x" "${parent}" \
            || fail_step "无法设置仓库父目录遍历 ACL: ${parent}"
    done
    find "${repo_root}" -type d -exec setfacl -m "u:${httpd_user}:r-x" {} + \
        || fail_step "无法设置仓库目录只读 ACL"
    find "${repo_root}" -type f -exec setfacl -m "u:${httpd_user}:r--" {} + \
        || fail_step "无法设置仓库文件只读 ACL"
    setfacl -m "d:u:${httpd_user}:r-x" "${repo_root}" \
        || fail_step "无法设置仓库默认目录 ACL"
    runuser -u "${httpd_user}" -- test -r "${metadata_file}" \
        || fail_step "httpd 账户仍无法读取仓库元数据"
}

apply_repo_selinux_context() {
    local selinux_mode repo_context
    command -v getenforce >/dev/null 2>&1 || return 0
    selinux_mode=$(getenforce 2>/dev/null) || fail_step "无法读取 SELinux 状态"
    [ "${selinux_mode}" != "Disabled" ] || return 0

    require_tool restorecon
    if command -v semanage >/dev/null 2>&1; then
        semanage fcontext -a -t httpd_sys_content_t "${repo_root}(/.*)?" >/dev/null 2>&1 \
            || semanage fcontext -m -t httpd_sys_content_t "${repo_root}(/.*)?" \
            || fail_step "无法登记仓库 SELinux 文件上下文"
    else
        log_warn "semanage 不可用，将使用系统默认规则恢复并校验仓库标签"
    fi
    restorecon -RF "${repo_root}" || fail_step "无法恢复仓库 SELinux 标签"
    repo_context=$(stat -Lc '%C' "${metadata_file}" 2>/dev/null || true)
    [[ "${repo_context}" == *:httpd_sys_content_t:* ]] \
        || fail_step "仓库 SELinux 标签不是 httpd_sys_content_t"
}

allow_repo_http_through_firewall() {
    systemctl is-active --quiet firewalld >/dev/null 2>&1 || return 0
    require_tool firewall-cmd
    firewall-cmd --permanent --add-service=http >/dev/null \
        || fail_step "无法为本地仓库开放 HTTP 防火墙服务"
    firewall-cmd --reload >/dev/null || fail_step "防火墙规则重载失败"
}

[ -f "${repo_source_name}" ] || fail_step "YUM 源文件不存在: ${repo_source_name}"
require_tool tar
require_tool yum
require_tool systemctl
require_tool curl

mkdir -p "${web_root}" "$(dirname "${local_repo_config}")" \
    || fail_step "无法创建 YUM 仓库目录"
tar -zxf "${repo_source_name}" -C "${web_root}" \
    || fail_step "YUM 源文件解压失败"
[ -f "${metadata_file}" ] || fail_step "仓库元数据不存在: ${metadata_file}"

if ! cat > "${local_repo_config}" <<EOF
# Managed by KubeFoundry v0.3.2
[k8s-yum]
name=KubeFoundry Kubernetes local repository
baseurl=file://${repo_root}/
enabled=1
gpgcheck=0
EOF
then
    fail_step "无法写入 Kubernetes 本地 YUM Repo 配置"
fi

yum -yq install httpd sshpass acl curl policycoreutils \
    || fail_step "无法从离线仓库安装 HTTP/ACL/SELinux 工具"
if ! command -v semanage >/dev/null 2>&1; then
    yum -yq install policycoreutils-python-utils >/dev/null 2>&1 \
        || yum -yq install policycoreutils-python >/dev/null 2>&1 \
        || log_warn "离线仓库未提供 semanage 工具包，将校验系统默认 SELinux 标签"
fi

systemctl enable httpd --now || fail_step "httpd 启动失败"
HTTPD_USER=""
detect_httpd_user
httpd_user="${HTTPD_USER}"
log_info "已确认 httpd 运行账户: ${httpd_user}"
apply_repo_acl "${httpd_user}"
apply_repo_selinux_context
allow_repo_http_through_firewall

curl --fail --silent --show-error --max-time 10 --output /dev/null "${local_metadata_url}" \
    || fail_step "本机访问仓库元数据未返回 HTTP 200"
yum -q clean all || fail_step "YUM 缓存清理失败"
yum -q --disablerepo='*' --enablerepo='k8s-yum' makecache \
    || fail_step "Kubernetes 本地 YUM 仓库缓存创建失败"

log_success "Kubernetes YUM HTTP 仓库配置完成"
