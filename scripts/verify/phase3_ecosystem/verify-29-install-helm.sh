#!/bin/bash

set -o nounset -o pipefail

[ -x /usr/local/bin/helm ] || { printf '[INFO] 受管 Helm 未安装\n'; exit 10; }
[ -r /usr/local/lib/kubefoundry/helm.sha256 ] || { printf '[INFO] Helm 受管标记不存在\n'; exit 10; }
grep -Eq '^[0-9a-f]{64}$' /usr/local/lib/kubefoundry/helm.sha256 || { printf '[ERROR] Helm 受管标记无效\n' >&2; exit 20; }
timeout --foreground "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" /usr/local/bin/helm version --short >/dev/null 2>&1
status=$?
case "${status}" in
    0) printf '[SUCCESS] 受管 Helm 已就绪\n' ;;
    124|137) printf '[ERROR] 验证命令超时\n' >&2; exit 21 ;;
    *) printf '[ERROR] Helm 版本查询失败\n' >&2; exit 20 ;;
esac
