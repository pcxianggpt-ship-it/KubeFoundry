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

repo_config="${KF_YUM_HTTP_REPO_CONFIG:-/etc/yum.repos.d/k8s-http.repo}"
primary_hostname="${PRIMARY_CONTROL_HOSTNAME:-k8sc1}"
[ -r "${repo_config}" ] || missing "Kubernetes HTTP Repo 未配置"
grep -qF '# Managed by KubeFoundry v0.3.2' "${repo_config}" || missing "Kubernetes HTTP Repo 不是 KubeFoundry 受管配置"
grep -Eq '^enabled[[:space:]]*=[[:space:]]*1' "${repo_config}" || missing "Kubernetes HTTP Repo 未启用"
grep -qF "baseurl=http://${primary_hostname}/repo" "${repo_config}" || missing "Kubernetes HTTP Repo 地址不匹配"
run curl --fail --silent --show-error --max-time 10 --output /dev/null "http://${primary_hostname}/repo/repodata/repomd.xml" || missing "远程访问 Kubernetes YUM 仓库未返回 HTTP 200"
run yum -q --disablerepo='*' --enablerepo='k8s-repo' makecache >/dev/null 2>&1 || missing "Kubernetes HTTP YUM 仓库缓存创建失败"
printf '[SUCCESS] Kubernetes HTTP Repo 已就绪\n'
