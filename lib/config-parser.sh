#!/bin/bash
# config-parser.sh - 配置解析模块
# 提供 KubeFoundry 配置文件的解析和处理功能

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 加载依赖模块
source "${PROJECT_ROOT}/lib/common.sh"

# 配置文件路径
readonly CONFIG_FILE="${CONFIG_FILE:-${PROJECT_ROOT}/config/deploy-config.yaml}"
readonly DEFAULTS_DIR="${PROJECT_ROOT}/config/defaults"

# 解析后的配置缓存
declare -A PARSED_CONFIG=()

# 加载配置文件
load_config() {
    local config_file="${1:-${CONFIG_FILE}}"

    if [[ ! -f "${config_file}" ]]; then
        log_error "配置文件不存在: ${config_file}"
        return 1
    fi

    if ! command -v yq >/dev/null 2>&1; then
        log_error "yq 命令未找到，无法解析配置文件"
        return 1
    fi

    log_info "加载配置文件: ${config_file}"

    # 验证 YAML 格式
    if ! yq eval '.' "${config_file}" >/dev/null 2>&1; then
        log_error "配置文件格式无效: ${config_file}"
        return 1
    fi

    return 0
}

# 获取配置值
get_config() {
    local key="$1"
    local default_value="${2:-}"
    local config_file="${3:-${CONFIG_FILE}}"

    # 检查缓存
    if [[ -n "${PARSED_CONFIG[${key}]:-}" ]]; then
        echo "${PARSED_CONFIG[${key}]}"
        return 0
    fi

    local value
    value=$(yq eval ".${key} // \"${default_value}\"" "${config_file}" 2>/dev/null)

    # 处理 null 值
    if [[ "${value}" == "null" ]]; then
        value="${default_value}"
    fi

    # 缓存值
    PARSED_CONFIG["${key}"]="${value}"

    echo "${value}"
}

# 获取数组配置
get_config_array() {
    local key="$1"
    local config_file="${2:-${CONFIG_FILE}}"

    yq eval ".${key}[]" "${config_file}" 2>/dev/null
}

# 检查配置是否存在
config_exists() {
    local key="$1"
    local config_file="${2:-${CONFIG_FILE}}"

    local value
    value=$(yq eval ".${key}" "${config_file}" 2>/dev/null)
    [[ "${value}" != "null" ]]
}

# 合并配置
merge_configs() {
    local base_file="$1"
    local overlay_file="$2"
    local output_file="$3"

    if [[ ! -f "${base_file}" ]] || [[ ! -f "${overlay_file}" ]]; then
        log_error "基础配置文件或覆盖配置文件不存在"
        return 1
    fi

    # 使用 yq 合并配置
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "${base_file}" "${overlay_file}" > "${output_file}" || {
        log_error "配置合并失败"
        return 1
    }

    log_info "配置已合并: ${output_file}"
}

