#!/bin/bash

#===============================================================================
# 脚本名称：verify.sh
# 功能：v0.3.2 安装步骤本地只读验证公共库
# 作者：KubeFoundry Team
# 版本：0.3.2
#===============================================================================

[ -n "${_KUBEFNDRY_VERIFY_LOADED:-}" ] && return 0
_KUBEFNDRY_VERIFY_LOADED=1

vf_satisfied() { log_success "$*"; exit 0; }
vf_missing() { log_info "$*"; exit 10; }
vf_error() { log_error "$*"; exit 20; }
vf_timeout() { log_error "$*"; exit 21; }

vf_require_runtime() {
    local name
    for name in "$@"; do
        [ -n "${!name:-}" ] || vf_error "验证缺少运行参数: ${name}"
    done
}

vf_require_tool() {
    command -v "$1" >/dev/null 2>&1 || vf_error "验证工具不可用: $1"
}

vf_run() {
    local duration="${1:-${KF_VERIFY_COMMAND_TIMEOUT:-30s}}"
    shift
    vf_require_tool timeout
    timeout --foreground "${duration}" "$@"
    local status=$?
    case "${status}" in
        124|137) vf_timeout "验证命令超时" ;;
    esac
    return "${status}"
}

VF_OUTPUT=""
vf_capture_run() {
    VF_OUTPUT=$(vf_run "$@")
    local status=$?
    [ "${status}" -ne 21 ] || vf_timeout "验证命令超时"
    return "${status}"
}

vf_systemctl_active() {
    vf_require_tool systemctl
    vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" systemctl is-active --quiet "$1"
}

vf_systemctl_enabled() {
    vf_require_tool systemctl
    vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" systemctl is-enabled --quiet "$1"
}

vf_kubectl() {
    vf_require_tool kubectl
    vf_require_runtime KF_KUBECONFIG
    [ -r "${KF_KUBECONFIG}" ] || vf_error "Kubernetes 管理配置不可读"
    vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" env KUBECONFIG="${KF_KUBECONFIG}" \
        kubectl --request-timeout="${KF_VERIFY_COMMAND_TIMEOUT:-30s}" "$@"
}

vf_capture_kubectl() {
    VF_OUTPUT=$(vf_kubectl "$@")
    local status=$?
    [ "${status}" -ne 21 ] || vf_timeout "Kubernetes API 验证超时"
    return "${status}"
}

vf_kube_api_ready() {
    vf_kubectl get --raw=/readyz >/dev/null 2>&1 || vf_error "Kubernetes API 验证异常"
}

vf_helm_release() {
    local release="$1" namespace="$2"
    vf_require_tool helm
    vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" env KUBECONFIG="${KF_KUBECONFIG}" \
        helm status "${release}" --namespace "${namespace}" >/dev/null 2>&1
}

vf_rollout() {
    local rollout_timeout="${KF_VERIFY_ROLLOUT_TIMEOUT:-180s}"
    vf_require_tool kubectl
    vf_require_runtime KF_KUBECONFIG
    [ -r "${KF_KUBECONFIG}" ] || vf_error "Kubernetes 管理配置不可读"
    vf_run "${rollout_timeout}" env KUBECONFIG="${KF_KUBECONFIG}" \
        kubectl --request-timeout="${rollout_timeout}" rollout status "$1/$2" --namespace "$3" \
        --timeout="${rollout_timeout}" >/dev/null 2>&1
}

