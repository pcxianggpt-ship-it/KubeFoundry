#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXEC_SCRIPT="${PROJECT_ROOT}/scripts/lib/exec_script.sh"
INSTALL_SCRIPT="${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/16-install-containerd.sh"

grep -Fq "_inj_containerd_root=\$(config_resolve '.env.containerd_root'" "${EXEC_SCRIPT}"
grep -Fq 'export CONTAINERD_ROOT="${_inj_containerd_root}"' "${EXEC_SCRIPT}"
grep -Fq '.env.containerd_root)  echo "${_inj_containerd_root}"' "${EXEC_SCRIPT}"
grep -Fq '缺少环境变量 CONTAINERD_ROOT' "${INSTALL_SCRIPT}"
grep -Fq 'mkdir -p "${CONTAINERD_ROOT}"' "${INSTALL_SCRIPT}"
grep -Fq "grep -Eq '^[[:space:]]*root[[:space:]]*=' /etc/containerd/config.toml" "${INSTALL_SCRIPT}"
grep -Fq 'sed -i -E "0,/^[[:space:]]*root[[:space:]]*=/s|^[[:space:]]*root[[:space:]]*=.*$|root = \"${CONTAINERD_ROOT}\"|" /etc/containerd/config.toml' "${INSTALL_SCRIPT}"

echo "containerd 数据目录配置测试通过"
