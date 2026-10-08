#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
BIN="${TMP}/bin"
mkdir -p "${BIN}"
cat > "${BIN}/yq" <<'EOF'
#!/bin/bash
printf 'MinIO 安装不应调用 yq\n' >&2
exit 127
EOF
cat > "${BIN}/helm" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_STORAGE_HELM_LOG}"
if [ "${1:-}" = "upgrade" ] && [ "${2:-}" = "--install" ] && [ "${3:-}" = "openebs" ]; then
    path_values="${!#}"
    grep -q "basePath: \"${KF_K8S_HOME}/openebs-root\"" "${path_values}" || exit 1
fi
exit 0
EOF
cat > "${BIN}/curl" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "${BIN}/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_STORAGE_KUBECTL_LOG}"
if [ "${1:-}" = get ] && [ "${2:-}" = pods ] && [ -n "${KF_STORAGE_POD_MODE:-}" ]; then
    case "${KF_STORAGE_POD_MODE}" in
        large)
            printf '%s-pod 1/1 Running 0 1m\n' "${KF_STORAGE_MOCK_GROUP}"
            for ((index=0; index<4000; index++)); do
                printf 'unrelated-workload-%04d 1/1 Running 0 1m\n' "${index}"
            done
            ;;
        missing) printf 'unrelated-pod 1/1 Running 0 1m\n' ;;
        query_failed)
            printf '%s-pod 1/1 Running 0 1m\n' "${KF_STORAGE_MOCK_GROUP}"
            exit 1
            ;;
    esac
    exit 0
fi
if [ "${1:-}" = apply ] && [ "${2:-}" = -k ]; then
    cp "${3}/minio-resources-patch.yaml" "${KF_STORAGE_MINIO_PATCH}"
    cp "${3}/tenant.yaml" "${KF_STORAGE_MINIO_SOURCE}"
    printf '%s\n' "$3" > "${KF_STORAGE_MINIO_RENDER_DIR}"
    if [ -n "${KF_STORAGE_KUSTOMIZE_BIN:-}" ]; then
        "${KF_STORAGE_KUSTOMIZE_BIN}" kustomize "$3" > "${KF_STORAGE_MINIO_RENDERED}"
    fi
    [ "${KF_STORAGE_MINIO_APPLY_EXIT:-0}" -eq 0 ] || exit "${KF_STORAGE_MINIO_APPLY_EXIT}"
fi
case "$*" in
  *"get nodes"*) printf 'worker-a Ready worker 1m v1.30.14\nworker-b Ready worker 1m v1.30.14\nworker-c Ready worker 1m v1.30.14\nworker-d Ready worker 1m v1.30.14\n' ;;
  *"get --raw=/readyz"*) printf 'ok\n' ;;
  *"rollout status deployment/minio-operator"*) printf 'deployment successfully rolled out\n' ;;
  *"get tenant kubemate-minio"*"status.currentState"*) printf 'Initialized' ;;
  *"get tenant kubemate-minio"*"spec.pools"*) printf '20Gi|500m|3|1Gi|6Gi' ;;
  *"get pods -n kubemate-system -l v1.min.io/tenant=kubemate-minio"*"--no-headers"*) printf 'minio-0 1/1 Running\nminio-1 1/1 Running\nminio-2 1/1 Running\nminio-3 1/1 Running\n' ;;
  *"get pods -n kubemate-system -l v1.min.io/tenant=kubemate-minio"*"jsonpath"*) printf '500m|3|1Gi|6Gi\n500m|3|1Gi|6Gi\n500m|3|1Gi|6Gi\n500m|3|1Gi|6Gi\n' ;;
  *"get pvc -n kubemate-system -l v1.min.io/tenant=kubemate-minio"*"--no-headers"*) printf 'data-0 Bound pv-0 20Gi RWO openebs-hostpath\ndata-1 Bound pv-1 20Gi RWO openebs-hostpath\ndata-2 Bound pv-2 20Gi RWO openebs-hostpath\ndata-3 Bound pv-3 20Gi RWO openebs-hostpath\n' ;;
  *"get pvc -n kubemate-system -l v1.min.io/tenant=kubemate-minio"*"jsonpath"*) printf '20Gi\n20Gi\n20Gi\n20Gi\n' ;;
  *"get service kubemate-minio-hl"*) printf 'service/kubemate-minio-hl\n' ;;
  *"get secret kubemate-minio-env"*) printf 'export MINIO_ROOT_USER="test-user"\nexport MINIO_ROOT_PASSWORD="test-password"\n' ;;
  *"get pvc --selector v1.min.io/tenant=kubemate-minio"*) printf 'data-0 Bound pv-0 1Gi RWO openebs-hostpath\ndata-1 Bound pv-1 1Gi RWO openebs-hostpath\ndata-2 Bound pv-2 1Gi RWO openebs-hostpath\ndata-3 Bound pv-3 1Gi RWO openebs-hostpath\n' ;;
  *"get pods --selector v1.min.io/tenant=kubemate-minio"*) printf 'minio-0 1/1 Running\nminio-1 1/1 Running\nminio-2 1/1 Running\nminio-3 1/1 Running\n' ;;
  *"get deployment"*) printf '%s\n' "${KF_STORAGE_MOCK_GROUP}-controller" ;;
  *"get pods"*) printf '%s\n' "${KF_STORAGE_MOCK_GROUP}-pod 1/1 Running" ;;
  *) : ;;
