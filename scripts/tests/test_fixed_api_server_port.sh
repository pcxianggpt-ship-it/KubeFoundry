#!/bin/bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

if grep -R -n -E 'network\.api_server_port|KF_API_SERVER_PORT|API_SERVER_PORT' \
    "${PROJECT_ROOT}/scripts/lib" \
    "${PROJECT_ROOT}/scripts/steps" \
    "${PROJECT_ROOT}/scripts/verify" \
    "${PROJECT_ROOT}/config/cluster.yaml"; then
    echo "发现 API Server 端口变量配置链路" >&2
    exit 1
fi

grep -q 'bindPort: 6443' \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/18-init-k8s-cluster.sh"
grep -q 'controlPlaneEndpoint: "${local_hostname}:6443"' \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/18-init-k8s-cluster.sh"

echo "API Server 固定端口测试通过"
