#!/bin/bash

#===============================================================================
# 脚本名称：run_all.sh
# 功能：执行 KubeFoundry 全部确定性 Bash 单元与静态回归测试
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

set -o errexit -o nounset -o pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tests=(
    test_acceptance_scripts.sh
    test_containerd_root_config.sh
    test_environment_sysctl.sh
    test_etcd_backup.sh
    test_fixed_api_server_port.sh
    test_managed_config_ownership.sh
    test_package_frontend_isolation.sh
    test_phase2_coredns_affinity.sh
    test_phase3_common.sh
    test_phase3_kubemate.sh
    test_phase3_nfs.sh
    test_phase3_prometheus.sh
    test_phase3_storage_observability.sh
    test_phase3_traefik.sh
    test_redis_sentinel.sh
    test_reset_component_cleanup.sh
    test_verify_contract.sh
    test_web_package_deploy.sh
    test_yum_repo_permissions.sh
)

for test_script in "${tests[@]}"; do
    printf '[TEST] %s\n' "${test_script}"
    bash "${project_root}/scripts/tests/${test_script}"
done

printf '[SUCCESS] 全部 Bash 单元与静态回归测试通过（%s 项）\n' "${#tests[@]}"