esac
for argument in "$@"; do
  if [ -f "${argument}" ] && grep -q 'name: BasePath' "${argument}"; then
    grep -Fq "value: ${KF_STORAGE_EXPECTED_BASE_PATH:-${KF_K8S_HOME}/openebs-root}" "${argument}" || exit 1
    ! grep -q '__KUBERNETES_WORK_DIR__' "${argument}" || exit 1
    cp "${argument}" "${KF_STORAGE_APPLIED_CLASS}"
  fi
done
exit 0
EOF
chmod +x "${BIN}"/*
export PATH="${BIN}:${PATH}"
export PROJECT_ROOT="${ROOT}"
export KF_STORAGE_HELM_LOG="${TMP}/helm.log"
export KF_STORAGE_KUBECTL_LOG="${TMP}/kubectl.log"
export KF_STORAGE_APPLIED_CLASS="${TMP}/applied-storage-class.yaml"
export KF_STORAGE_MINIO_PATCH="${TMP}/minio-resources-patch.yaml"
export KF_STORAGE_MINIO_SOURCE="${TMP}/original-minio-tenant.yaml"
export KF_STORAGE_MINIO_RENDER_DIR="${TMP}/minio-render-dir.txt"
export KF_STORAGE_MINIO_RENDERED="${TMP}/rendered-minio-tenant.yaml"
export KF_COMPONENT_RESOURCE_DIR="${TMP}/resources"
export KF_ROLLOUT_TIMEOUT=1s
export KF_NODE_HOSTNAME=cp-a
export KF_NODE_IP=10.0.0.1
export KF_NODE_ROLE=control_plane
export KF_K8S_HOME="${TMP}/k8s-work"
unset KF_OPENEBS_RELEASE_EXISTS || true
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "$*" >&2; }
export -f log_info log_success log_warn log_error

run_group() {
    local group="$1" script="$2"
    rm -rf "${KF_COMPONENT_RESOURCE_DIR}"
    mkdir -p "${KF_COMPONENT_RESOURCE_DIR}"
    export KF_STORAGE_MOCK_GROUP="${group}"
    export KF_COMPONENT_GROUP_KEY=storage_observability
    case "${group}" in
        openebs)
            printf 'chart' > "${KF_COMPONENT_RESOURCE_DIR}/openebs-4.2.0.tgz"
            printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/openebs-values.yaml"
            cp "${ROOT}/kube-media/03.setup_file/v1.30.14/helmapp/openebs/openebssc.yaml" \
                "${KF_COMPONENT_RESOURCE_DIR}/openebssc.yaml"
            ;;
        minio)
            printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: minio-operator\n' > "${KF_COMPONENT_RESOURCE_DIR}/minio-operator.yaml"
            cp "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/kustomization.yaml" \
                "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml" "${KF_COMPONENT_RESOURCE_DIR}/"
            printf 'export MINIO_ROOT_USER="test-user"\nexport MINIO_ROOT_PASSWORD="test-password"\n' > "${KF_COMPONENT_RESOURCE_DIR}/tenant.env"
            ;;
        loki) printf 'chart' > "${KF_COMPONENT_RESOURCE_DIR}/loki-5.45.0.tgz"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/values.yaml" ;;
        alloy) printf 'chart' > "${KF_COMPONENT_RESOURCE_DIR}/alloy-1.4.0.tgz"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/alloy.config"; printf '{}' > "${KF_COMPONENT_RESOURCE_DIR}/alloy-values.yaml" ;;
    esac
    bash "${ROOT}/scripts/steps/phase3_ecosystem/${script}" || return $?
    if [ "${group}" = minio ]; then
        cmp "${KF_COMPONENT_RESOURCE_DIR}/tenant.yaml" "${KF_STORAGE_MINIO_SOURCE}"
        ! grep -q '^patches:' "${KF_COMPONENT_RESOURCE_DIR}/kustomization.yaml"
        [ ! -d "$(cat "${KF_STORAGE_MINIO_RENDER_DIR}")" ]
    fi
}

bash "${ROOT}/scripts/steps/phase3_ecosystem/46-prepare-storage-workers.sh"
for directory in openebs-root minio-root loki-root; do
    [ -d "${KF_K8S_HOME}/${directory}" ]
done
if KF_K8S_HOME="${TMP}/../unsafe" \
        bash "${ROOT}/scripts/steps/phase3_ecosystem/46-prepare-storage-workers.sh" >/dev/null 2>&1; then
    printf '不安全的 Kubernetes 工作目录未被拒绝\n' >&2
    exit 1
fi
run_group openebs 47-install-openebs.sh
export KF_OPENEBS_RELEASE_EXISTS=true
run_group openebs 47-install-openebs.sh
# 更换工作目录时，目录准备、StorageClass 和 Helm 路径必须同步变化。
original_work_dir="${KF_K8S_HOME}"
export KF_K8S_HOME="${TMP}/different-work"
bash "${ROOT}/scripts/steps/phase3_ecosystem/46-prepare-storage-workers.sh"
test -d "${KF_K8S_HOME}/openebs-root"
run_group openebs 47-install-openebs.sh
grep -Fq "value: ${KF_K8S_HOME}/openebs-root" "${KF_STORAGE_APPLIED_CLASS}"
export KF_K8S_HOME="${original_work_dir}"
# 已渲染的配置可重复安装，不要求恢复占位符，也不覆盖自定义存储路径。
cp "${ROOT}/kube-media/03.setup_file/v1.30.14/helmapp/openebs/openebssc.yaml" \
    "${KF_COMPONENT_RESOURCE_DIR}/openebssc.yaml"
export KF_STORAGE_EXPECTED_BASE_PATH="${TMP}/custom-openebs"
sed -i "s|__KUBERNETES_WORK_DIR__/openebs-root|${KF_STORAGE_EXPECTED_BASE_PATH}|g" \
    "${KF_COMPONENT_RESOURCE_DIR}/openebssc.yaml"
cp "${KF_COMPONENT_RESOURCE_DIR}/openebssc.yaml" "${TMP}/original-storage-class.yaml"
bash "${ROOT}/scripts/steps/phase3_ecosystem/47-install-openebs.sh"
bash "${ROOT}/scripts/steps/phase3_ecosystem/47-install-openebs.sh"
cmp "${TMP}/original-storage-class.yaml" "${KF_STORAGE_APPLIED_CLASS}"
grep -q '  name: localpath$' "${KF_STORAGE_APPLIED_CLASS}"
cmp "${TMP}/original-storage-class.yaml" "${KF_COMPONENT_RESOURCE_DIR}/openebssc.yaml"
unset KF_STORAGE_EXPECTED_BASE_PATH
unset KF_MINIO_PVC_SIZE KF_MINIO_CPU_REQUEST KF_MINIO_CPU_LIMIT \
    KF_MINIO_MEMORY_REQUEST KF_MINIO_MEMORY_LIMIT || true
run_group minio 49-install-minio.sh
if [ -n "${KF_STORAGE_KUSTOMIZE_BIN:-}" ]; then
    grep -q 'storage: 10Gi' "${KF_STORAGE_MINIO_RENDERED}"
    grep -q 'cpu: 250m' "${KF_STORAGE_MINIO_RENDERED}"
    grep -q 'cpu: "2"' "${KF_STORAGE_MINIO_RENDERED}"
    grep -q 'memory: 512Mi' "${KF_STORAGE_MINIO_RENDERED}"
    grep -q 'memory: 4Gi' "${KF_STORAGE_MINIO_RENDERED}"
    grep -q 'servers: 4' "${KF_STORAGE_MINIO_RENDERED}"
    grep -q 'kind: Secret' "${KF_STORAGE_MINIO_RENDERED}"
fi
export KF_MINIO_PVC_SIZE=20Gi KF_MINIO_CPU_REQUEST=500m KF_MINIO_CPU_LIMIT=3
export KF_MINIO_MEMORY_REQUEST=1Gi KF_MINIO_MEMORY_LIMIT=6Gi
openebs_install_count=$(grep -c '^upgrade --install openebs ' "${KF_STORAGE_HELM_LOG}")
run_group minio 49-install-minio.sh
# 重复安装仍从原介质生成补丁，且无需可用的 yq。
bash "${ROOT}/scripts/steps/phase3_ecosystem/49-install-minio.sh"
[ ! -d "$(cat "${KF_STORAGE_MINIO_RENDER_DIR}")" ]
cmp "${KF_COMPONENT_RESOURCE_DIR}/tenant.yaml" "${KF_STORAGE_MINIO_SOURCE}"
if KF_STORAGE_MINIO_APPLY_EXIT=1 bash "${ROOT}/scripts/steps/phase3_ecosystem/49-install-minio.sh" \
        >/dev/null 2>&1; then
    printf 'MinIO apply 失败未正确返回\n' >&2
    exit 1
fi
[ ! -d "$(cat "${KF_STORAGE_MINIO_RENDER_DIR}")" ]
[ "$(grep -c '^upgrade --install openebs ' "${KF_STORAGE_HELM_LOG}")" -eq "${openebs_install_count}" ]
touch "${TMP}/admin.conf"
KF_KUBECONFIG="${TMP}/admin.conf" bash "${ROOT}/scripts/verify/phase3_ecosystem/verify-49-install-minio.sh"
run_group loki 35-install-loki.sh
run_group alloy 48-install-alloy.sh

# Pod 已启动且匹配项在长列表开头时，不得因下游提前关闭管道而误判。
for group in loki alloy; do
    if [ "${group}" = loki ]; then script=35-install-loki.sh; else script=48-install-alloy.sh; fi
    export KF_STORAGE_POD_MODE=large
    run_group "${group}" "${script}"
    # 不存在对应 Pod 或查询失败（即使输出中有匹配项）仍应拒绝成功。
    for mode in missing query_failed; do
        export KF_STORAGE_POD_MODE="${mode}"
        if run_group "${group}" "${script}" > "${TMP}/pod-check-output" 2>&1; then
            printf '%s 在 %s 情况下错误报告成功\n' "${group}" "${mode}" >&2
            exit 1
        fi
        grep -q '工作负载未就绪' "${TMP}/pod-check-output"
    done
done
unset KF_STORAGE_POD_MODE
grep -q -- '^upgrade --install openebs .*openebs-4.2.0.tgz --namespace kubemate-system .*--labels app.kubernetes.io/managed-by=kubefoundry,kubefoundry.io/component-group=openebs.*-f .*openebs-values.yaml -f /tmp/' "${KF_STORAGE_HELM_LOG}" || {
    printf 'OpenEBS Helm 调用不符合预期:\n' >&2
    cat "${KF_STORAGE_HELM_LOG}" >&2
    exit 1
}
[ "$(grep -c -- '^upgrade --install openebs ' "${KF_STORAGE_HELM_LOG}")" -eq 5 ]
grep -q -- 'loki-5.45.0.tgz.*-f .*values.yaml -f /tmp/' "${KF_STORAGE_HELM_LOG}"
grep -q -- '--set read.replicas=3 --set write.replicas=3 --set backend.replicas=3 --set loki.commonConfig.replication_factor=3 --set sidecar.image.repository=registry:5000/ghcr.io/kiwigrid/k8s-sidecar --set loki.storage.s3.endpoint=kubemate-minio-hl:9000' "${KF_STORAGE_HELM_LOG}"
grep -q -- '--set memberlist.service.publishNotReadyAddresses=true' "${KF_STORAGE_HELM_LOG}"
grep -q -- 'alloy-1.4.0.tgz.*-f .*alloy-values.yaml' "${KF_STORAGE_HELM_LOG}"
grep -q -- 'apply --server-side --field-manager=kubefoundry --force-conflicts -f /tmp/' "${KF_STORAGE_KUBECTL_LOG}"
grep -q -- 'apply -k .*/tenant' "${KF_STORAGE_KUBECTL_LOG}"
grep -q -- 'label --overwrite -k .*/tenant app.kubernetes.io/managed-by=kubefoundry kubefoundry.io/component-group=storage_observability' \
    "${KF_STORAGE_KUBECTL_LOG}"