vf_verify_base() {
    local key="$1" value container_cmd
    case "${key}" in
        10-setup-yum-source)
            local web_root="${KF_YUM_WEB_ROOT:-/var/www/html}"
            local repo_root="${web_root}/repo"
            local metadata_file="${repo_root}/repodata/repomd.xml"
            local repo_config="${KF_YUM_LOCAL_REPO_CONFIG:-/etc/yum.repos.d/k8s.repo}"
            local metadata_url="${KF_YUM_LOCAL_METADATA_URL:-http://127.0.0.1/repo/repodata/repomd.xml}"
            [ -r "${repo_config}" ] || vf_missing "Kubernetes YUM 源未配置"
            grep -qF '# Managed by KubeFoundry v0.3.2' "${repo_config}" \
                || vf_missing "Kubernetes YUM 源不是 KubeFoundry 受管配置"
            [ -f "${metadata_file}" ] || vf_missing "Kubernetes YUM 仓库元数据不存在"
            [ "$(stat -c '%a' "$(dirname "${web_root}")" 2>/dev/null)" = 777 ] \
                || vf_missing "Kubernetes YUM 仓库父目录权限不是 777"
            [ "$(stat -c '%a' "${web_root}" 2>/dev/null)" = 777 ] \
                || vf_missing "Kubernetes YUM Web 目录权限不是 777"
            [ -z "$(find "${repo_root}" ! -perm 0777 -print -quit 2>/dev/null)" ] \
                || vf_missing "Kubernetes YUM 仓库权限不是 777"
            vf_systemctl_active httpd || vf_missing "httpd 未运行"
            vf_systemctl_enabled httpd || vf_missing "httpd 未设为开机启动"
            vf_systemctl_active firewalld \
                && vf_missing "firewalld 仍处于运行状态"
            vf_systemctl_enabled firewalld \
                && vf_missing "firewalld 仍处于启用状态"
            vf_require_tool curl
            vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" curl --fail --silent --show-error \
                --max-time 10 --output /dev/null "${metadata_url}" \
                || vf_missing "本机访问 Kubernetes YUM 仓库未返回 HTTP 200"
            vf_require_tool yum
            vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" yum -q --disablerepo='*' \
                --enablerepo='k8s-yum' makecache >/dev/null 2>&1 \
                || vf_missing "Kubernetes 本地 YUM 仓库缓存创建失败"
            vf_satisfied "Kubernetes YUM 源已就绪"
            ;;
        11b-setup-hostname)
            vf_require_runtime KF_NODE_HOSTNAME KF_NODE_IP
            [ "$(hostname)" = "${KF_NODE_HOSTNAME}" ] || vf_missing "当前节点主机名未配置"
            grep -qF '# >>>KubeFoundry>>>' /etc/hosts 2>/dev/null \
                || vf_missing "/etc/hosts 受管块不存在"
            awk -v ip="${KF_NODE_IP}" -v host="${KF_NODE_HOSTNAME}" \
                '$1 == ip { for (i=2; i<=NF; i++) if ($i == host) found=1 } END { exit !found }' /etc/hosts \
                || vf_missing "当前节点 hosts 映射不完整"
            vf_satisfied "当前节点主机名和 hosts 已就绪"
            ;;
        12-setup-k8s-repo)
            local repo_config="${KF_YUM_HTTP_REPO_CONFIG:-/etc/yum.repos.d/k8s-http.repo}"
            local primary_hostname="${PRIMARY_CONTROL_HOSTNAME:-k8sc1}"
            local metadata_url="http://${primary_hostname}/repo/repodata/repomd.xml"
            [ -r "${repo_config}" ] || vf_missing "Kubernetes HTTP Repo 未配置"
            grep -qF '# Managed by KubeFoundry v0.3.2' "${repo_config}" \
                || vf_missing "Kubernetes HTTP Repo 不是 KubeFoundry 受管配置"
            grep -Eq '^enabled[[:space:]]*=[[:space:]]*1' "${repo_config}" \
                || vf_missing "Kubernetes HTTP Repo 未启用"
            grep -qF "baseurl=http://${primary_hostname}/repo" "${repo_config}" \
                || vf_missing "Kubernetes HTTP Repo 地址不匹配"
            vf_require_tool curl
            vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" curl --fail --silent --show-error \
                --max-time 10 --output /dev/null "${metadata_url}" \
                || vf_missing "远程访问 Kubernetes YUM 仓库未返回 HTTP 200"
            vf_require_tool yum
            vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" yum -q --disablerepo='*' \
                --enablerepo='k8s-repo' makecache >/dev/null 2>&1 \
                || vf_missing "Kubernetes HTTP YUM 仓库缓存创建失败"
            vf_satisfied "Kubernetes HTTP Repo 已就绪"
            ;;
        13-install-k8s-deps)
            for value in kubeadm kubectl kubelet crictl; do
                command -v "${value}" >/dev/null 2>&1 || vf_missing "Kubernetes 依赖未安装: ${value}"
            done
            vf_systemctl_enabled kubelet || vf_missing "kubelet 未设为开机启动"
            vf_satisfied "Kubernetes 依赖已安装"
            ;;
        14-replace-kubeadm)
            [ -x /usr/bin/kubeadm ] || vf_missing "受管 kubeadm 不可执行"
            [ -s /tmp/k8s/kubeadm_bak ] || vf_missing "kubeadm 原始备份不存在"
            vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" /usr/bin/kubeadm version -o short >/dev/null 2>&1 \
                || vf_error "kubeadm 版本查询失败"
            vf_satisfied "长证书 kubeadm 已就绪"
            ;;
        15-environment-config)
            [ -z "$(swapon --show --noheadings 2>/dev/null)" ] || vf_missing "swap 仍处于启用状态"
            [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = 1 ] || vf_missing "IPv4 转发未启用"
            [ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null)" = 1 ] \
                || vf_missing "桥接 iptables 转发未启用"
            grep -qw overlay /proc/modules 2>/dev/null || vf_missing "overlay 内核模块未加载"
            grep -qw br_netfilter /proc/modules 2>/dev/null || vf_missing "br_netfilter 内核模块未加载"
            vf_satisfied "当前节点 Kubernetes 环境参数已就绪"
            ;;
        16-install-containerd)
            vf_require_runtime KF_CONTAINERD_ROOT
            vf_systemctl_active containerd || vf_missing "containerd 未运行"
            for value in runc nerdctl; do
                command -v "${value}" >/dev/null 2>&1 || vf_missing "容器运行时工具未安装: ${value}"
            done
            grep -Eq '^[[:space:]]*root[[:space:]]*=[[:space:]]*"'"${KF_CONTAINERD_ROOT}"'"' \
                /etc/containerd/config.toml 2>/dev/null || vf_missing "containerd 数据目录不匹配"
            vf_satisfied "containerd 及受管数据目录已就绪"
            ;;
        17-install-registry)
            if command -v nerdctl >/dev/null 2>&1; then container_cmd=nerdctl
            elif command -v docker >/dev/null 2>&1; then container_cmd=docker
            else vf_error "无法验证 Registry：未找到容器运行时"; fi
            vf_capture_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" "${container_cmd}" inspect \
                --format '{{.State.Running}}' registry 2>/dev/null || vf_missing "Registry 容器不存在"
            value=${VF_OUTPUT}
            [ "${value}" = true ] || vf_missing "Registry 容器未运行"
            vf_capture_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" "${container_cmd}" inspect \
                --format '{{.State.Running}}' registry-ui-5080 2>/dev/null || vf_missing "Registry UI 容器不存在"
            value=${VF_OUTPUT}
            [ "${value}" = true ] || vf_missing "Registry UI 容器未运行"
            vf_require_tool curl
            vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" curl --fail --silent --show-error \
                "http://127.0.0.1:${KF_REGISTRY_PORT:-5000}/v2/" >/dev/null 2>&1 \
                || vf_error "Registry API 不可用"
            vf_satisfied "Registry 和 UI 已就绪"
            ;;
        18-init-k8s-cluster)
            vf_require_runtime KF_NODE_HOSTNAME
            [ -s /etc/kubernetes/admin.conf ] || vf_missing "Kubernetes 集群尚未初始化"
            for value in kube-apiserver kube-controller-manager kube-scheduler etcd; do
                [ -s "/etc/kubernetes/manifests/${value}.yaml" ] \
                    || vf_missing "Kubernetes 静态 Pod 清单不完整: ${value}"
            done
            vf_kube_api_ready
            vf_kubectl get node "${KF_NODE_HOSTNAME}" >/dev/null 2>&1 \
                || vf_missing "主控节点尚未注册"
            vf_satisfied "Kubernetes 集群已初始化"
            ;;
        19-modify-cert-expiry)
            grep -q -- '--cluster-signing-duration=867240h0m0s' \
                /etc/kubernetes/manifests/kube-controller-manager.yaml 2>/dev/null \
                || vf_missing "证书有效期参数未配置"
            vf_kube_api_ready
            vf_satisfied "Kubernetes 证书有效期参数已就绪"
            ;;
        20-add-control-nodes)
            vf_require_runtime KF_NODE_HOSTNAME
            [ -s /etc/kubernetes/admin.conf ] || vf_missing "当前控制节点尚未加入集群"
            vf_systemctl_active kubelet || vf_missing "kubelet 未运行"
            vf_kube_api_ready
            vf_kubectl get node "${KF_NODE_HOSTNAME}" >/dev/null 2>&1 \
                || vf_missing "当前控制节点未注册"
            vf_satisfied "当前控制节点已加入集群"
            ;;
        21-add-worker-nodes)
            [ -s /etc/kubernetes/kubelet.conf ] || vf_missing "当前 Worker 尚未加入集群"
            [ -s /var/lib/kubelet/kubeadm-flags.env ] || vf_missing "Worker kubeadm 参数不完整"
            vf_systemctl_active kubelet || vf_missing "kubelet 未运行"
            vf_satisfied "当前 Worker 已加入集群"
            ;;
        22-install-cni-flannel)
            vf_kube_api_ready
            vf_kubectl get namespace kube-flannel >/dev/null 2>&1 || vf_missing "Flannel 命名空间不存在"
            vf_rollout daemonset kube-flannel-ds kube-flannel || vf_missing "Flannel DaemonSet 未就绪"
            vf_rollout deployment coredns kube-system || vf_missing "CoreDNS 未就绪"
            vf_satisfied "Flannel 和 CoreDNS 已就绪"
            ;;
        23-configure-coredns-affinity)
            vf_kube_api_ready
            vf_capture_kubectl get deployment coredns -n kube-system \
                -o jsonpath='{.metadata.annotations.kubefoundry\.io/coredns-anti-affinity}' 2>/dev/null \
                || vf_missing "CoreDNS Deployment 不存在"
            value=${VF_OUTPUT}
            [ "${value}" = v2 ] || vf_missing "CoreDNS 反亲和标记未就绪"
            vf_rollout deployment coredns kube-system || vf_missing "CoreDNS 未就绪"
            vf_satisfied "CoreDNS 反亲和配置已就绪"
            ;;
        *) return 1 ;;
    esac
}

