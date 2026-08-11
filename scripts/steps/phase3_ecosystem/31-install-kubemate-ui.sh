#!/bin/bash

#===============================================================================
# 脚本名称：31-install-kubemate-ui.sh
# 功能：在主控节点安装 Kubemate 管理组件
# 作者：KubeFoundry Team
# 版本：0.3.1
#===============================================================================

if [ -f "./phase3.sh" ]; then source "./phase3.sh"; else source "${PROJECT_ROOT}/scripts/lib/phase3.sh"; fi
phase3_init
: "${KF_PRIMARY_CONTROL_IP:?缺少主控制节点地址}"

kubemate_namespace="${KF_KUBEMATE_NAMESPACE:-kubemate-system}"
resource_dir=$(phase3_resource_path .)
crd_manifest="${resource_dir}/kubemate-crds.yml"
resource_manifest="${resource_dir}/kubemate-resources.yml"

[ -f "${KUBECONFIG}" ] || {
    log_error "Kubernetes 管理配置不存在: ${KUBECONFIG}"
    exit 1
}
[ -f "${resource_manifest}" ] || {
    log_error "Kubemate 资源清单不存在: ${resource_manifest}"
    exit 1
}
[ -f "${crd_manifest}" ] || {
    log_error "Kubemate CRD 清单不存在: ${crd_manifest}"
    exit 1
}

# 1. 使用管理节点 kubeconfig 创建 Kubemate ConfigMap。
kubectl create configmap kubemate-etc --namespace "${kubemate_namespace}" \
    --from-file=k8s_config.yml="${KUBECONFIG}"

# 2. 仅修改任务资源副本中 kubemate-appx Deployment 的 hostAliases IP。
rendered=$(mktemp "${resource_manifest}.XXXXXX")
trap 'rm -f -- "${rendered}"' EXIT
if ! awk -v control_ip="${KF_PRIMARY_CONTROL_IP}" '
    /^---[[:space:]]*($|#)/ {
        target_deployment = 0
        host_aliases = 0
    }
    /^[[:space:]]*name:[[:space:]]*kubemate-appx[[:space:]]*$/ {
        target_deployment = 1
    }
    target_deployment && /^[[:space:]]*hostAliases:[[:space:]]*$/ {
        host_aliases = 1
    }
    target_deployment && host_aliases && /^[[:space:]]*-[[:space:]]*ip:[[:space:]]*/ && !replaced {
        sub(/ip:[[:space:]]*.*/, "ip: " control_ip)
        replaced = 1
    }
    { print }
    END { if (!replaced) exit 42 }
' "${resource_manifest}" > "${rendered}"; then
    log_error "未找到 kubemate-appx Deployment 的 hostAliases IP 配置"
    exit 1
fi
mv -- "${rendered}" "${resource_manifest}"

# 3. 先安装并等待 CRD 可用，再部署依赖这些 CRD 的 Kubemate 资源。
kubectl apply -f "${crd_manifest}"
crd_resources=$(kubectl get -f "${crd_manifest}" -o name)
[ -n "${crd_resources}" ] || {
    log_error "Kubemate CRD 清单未生成可等待资源"
    exit 1
}
while IFS= read -r crd_resource; do
    [ -z "${crd_resource}" ] || kubectl wait --for=condition=Established "${crd_resource}" \
        --timeout "${KF_CRD_TIMEOUT:-180s}"
done <<< "${crd_resources}"
kubectl apply -f "${resource_manifest}"

log_success "Kubemate 管理组件安装命令执行完成"
