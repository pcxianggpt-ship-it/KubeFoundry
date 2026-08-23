#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
run() {
    command -v timeout >/dev/null 2>&1 || error "验证工具不可用: timeout"
    command -v "$1" >/dev/null 2>&1 || error "验证工具不可用: $1"
    timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" "$@"
    local status=$?
    case "${status}" in 124|137) printf '[ERROR] 验证命令超时\n' >&2; exit 21 ;; esac
    return "${status}"
}

web_root="${KF_YUM_WEB_ROOT:-/var/www/html}"
repo_root="${web_root}/repo"
repo_config="${KF_YUM_LOCAL_REPO_CONFIG:-/etc/yum.repos.d/k8s.repo}"
metadata_url="${KF_YUM_LOCAL_METADATA_URL:-http://127.0.0.1/repo/repodata/repomd.xml}"
[ -r "${repo_config}" ] || missing "Kubernetes YUM 源未配置"
grep -qF '# Managed by KubeFoundry v0.3.2' "${repo_config}" || missing "Kubernetes YUM 源不是 KubeFoundry 受管配置"
[ -f "${repo_root}/repodata/repomd.xml" ] || missing "Kubernetes YUM 仓库元数据不存在"
[ "$(stat -c '%a' "$(dirname "${web_root}")" 2>/dev/null)" = 777 ] || missing "Kubernetes YUM 仓库父目录权限不是 777"
[ "$(stat -c '%a' "${web_root}" 2>/dev/null)" = 777 ] || missing "Kubernetes YUM Web 目录权限不是 777"
[ -z "$(find "${repo_root}" ! -perm 0777 -print -quit 2>/dev/null)" ] || missing "Kubernetes YUM 仓库权限不是 777"
run systemctl is-active --quiet httpd || missing "httpd 未运行"
run systemctl is-enabled --quiet httpd || missing "httpd 未设为开机启动"
run systemctl is-active --quiet firewalld && missing "firewalld 仍处于运行状态"
run systemctl is-enabled --quiet firewalld && missing "firewalld 仍处于启用状态"
run curl --fail --silent --show-error --max-time 10 --output /dev/null "${metadata_url}" || missing "本机访问 Kubernetes YUM 仓库未返回 HTTP 200"
run yum -q --disablerepo='*' --enablerepo='k8s-yum' makecache >/dev/null 2>&1 || missing "Kubernetes 本地 YUM 仓库缓存创建失败"
printf '[SUCCESS] Kubernetes YUM 源已就绪\n'
