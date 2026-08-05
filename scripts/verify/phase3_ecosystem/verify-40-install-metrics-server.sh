#!/bin/bash

#===============================================================================
# 脚本名称：verify-40-install-metrics-server.sh
# 功能：验证 Metrics Server 和 kubectl top
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
kubectl wait --for=condition=available deployment/metrics-server --namespace kube-system \
    --timeout "${KF_ROLLOUT_TIMEOUT:-10m}"
kubectl top nodes --no-headers >/dev/null
log_success "Metrics Server 和 kubectl top nodes 验证通过"