grep -q -- 'label nodes worker-a worker-b worker-c worker-d kubefoundry.io/minio=true --overwrite' "${KF_STORAGE_KUBECTL_LOG}"
grep -q -- "wait --for=jsonpath={.status.currentState}=Initialized tenant/kubemate-minio --namespace kubemate-system --timeout 10m" "${KF_STORAGE_KUBECTL_LOG}"
grep -A1 '/requests/storage$' "${KF_STORAGE_MINIO_PATCH}" | grep -q 'value: "20Gi"'
grep -A1 '/requests/cpu$' "${KF_STORAGE_MINIO_PATCH}" | grep -q 'value: "500m"'
grep -A1 '/limits/cpu$' "${KF_STORAGE_MINIO_PATCH}" | grep -q 'value: "3"'
grep -A1 '/requests/memory$' "${KF_STORAGE_MINIO_PATCH}" | grep -q 'value: "1Gi"'
grep -A1 '/limits/memory$' "${KF_STORAGE_MINIO_PATCH}" | grep -q 'value: "6Gi"'
! grep -Eq 'test-password|MINIO_ROOT_PASSWORD' "${KF_STORAGE_MINIO_PATCH}"
if [ -n "${KF_STORAGE_KUSTOMIZE_BIN:-}" ]; then
    grep -q 'storage: 20Gi' "${KF_STORAGE_MINIO_RENDERED}"
    grep -q 'cpu: 500m' "${KF_STORAGE_MINIO_RENDERED}"
    grep -Eq 'cpu: "?3"?' "${KF_STORAGE_MINIO_RENDERED}"
    grep -q 'memory: 1Gi' "${KF_STORAGE_MINIO_RENDERED}"
    grep -q 'memory: 6Gi' "${KF_STORAGE_MINIO_RENDERED}"
