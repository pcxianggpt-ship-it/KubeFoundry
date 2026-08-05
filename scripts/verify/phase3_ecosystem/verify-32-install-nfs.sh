#!/bin/bash

#===============================================================================
# 脚本名称：verify-32-install-nfs.sh
# 功能：在当前目标节点验证 NFS Provisioner
# 版本：0.3.0
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
PASS=0
FAIL=0
check_pass() { PASS=$((PASS + 1)); log_success "[PASS] $1"; }
check_fail() { FAIL=$((FAIL + 1)); log_error "[FAIL] $1"; }

systemctl is-active --quiet nfs-server && check_pass "nfs-server 运行中" || check_fail "nfs-server 未运行"
command -v helm >/dev/null 2>&1 && check_pass "Helm 已安装" || check_fail "Helm 未安装"
kubectl get deployment nfs-subdir-external-provisioner -n kubemate-system >/dev/null 2>&1 \
    && check_pass "NFS Provisioner Deployment 存在" || check_fail "NFS Provisioner Deployment 不存在"

if [ "${FAIL}" -eq 0 ]; then
    log_success "NFS 验证通过"
    exit 0
fi
log_error "NFS 验证失败: ${FAIL} 项"
exit 1
