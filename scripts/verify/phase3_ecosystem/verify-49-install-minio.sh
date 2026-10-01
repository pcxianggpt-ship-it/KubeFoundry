#!/bin/bash

set -o nounset -o pipefail

missing() { printf '[INFO] %s\n' "$1"; exit 10; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 20; }
kube() {
    local duration="$1"; shift
    timeout --foreground "${duration}" env KUBECONFIG="${KF_KUBECONFIG}" kubectl --request-timeout="${duration}" "$@"
    local status=$?
    case "${status}" in 124|137) return 21 ;; esac
    return "${status}"
}
check_status() { [ "$1" -ne 21 ] || { printf '[ERROR] Kubernetes API 验证超时\n' >&2; exit 21; }; }
quantity_value() {
    printf '%s\n' "$1" | awk -v kind="$2" '
      {
        text = $0; factor = 1
        if (kind == "cpu" && text ~ /m$/) { sub(/m$/, "", text); factor = 0.001 }
        if (kind == "bytes") {
          split("Ki Mi Gi Ti Pi Ei", units, " ")
          for (i = 1; i <= 6; i++) if (text ~ (units[i] "$") ) {
            sub(units[i] "$", "", text); factor = 1024 ^ i
          }
        }
        if (text !~ /^[0-9]+([.][0-9]+)?$/) next
        printf "%.9g", (text + 0) * factor
      }'
}
quantity_matches() {
    [ -n "$1" ] && [ -n "$2" ] &&
        [ "$(quantity_value "$1" "$3")" = "$(quantity_value "$2" "$3")" ]
}
all_lines_match() {
    local expected result
    expected=$(quantity_value "$2" "$3")
    [ -n "${expected}" ] || return 1
    result=$(printf '%s\n' "$1" | awk -v expected="${expected}" -v kind="$3" '
      function normalized(text, type, units, i, factor) {
        factor = 1
        if (type == "cpu" && text ~ /m$/) { sub(/m$/, "", text); factor = 0.001 }
        if (type == "bytes") {
          split("Ki Mi Gi Ti Pi Ei", units, " ")
          for (i = 1; i <= 6; i++) if (text ~ (units[i] "$") ) {
            sub(units[i] "$", "", text); factor = 1024 ^ i
          }
        }
        if (text !~ /^[0-9]+([.][0-9]+)?$/) return "invalid"
        return sprintf("%.9g", (text + 0) * factor)
      }
      NF { count++; if (normalized($0, kind) != expected) bad = 1 }
      END { if (count == 4 && !bad) print "match" }')
    [ "${result}" = match ]
}

[ -n "${KF_KUBECONFIG:-}" ] && [ -r "${KF_KUBECONFIG}" ] || error "Kubernetes 管理配置不可读"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get --raw=/readyz >/dev/null 2>&1; status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || error "Kubernetes API 验证异常"
kube "${KF_VERIFY_ROLLOUT_TIMEOUT:-300s}" rollout status deployment/minio-operator --namespace kubemate-system --timeout="${KF_VERIFY_ROLLOUT_TIMEOUT:-300s}" >/dev/null 2>&1; status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || missing "MinIO Operator 未就绪"
state=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get tenant kubemate-minio -n kubemate-system -o jsonpath='{.status.currentState}' 2>/dev/null); status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || missing "MinIO Tenant 不存在"
[ "${state}" = Initialized ] || missing "MinIO Tenant 未初始化"
tenant_resources=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get tenant kubemate-minio -n kubemate-system -o jsonpath='{.spec.pools[0].volumeClaimTemplate.spec.resources.requests.storage}{"|"}{.spec.pools[0].resources.requests.cpu}{"|"}{.spec.pools[0].resources.limits.cpu}{"|"}{.spec.pools[0].resources.requests.memory}{"|"}{.spec.pools[0].resources.limits.memory}' 2>/dev/null); status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || error "MinIO Tenant 资源配置查询失败"
tenant_pvc=$(printf '%s' "${tenant_resources}" | cut -d'|' -f1)
tenant_cpu_request=$(printf '%s' "${tenant_resources}" | cut -d'|' -f2)
tenant_cpu_limit=$(printf '%s' "${tenant_resources}" | cut -d'|' -f3)
tenant_memory_request=$(printf '%s' "${tenant_resources}" | cut -d'|' -f4)
tenant_memory_limit=$(printf '%s' "${tenant_resources}" | cut -d'|' -f5)
quantity_matches "${tenant_pvc}" "${KF_MINIO_PVC_SIZE:-10Gi}" bytes || missing "MinIO Tenant PVC 容量与安装快照不一致"
quantity_matches "${tenant_cpu_request}" "${KF_MINIO_CPU_REQUEST:-250m}" cpu || missing "MinIO Tenant CPU request 与安装快照不一致"
quantity_matches "${tenant_cpu_limit}" "${KF_MINIO_CPU_LIMIT:-2}" cpu || missing "MinIO Tenant CPU limit 与安装快照不一致"
quantity_matches "${tenant_memory_request}" "${KF_MINIO_MEMORY_REQUEST:-512Mi}" bytes || missing "MinIO Tenant 内存 request 与安装快照不一致"
quantity_matches "${tenant_memory_limit}" "${KF_MINIO_MEMORY_LIMIT:-4Gi}" bytes || missing "MinIO Tenant 内存 limit 与安装快照不一致"
pods=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get pods -n kubemate-system -l v1.min.io/tenant=kubemate-minio --no-headers 2>/dev/null); status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || error "MinIO Pod 查询失败"
[ "$(printf '%s\n' "${pods}" | awk '$2 ~ /^[0-9]+\/[0-9]+$/ && $2 != "0/0" && $3 == "Running" { count++ } END { print count+0 }')" -eq 4 ] || missing "MinIO Tenant Pod 未全部就绪"
pod_resources=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get pods -n kubemate-system -l v1.min.io/tenant=kubemate-minio -o jsonpath='{range .items[*].spec.containers[?(@.name=="minio")]}{.resources.requests.cpu}{"|"}{.resources.limits.cpu}{"|"}{.resources.requests.memory}{"|"}{.resources.limits.memory}{"\n"}{end}' 2>/dev/null); status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || error "MinIO Pod 资源配置查询失败"
all_lines_match "$(printf '%s\n' "${pod_resources}" | cut -d'|' -f1)" "${KF_MINIO_CPU_REQUEST:-250m}" cpu || missing "MinIO Pod CPU request 与安装快照不一致"
all_lines_match "$(printf '%s\n' "${pod_resources}" | cut -d'|' -f2)" "${KF_MINIO_CPU_LIMIT:-2}" cpu || missing "MinIO Pod CPU limit 与安装快照不一致"
all_lines_match "$(printf '%s\n' "${pod_resources}" | cut -d'|' -f3)" "${KF_MINIO_MEMORY_REQUEST:-512Mi}" bytes || missing "MinIO Pod 内存 request 与安装快照不一致"
all_lines_match "$(printf '%s\n' "${pod_resources}" | cut -d'|' -f4)" "${KF_MINIO_MEMORY_LIMIT:-4Gi}" bytes || missing "MinIO Pod 内存 limit 与安装快照不一致"
pvcs=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get pvc -n kubemate-system -l v1.min.io/tenant=kubemate-minio --no-headers 2>/dev/null); status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || error "MinIO PVC 查询失败"
[ "$(printf '%s\n' "${pvcs}" | awk '$2 == "Bound" { count++ } END { print count+0 }')" -eq 4 ] || missing "MinIO Tenant PVC 未全部 Bound"
pvc_sizes=$(kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get pvc -n kubemate-system -l v1.min.io/tenant=kubemate-minio -o jsonpath='{range .items[*]}{.spec.resources.requests.storage}{"\n"}{end}' 2>/dev/null); status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || error "MinIO PVC 容量查询失败"
all_lines_match "${pvc_sizes}" "${KF_MINIO_PVC_SIZE:-10Gi}" bytes || missing "MinIO PVC 容量与安装快照不一致"
kube "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" get service kubemate-minio-hl -n kubemate-system >/dev/null 2>&1; status=$?; check_status "${status}"; [ "${status}" -eq 0 ] || missing "MinIO Headless Service 不存在"
printf '[SUCCESS] MinIO Operator、Tenant、Pod 和 PVC 已就绪\n'
