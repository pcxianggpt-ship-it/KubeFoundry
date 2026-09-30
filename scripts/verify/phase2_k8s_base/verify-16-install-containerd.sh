#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
[ -n "${KF_CONTAINERD_ROOT:-}" ] || { printf '[ERROR] 验证缺少运行参数: KF_CONTAINERD_ROOT\n' >&2; exit 20; }
command -v systemctl >/dev/null 2>&1 || { printf '[ERROR] 验证工具不可用: systemctl\n' >&2; exit 20; }
systemctl is-active --quiet containerd || missing "containerd 未运行"
for tool in runc nerdctl; do
    command -v "${tool}" >/dev/null 2>&1 || missing "容器运行时工具未安装: ${tool}"
done
grep -Eq '^[[:space:]]*root[[:space:]]*=[[:space:]]*"'"${KF_CONTAINERD_ROOT}"'"' /etc/containerd/config.toml 2>/dev/null || missing "containerd 数据目录不匹配"
[ -n "${KF_REGISTRY_IP:-}" ] || { printf '[ERROR] 验证缺少运行参数: KF_REGISTRY_IP\n' >&2; exit 20; }
for registry_config in \
    "/etc/containerd/certs.d/${KF_REGISTRY_IP}:5000/hosts.toml" \
    /etc/containerd/certs.d/registry:5000/hosts.toml; do
    [ -f "${registry_config}" ] || missing "containerd Registry 配置不存在: ${registry_config}"
    grep -Fqx '# Managed by KubeFoundry v0.3.2' "${registry_config}" || \
        missing "containerd Registry 受管标记缺失: ${registry_config}"
done
manifest=/var/lib/kubefoundry/managed-config/manifest.tsv
[ -f "${manifest}" ] || missing "containerd 配置基线清单不存在"
[ "$(stat -c '%a' "${manifest}" 2>/dev/null)" = 600 ] || missing "containerd 配置基线清单权限不安全"
grep -Fq $'containerd.config\t/etc/containerd/config.toml\t' "${manifest}" || \
    missing "containerd 配置基线记录缺失"
grep -Fq $'containerd.service\t/etc/systemd/system/containerd.service\t' "${manifest}" || \
    missing "containerd service 基线记录缺失"
grep -Fq $'buildkit.service\t/etc/systemd/system/buildkit.service\t' "${manifest}" || \
    missing "buildkit service 基线记录缺失"
printf '[SUCCESS] containerd 及受管数据目录已就绪\n'