fi
! grep -Eq 'ssh_exec|config_get|get_all_' "${ROOT}/scripts/steps/phase3_ecosystem/47-install-openebs.sh" "${ROOT}/scripts/steps/phase3_ecosystem/49-install-minio.sh" "${ROOT}/scripts/steps/phase3_ecosystem/35-install-loki.sh" "${ROOT}/scripts/steps/phase3_ecosystem/48-install-alloy.sh"
! grep -Eq -- '--dry-run' "${ROOT}/scripts/steps/phase3_ecosystem/47-install-openebs.sh" "${ROOT}/scripts/steps/phase3_ecosystem/35-install-loki.sh" "${ROOT}/scripts/steps/phase3_ecosystem/48-install-alloy.sh"
grep -q 'application/vnd.oci.image.index.v1+json' "${ROOT}/scripts/lib/phase3.sh"
grep -q 'storageclass.kubernetes.io/is-default-class: "false"' "${ROOT}/kube-media/03.setup_file/v1.30.14/helmapp/openebs/openebssc.yaml"
grep -q 'value: __KUBERNETES_WORK_DIR__/openebs-root' "${ROOT}/kube-media/03.setup_file/v1.30.14/helmapp/openebs/openebssc.yaml"
for file in minio-operator.yaml kustomization.yaml tenant.yaml; do
    [ -s "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/${file}" ]
done
grep -Fqx 'kube-media/**/minio/tenant.env' "${ROOT}/.gitignore"
grep -q 'storage: 10Gi' "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
grep -q 'cpu: 250m' "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
grep -q 'memory: 512Mi' "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
grep -q 'cpu: "2"' "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
grep -q 'memory: 4Gi' "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
! grep -Eq '(^|[/:])minio/kes([:@]|$)|^[[:space:]]+kes:' \
    "${ROOT}/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml"
printf 'phase3 storage observability tests passed\n'