vf_verify_component() {
    local key="$1" value rows source
    case "${key}" in
        29-install-helm)
            [ -x /usr/local/bin/helm ] || vf_missing "受管 Helm 未安装"
            [ -r /usr/local/lib/kubefoundry/helm.sha256 ] || vf_missing "Helm 受管标记不存在"
            grep -Eq '^[0-9a-f]{64}$' /usr/local/lib/kubefoundry/helm.sha256 \
                || vf_error "Helm 受管标记无效"
            vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" /usr/local/bin/helm version --short >/dev/null 2>&1 \
                || vf_error "Helm 版本查询失败"
            vf_satisfied "受管 Helm 已就绪"
            ;;
        30-create-namespace)
            vf_kube_api_ready
            vf_capture_kubectl get namespace kubemate-system -o jsonpath='{.status.phase}' 2>/dev/null \
                || vf_missing "kubemate-system 命名空间不存在"
            value=${VF_OUTPUT}
            [ "${value}" = Active ] || vf_missing "kubemate-system 命名空间未就绪"
            vf_satisfied "kubemate-system 命名空间已就绪"
            ;;
        32-configure-nfs-exports)
            vf_require_runtime KF_NODE_IP KF_NFS_SERVER KF_NFS_SHARE_PATH KF_NFS_EXPORTS_MODE
            if [ "${KF_NFS_EXPORTS_MODE}" = managed ]; then
                [ "${KF_NODE_IP}" = "${KF_NFS_SERVER}" ] || vf_error "当前节点不是受管 NFS 服务节点"
                [ -d "${KF_NFS_SHARE_PATH}" ] || vf_missing "NFS 共享目录不存在"
                vf_systemctl_active nfs-server || vf_missing "nfs-server 未运行"
                grep -qF '# >>>KubeFoundry NFS exports>>>' "${KF_NFS_EXPORTS_FILE:-/etc/exports}" 2>/dev/null \
                    || vf_missing "NFS exports 受管块不存在"
            elif [ "${KF_NFS_EXPORTS_MODE}" = external ]; then
                vf_require_tool showmount
                vf_capture_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" showmount -e "${KF_NFS_SERVER}" 2>/dev/null \
                    || vf_error "外部 NFS 查询失败"
                rows=${VF_OUTPUT}
                printf '%s\n' "${rows}" | grep -Fq -- "${KF_NFS_SHARE_PATH}" \
                    || vf_missing "外部 NFS 共享目录不存在"
            else
                vf_error "NFS exports 模式无效"
            fi
            vf_satisfied "NFS exports 已就绪"
            ;;
        32-install-nfs)
            vf_kube_api_ready
            vf_helm_release nfs-subdir-external-provisioner kubemate-system \
                || vf_missing "NFS Provisioner Helm Release 不存在"
            vf_rollout deployment nfs-subdir-external-provisioner kubemate-system \
                || vf_missing "NFS Provisioner 未就绪"
            vf_kubectl get storageclass "${KF_NFS_STORAGE_CLASS:-nfs-client}" >/dev/null 2>&1 \
                || vf_missing "NFS StorageClass 不存在"
            vf_satisfied "NFS Provisioner 已就绪"
            ;;
        32-mount-nfs-workers)
            vf_require_runtime KF_NFS_SERVER KF_NFS_SHARE_PATH KF_NFS_WORKER_MOUNT_PATH
            if [ "${KF_NFS_EXPORTS_MODE:-}" = managed ] && [ "${KF_NODE_IP}" = "${KF_NFS_SERVER}" ]; then
                vf_satisfied "受管 NFS 服务节点无需自挂载"
            fi
            vf_require_tool findmnt
            vf_capture_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" findmnt -n -o SOURCE \
                --target "${KF_NFS_WORKER_MOUNT_PATH}" 2>/dev/null || vf_missing "NFS 工作节点挂载不存在"
            source=${VF_OUTPUT}
            [ "${source}" = "${KF_NFS_SERVER}:${KF_NFS_SHARE_PATH}" ] \
                || vf_missing "NFS 工作节点挂载来源不匹配"
            grep -qF '# >>>KubeFoundry NFS fstab>>>' "${KF_NFS_FSTAB_FILE:-/etc/fstab}" 2>/dev/null \
                || vf_missing "NFS fstab 受管块不存在"
            vf_satisfied "当前 Worker NFS 挂载已就绪"
            ;;
        46-prepare-storage-workers)
            vf_require_runtime KF_K8S_HOME
            for value in openebs-root minio-root loki-root; do
                [ -d "${KF_K8S_HOME}/${value}" ] && [ -w "${KF_K8S_HOME}/${value}" ] \
                    || vf_missing "Worker 存储目录未就绪: ${value}"
            done
            vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" df -P "${KF_K8S_HOME}" >/dev/null 2>&1 \
                || vf_error "Worker 存储文件系统查询失败"
            vf_satisfied "Worker 存储目录已就绪"
            ;;
        37-prepare-prometheus-workers)
            vf_require_runtime KF_K8S_HOME
            [ -d "${KF_K8S_HOME}/prom_data" ] && [ -w "${KF_K8S_HOME}/prom_data" ] \
                || vf_missing "Prometheus Worker 数据目录未就绪"
            vf_run "${KF_VERIFY_COMMAND_TIMEOUT:-30s}" df -P "${KF_K8S_HOME}/prom_data" >/dev/null 2>&1 \
                || vf_error "Prometheus 数据目录文件系统查询失败"
            vf_satisfied "Prometheus Worker 数据目录已就绪"
            ;;
        31-install-kubemate-ui)
            vf_kube_api_ready
            vf_kubectl get configmap kubemate-etc -n kubemate-system >/dev/null 2>&1 \
                || vf_missing "Kubemate ConfigMap 不存在"
            vf_kubectl get deployment kubemate-appx -n kubemate-system >/dev/null 2>&1 \
                || vf_missing "Kubemate Deployment 不存在"
            vf_rollout deployment kubemate-appx kubemate-system \
                || vf_missing "Kubemate Deployment 未就绪"
            vf_kubectl get service kubemate-app -n kubemate-system >/dev/null 2>&1 \
                || vf_missing "Kubemate Service 不存在"
            vf_satisfied "Kubemate 管理组件已就绪"
            ;;
        36-install-traefik)
            vf_kube_api_ready
            vf_capture_kubectl get daemonset -A \
                -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,DESIRED:.status.desiredNumberScheduled,READY:.status.numberReady' \
                --no-headers 2>/dev/null || vf_error "Traefik DaemonSet 查询失败"
            rows=${VF_OUTPUT}
            printf '%s\n' "${rows}" | awk '$2 ~ /^traefik($|-)/ && $3 > 0 && $4 == $3 { found=1 } END { exit !found }' \
                || vf_missing "Traefik DaemonSet 未就绪"
            while read -r namespace name desired ready; do
                [ -n "${namespace}" ] || continue
                case "${name}" in
                    traefik|traefik-*) vf_rollout daemonset "${name}" "${namespace}" \
                        || vf_missing "Traefik DaemonSet 未就绪" ;;
                esac
            done <<< "${rows}"
            vf_capture_kubectl get service -A --no-headers 2>/dev/null \
                || vf_error "Traefik Service 查询失败"
            rows=${VF_OUTPUT}
            printf '%s\n' "${rows}" | awk '$2 ~ /^traefik($|-)/ { found=1 } END { exit !found }' \
                || vf_missing "Traefik Service 不存在"
            vf_satisfied "Traefik 网关资源已就绪"
            ;;
        47-install-openebs)
            vf_kube_api_ready
            vf_helm_release openebs kubemate-system || vf_missing "OpenEBS Helm Release 不存在"
            vf_kubectl get storageclass openebs-hostpath >/dev/null 2>&1 \
                || vf_missing "OpenEBS StorageClass 不存在"
            vf_capture_kubectl get pods -n kubemate-system --no-headers 2>/dev/null \
                || vf_error "OpenEBS Pod 查询失败"
            rows=${VF_OUTPUT}
            printf '%s\n' "${rows}" | awk '$1 ~ /openebs/ && ($3 == "Running" || $3 == "Completed") { found=1 } END { exit !found }' \
                || vf_missing "OpenEBS Pod 未就绪"
            vf_satisfied "OpenEBS 已就绪"
            ;;
        49-install-minio)
            vf_kube_api_ready
            vf_rollout deployment minio-operator kubemate-system || vf_missing "MinIO Operator 未就绪"
            vf_capture_kubectl get tenant kubemate-minio -n kubemate-system \
                -o jsonpath='{.status.currentState}' 2>/dev/null || vf_missing "MinIO Tenant 不存在"
            value=${VF_OUTPUT}
            [ "${value}" = Initialized ] || vf_missing "MinIO Tenant 未初始化"
            vf_capture_kubectl get pods -n kubemate-system -l v1.min.io/tenant=kubemate-minio \
                --no-headers 2>/dev/null || vf_error "MinIO Pod 查询失败"
            rows=${VF_OUTPUT}
            [ "$(printf '%s\n' "${rows}" | awk '$2 ~ /^[0-9]+\/[0-9]+$/ && $2 != "0/0" && $3 == "Running" { count++ } END { print count+0 }')" -eq 4 ] \
                || vf_missing "MinIO Tenant Pod 未全部就绪"
            vf_capture_kubectl get pvc -n kubemate-system -l v1.min.io/tenant=kubemate-minio \
                --no-headers 2>/dev/null || vf_error "MinIO PVC 查询失败"
            rows=${VF_OUTPUT}
            [ "$(printf '%s\n' "${rows}" | awk '$2 == "Bound" { count++ } END { print count+0 }')" -eq 4 ] \
                || vf_missing "MinIO Tenant PVC 未全部 Bound"
            vf_kubectl get service kubemate-minio-hl -n kubemate-system >/dev/null 2>&1 \
                || vf_missing "MinIO Headless Service 不存在"
            vf_satisfied "MinIO Operator、Tenant、Pod 和 PVC 已就绪"
            ;;
        35-install-loki|48-install-alloy)
            vf_kube_api_ready
            value=${key#*-install-}
            vf_helm_release "${value}" kubemate-system || vf_missing "${value} Helm Release 不存在"
            vf_capture_kubectl get pods -n kubemate-system --no-headers 2>/dev/null \
                || vf_error "${value} Pod 查询失败"
            rows=${VF_OUTPUT}
            printf '%s\n' "${rows}" | awk -v name="${value}" '$1 ~ name && ($3 == "Running" || $3 == "Completed") { found=1 } END { exit !found }' \
                || vf_missing "${value} 工作负载未就绪"
            vf_satisfied "${value} 已就绪"
            ;;
        38-install-prometheus)
            vf_kube_api_ready
            vf_kubectl get prometheus -A >/dev/null 2>&1 || vf_missing "Prometheus 自定义资源不存在"
            vf_kubectl get servicemonitor -A >/dev/null 2>&1 || vf_missing "ServiceMonitor 资源不存在"
            vf_capture_kubectl get pods -A --no-headers 2>/dev/null || vf_error "Prometheus Pod 查询失败"
            rows=${VF_OUTPUT}
            printf '%s\n' "${rows}" | awk '$2 ~ /prometheus/ && $4 == "Running" { found=1 } END { exit !found }' \
                || vf_missing "Prometheus 工作负载未就绪"
            vf_satisfied "Prometheus 监控组件已就绪"
            ;;
        *) return 1 ;;
    esac
}

verify_step() {
    local key="$1"
    [ -n "${key}" ] || vf_error "步骤键为空"
    vf_verify_base "${key}" && return 0
    vf_verify_component "${key}" && return 0
    vf_error "未定义的验证步骤: ${key}"
}

export -f verify_step vf_satisfied vf_missing vf_error vf_timeout
