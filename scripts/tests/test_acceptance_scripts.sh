#!/bin/bash

set -o errexit -o nounset -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${PROJECT_ROOT}/scripts/acceptance/v032-cluster-readiness.sh"
FAILOVER="${PROJECT_ROOT}/scripts/acceptance/redis-sentinel-failover.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

bash -n "${SCRIPT}"
bash -n "${FAILOVER}"
grep -Fq 'KF_ACCEPT_REDIS_FAILOVER=YES' "${FAILOVER}"
! grep -Eq 'kubectl (delete|apply|create|patch)|helm (install|upgrade|uninstall)|systemctl (start|stop|restart|disable|enable)' "${SCRIPT}"

mkdir -p "${TEST_ROOT}/bin"
printf 'test kubeconfig\n' > "${TEST_ROOT}/kubeconfig"
cat > "${TEST_ROOT}/bin/kubectl" <<'EOF'
#!/bin/bash
case "$*" in
    'get --raw=/readyz') printf 'ok\n' ;;
    'get nodes --no-headers -o custom-columns=NAME:.metadata.name,INTERNAL_IP:.status.addresses[?(@.type=="InternalIP")].address,READY:.status.conditions[?(@.type=="Ready")].status')
        printf '%s\n' 'k8sc1 10.0.0.1 True' 'k8sw1 10.0.0.2 True'
        ;;
    'get pods --all-namespaces --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase')
        printf '%s\n' 'kube-system coredns-1 Running' 'default completed-job Succeeded'
        ;;
    *) printf 'unexpected kubectl arguments: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
chmod 0755 "${TEST_ROOT}/bin/kubectl"

output="$(PATH="${TEST_ROOT}/bin:${PATH}" KUBECONFIG="${TEST_ROOT}/kubeconfig" \
    KF_EXPECT_REDIS=0 KF_EXPECT_MINIO=0 KF_EXPECT_ETCD_BACKUP=0 bash "${SCRIPT}")"
grep -Fq '[SUCCESS] v0.3.2 集群只读验收预检通过' <<< "${output}"

sed -i 's/k8sw1 10.0.0.2 True/k8sw1 10.0.0.2 False/' "${TEST_ROOT}/bin/kubectl"
if PATH="${TEST_ROOT}/bin:${PATH}" KUBECONFIG="${TEST_ROOT}/kubeconfig" \
        KF_EXPECT_REDIS=0 KF_EXPECT_MINIO=0 KF_EXPECT_ETCD_BACKUP=0 \
        bash "${SCRIPT}" >/dev/null 2>&1; then
    printf '[FAIL] 未拒绝包含未 Ready 节点的动态验收环境\n' >&2
    exit 1
fi

printf '%s\n' '[PASS] 真实验收脚本只读保护和集群预检测试通过'