# 加载默认值
load_defaults() {
    local config_file="${1:-${CONFIG_FILE}}"
    local temp_config
    temp_config=$(mktemp)

    # 创建基础配置结构
    cat > "${temp_config}" << 'EOF'
global:
  architecture: x86_64
  cluster_name: kubefoundry-cluster
  k8s_install_dir: /data
  media_source: /data/k8s_install
  timezone: Asia/Shanghai
  ssh:
    port: 22
    user: root
    timeout: 300
    retry_count: 3

hosts:
  control_plane: []
  workers: []

packages:
  container_runtime: auto
  kube_version: 1.30.14

networking:
  dual_stack:
    enabled: true
    ipv4_pod_cidr: 192.168.0.0/16
    ipv6_pod_cidr: fd00:100:64::/64
    ipv4_service_cidr: 192.96.0.0/12
    ipv6_service_cidr: fd00:100:96::/112
  cni:
    type: flannel
    flannel_version: v0.24.2
    backend: vxlan

registry:
  type: docker-registry
  host: registry.kubefoundry.local
  port: 5000

storage:
  nfs:
    server: ""
    export_path: ""
    mount_path: /data/nfs

addons:
  ingress:
    type: traefik
    enabled: true
  monitoring:
    enabled: true

backup:
  etcd:
    enabled: true
    backup_path: /data/nfs_root/etcdbackup
    retention_days: 30
    interval_hours: 6
EOF

    # 加载额外的默认配置文件
    for defaults_file in "${DEFAULTS_DIR}"/*.yaml; do
        if [[ -f "${defaults_file}" ]]; then
            log_debug "加载默认配置: ${defaults_file}"
            merge_configs "${temp_config}" "${defaults_file}" "${temp_config}.tmp"
            mv "${temp_config}.tmp" "${temp_config}"
        fi
    done

    # 合并用户配置
    if [[ -f "${config_file}" ]]; then
        merge_configs "${temp_config}" "${config_file}" "${temp_config}.tmp"
        mv "${temp_config}.tmp" "${temp_config}"
    fi

    # 生成最终配置
    cp "${temp_config}" "${config_file}"
    rm -f "${temp_config}"

    log_info "默认配置已加载并合并"
}

# 验证配置完整性
validate_config_integrity() {
    local config_file="${1:-${CONFIG_FILE}}"
    local errors=0

    log_info "验证配置完整性..."

    # 检查必需的顶级字段
    local required_fields=("global.architecture" "hosts.control_plane" "packages.kube_version" "networking.dual_stack")
    local field

    for field in "${required_fields[@]}"; do
        if ! config_exists "${field}" "${config_file}"; then
            log_error "缺少必需字段: ${field}"
            ((errors++))
        fi
    done

    # 检查架构配置
    local arch
    arch=$(get_config "global.architecture" "" "${config_file}")
    if [[ ! "${arch}" =~ ^(x86_64|amd64|arm64|aarch64)$ ]]; then
        log_error "无效的系统架构: ${arch}"
        ((errors++))
    fi

    # 检查主机配置
    local control_plane_count
    control_plane_count=$(yq eval '.hosts.control_plane | length' "${config_file}")
    if [[ ${control_plane_count} -eq 0 ]]; then
        log_error "至少需要一个控制平面节点"
        ((errors++))
    fi

    # 检查 Kubernetes 版本
    local kube_version
    kube_version=$(get_config "packages.kube_version" "" "${config_file}")
    if [[ ! "${kube_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "无效的 Kubernetes 版本格式: ${kube_version}"
        ((errors++))
    fi

    if [[ ${errors} -gt 0 ]]; then
        log_error "配置完整性验证失败，发现 ${errors} 个错误"
        return 1
    fi

    log_info "配置完整性验证通过"
    return 0
}

# 生成主机清单
generate_host_inventory() {
    local config_file="${1:-${CONFIG_FILE}}"
    local output_file="${2:-${PROJECT_ROOT}/hosts.ini}"

    cat > "${output_file}" << EOF
# KubeFoundry 主机清单
# 自动生成，请勿手动修改

[control_plane]
EOF

    # 添加控制平面节点
    yq eval '.hosts.control_plane[] | .name + " ansible_host=" + .ip + " ip=" + .ip + " ipv6=" + (.ipv6 // "null")' "${config_file}" | while read -r line; do
        echo "${line}" >> "${output_file}"
    done

    cat >> "${output_file}" << EOF

[workers]
EOF

    # 添加工作节点
    yq eval '.hosts.workers[]? | .name + " ansible_host=" + .ip + " ip=" + .ip + " ipv6=" + (.ipv6 // "null")' "${config_file}" | while read -r line; do
        echo "${line}" >> "${output_file}"
    done

    cat >> "${output_file}" << EOF

[all:vars]
ansible_user=root
ansible_port=\$(yq eval '.global.ssh.port' "${config_file}")
ansible_ssh_private_key_file=~/.ssh/kubefoundry_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

    log_info "主机清单已生成: ${output_file}"
}

# 生成 Kubernetes 配置
generate_kubeconfig() {
    local config_file="${1:-${CONFIG_FILE}}"
    local output_dir="${2:-${PROJECT_ROOT}/kubeconfig}"

    ensure_directory "${output_dir}"

    # 生成 kubeadm 配置模板
    cat > "${output_dir}/kubeadm-config.yaml" << EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "$(yq eval '.cluster.api_server.advertise_address' "${config_file}" 2>/dev/null || echo "192.168.1.10")"
  bindPort: $(yq eval '.cluster.api_server.bind_port' "${config_file}" 2>/dev/null || echo "6443")
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    cgroup-driver: systemd
    node-ip: "$(yq eval '.hosts.control_plane[0].ip' "${config_file}")"
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "$(yq eval '.packages.kube_version' "${config_file}")"
clusterName: "$(yq eval '.global.cluster_name' "${config_file}")"
controlPlaneEndpoint: "$(yq eval '.hosts.control_plane[0].ip' "${config_file}"):6443"
etcd:
  external:
    endpoints:
EOF

    # 添加 etcd 端点
    yq eval '.hosts.control_plane[] | "    - https://" + .ip + ":2379"' "${config_file}" >> "${output_dir}/kubeadm-config.yaml"

    cat >> "${output_dir}/kubeadm-config.yaml" << EOF
apiServer:
  extraArgs:
    service-node-port-range: "30000-32767"
  certSANs:
EOF

    # 添加证书 SAN
    yq eval '.cluster.api_server.cert_sans[]? | "    - " + .' "${config_file}" >> "${output_dir}/kubeadm-config.yaml" 2>/dev/null || echo "    - localhost" >> "${output_dir}/kubeadm-config.yaml"

    cat >> "${output_dir}/kubeadm-config.yaml" << EOF
networking:
  serviceSubnet: "$(yq eval '.networking.dual_stack.ipv4_service_cidr' "${config_file}")"
  podSubnet: "$(yq eval '.networking.dual_stack.ipv4_pod_cidr' "${config_file}")"
  dnsDomain: "$(yq eval '.cluster.domain' "${config_file}" 2>/dev/null || echo "cluster.local")"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
maxPods: $(yq eval '.performance.kubelet.max_pods' "${config_file}" 2>/dev/null || echo "110")
EOF

    log_info "kubeadm 配置已生成: ${output_dir}/kubeadm-config.yaml"
}

# 选择容器运行时
select_container_runtime() {
    local config_file="${1:-${CONFIG_FILE}}"

    local runtime_config
    runtime_config=$(get_config "packages.container_runtime" "auto" "${config_file}")

    local kube_version
    kube_version=$(get_config "packages.kube_version" "" "${config_file}")

    case "${runtime_config}" in
        "auto")
            case "${kube_version}" in
                "1.23"*)
                    echo "docker"
                    ;;
                "1.30"*)
                    echo "containerd"
                    ;;
                *)
                    log_error "不支持的 Kubernetes 版本: ${kube_version}"
                    return 1
                    ;;
            esac
            ;;
        "docker"|"containerd")
            echo "${runtime_config}"
            ;;
        *)
            log_error "不支持的容器运行时: ${runtime_config}"
            return 1
            ;;
    esac
}

# 获取架构特定的介质路径
get_architecture_media_path() {
    local config_file="${1:-${CONFIG_FILE}}"
    local media_base="${2:-$(get_config "global.media_source" "/data/k8s_install" "${config_file}")}"

    local arch
    arch=$(get_config "global.architecture" "x86_64" "${config_file}")

    # 统一架构名称
    case "${arch}" in
        "amd64"|"x86_64")
            echo "${media_base}/01.AMD"
            ;;
        "arm64"|"aarch64")
            echo "${media_base}/02.ARM"
            ;;
        *)
            log_error "不支持的架构: ${arch}"
            return 1
            ;;
    esac
}

# 生成配置摘要
generate_config_summary() {
    local config_file="${1:-${CONFIG_FILE}}"
    local output_file="${2:-${PROJECT_ROOT}/config-summary.txt}"

    cat > "${output_file}" << EOF
=== KubeFoundry 配置摘要 ===
配置文件: ${config_file}
生成时间: $(get_timestamp)

集群信息:
  - 集群名称: $(get_config "global.cluster_name" "" "${config_file}")
  - 系统架构: $(get_config "global.architecture" "" "${config_file}")
  - Kubernetes 版本: $(get_config "packages.kube_version" "" "${config_file}")
  - 容器运行时: $(select_container_runtime "${config_file}")

主机配置:
  - 控制平面节点数: $(yq eval '.hosts.control_plane | length' "${config_file}")
  - 工作节点数: $(yq eval '.hosts.workers | length' "${config_file}")

网络配置:
  - 双栈网络: $(get_config "networking.dual_stack.enabled" "" "${config_file}")
  - IPv4 Pod CIDR: $(get_config "networking.dual_stack.ipv4_pod_cidr" "" "${config_file}")
  - IPv6 Pod CIDR: $(get_config "networking.dual_stack.ipv6_pod_cidr" "" "${config_file}")
  - CNI 类型: $(get_config "networking.cni.type" "" "${config_file}")

存储配置:
  - NFS 服务器: $(get_config "storage.nfs.server" "未配置" "${config_file}")
  - NFS 导出路径: $(get_config "storage.nfs.export_path" "未配置" "${config_file}")

扩展组件:
  - Ingress 控制器: $(get_config "addons.ingress.enabled" "false" "${config_file}")
  - 监控组件: $(get_config "addons.monitoring.enabled" "false" "${config_file}")

备份配置:
  - etcd 备份: $(get_config "backup.etcd.enabled" "false" "${config_file}")
  - 备份路径: $(get_config "backup.etcd.backup_path" "" "${config_file}")
EOF

    log_info "配置摘要已生成: ${output_file}"
}

# 导出配置为环境变量
export_config_as_env() {
    local config_file="${1:-${CONFIG_FILE}}"
    local env_file="${2:-${PROJECT_ROOT}/.env}"

    cat > "${env_file}" << EOF
# KubeFoundry 配置环境变量
# 自动生成，请勿手动修改

export K8S_ARCHITECTURE="$(get_config "global.architecture" "x86_64" "${config_file}")"
export K8S_CLUSTER_NAME="$(get_config "global.cluster_name" "kubefoundry-cluster" "${config_file}")"
export K8S_INSTALL_DIR="$(get_config "global.k8s_install_dir" "/data" "${config_file}")"
export K8S_MEDIA_SOURCE="$(get_config "global.media_source" "/data/k8s_install" "${config_file}")"
export K8S_VERSION="$(get_config "packages.kube_version" "1.30.14" "${config_file}")"
export K8S_CONTAINER_RUNTIME="$(select_container_runtime "${config_file}")"

export K8S_CONTROL_PLANE_COUNT="$(yq eval '.hosts.control_plane | length' "${config_file}")"
export K8S_WORKER_COUNT="$(yq eval '.hosts.workers | length' "${config_file}")"

export K8S_DUAL_STACK="$(get_config "networking.dual_stack.enabled" "true" "${config_file}")"
export K8S_IPV4_POD_CIDR="$(get_config "networking.dual_stack.ipv4_pod_cidr" "192.168.0.0/16" "${config_file}")"
export K8S_IPV6_POD_CIDR="$(get_config "networking.dual_stack.ipv6_pod_cidr" "fd00:100:64::/64" "${config_file}")"
export K8S_IPV4_SERVICE_CIDR="$(get_config "networking.dual_stack.ipv4_service_cidr" "192.96.0.0/12" "${config_file}")"
export K8S_IPV6_SERVICE_CIDR="$(get_config "networking.dual_stack.ipv6_service_cidr" "fd00:100:96::/112" "${config_file}")"

export K8S_CNI_TYPE="$(get_config "networking.cni.type" "flannel" "${config_file}")"
export K8S_CNI_FLANNEL_VERSION="$(get_config "networking.cni.flannel_version" "v0.24.2" "${config_file}")"

export K8S_REGISTRY_TYPE="$(get_config "registry.type" "docker-registry" "${config_file}")"
export K8S_REGISTRY_HOST="$(get_config "registry.host" "registry.kubefoundry.local" "${config_file}")"
export K8S_REGISTRY_PORT="$(get_config "registry.port" "5000" "${config_file}")"

export K8S_NFS_SERVER="$(get_config "storage.nfs.server" "" "${config_file}")"
export K8S_NFS_EXPORT_PATH="$(get_config "storage.nfs.export_path" "" "${config_file}")"

export K8S_INGRESS_ENABLED="$(get_config "addons.ingress.enabled" "true" "${config_file}")"
export K8S_MONITORING_ENABLED="$(get_config "addons.monitoring.enabled" "true" "${config_file}")"
export K8S_BACKUP_ENABLED="$(get_config "backup.etcd.enabled" "true" "${config_file}")"
export K8S_BACKUP_PATH="$(get_config "backup.etcd.backup_path" "/data/nfs_root/etcdbackup" "${config_file}")"
EOF

    log_info "配置环境变量已导出: ${env_file}"
}

# 刷新配置缓存
flush_config_cache() {
    PARSED_CONFIG=()
    log_debug "配置缓存已刷新"
}

# 模块加载提示
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "config-parser.sh 是一个库文件，应该被 source 调用，而不是直接执行"
    echo ""
    echo "用法示例:"
    echo "  source ${PROJECT_ROOT}/lib/config-parser.sh"
    echo "  load_config config/deploy-config.yaml"
    echo "  get_config 'global.cluster_name'"
    echo "  select_container_runtime"
    exit 1
fi

log_debug "配置解析模块已加载"