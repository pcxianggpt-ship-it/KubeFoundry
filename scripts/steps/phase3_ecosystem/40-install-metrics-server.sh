#!/bin/bash

#===============================================================================
# 脚本名称：40-install-metrics-server.sh
# 功能：在 Prometheus 组内幂等安装并验证 Metrics Server
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
resource_dir=$(phase3_resource_path .)
find "${resource_dir}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 \
    | sort -z \
    | while IFS= read -r -d '' manifest; do
        kubectl apply --server-side --field-manager=kubefoundry -f "${manifest}"
    done
phase3_wait_rollout deployment metrics-server kube-system
kubectl top nodes --no-headers >/dev/null
log_success "Metrics Server 已幂等安装，kubectl top nodes 可用"
