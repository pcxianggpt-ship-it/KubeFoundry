#!/bin/bash

#===============================================================================
# 脚本名称：main.sh
# 功能：KubeFoundry 主入口脚本
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 设置脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 切换到项目根目录
cd "${PROJECT_ROOT}" || exit 1

# 加载所有库函数
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/ssh.sh"
source "${SCRIPT_DIR}/lib/validator.sh"
source "${SCRIPT_DIR}/lib/exec.sh"
source "${SCRIPT_DIR}/lib/exec_script.sh"
source "${SCRIPT_DIR}/lib/progress.sh"

# 导出变量，使子 shell 可继承
export SCRIPT_DIR PROJECT_ROOT

#===============================================================================
# 函数：show_usage()
# 功能：显示使用帮助
#===============================================================================
show_usage() {
    cat << EOF
KubeFoundry - Kubernetes 集群一键安装工具

用法: $(basename "$0") [选项] [步骤]

选项:
  -h, --help          显示帮助信息
  -v, --version       显示版本信息
  -c, --config FILE   指定配置文件（默认：config/cluster.yaml）
  -l, --log FILE      指定日志文件（默认：/tmp/kubefoundry_install.log）
  -d, --dry-run       模拟运行，不执行实际操作
  -s, --skip-verify   跳过验证步骤（不推荐）
  -r, --reset         清除进度记录，从头开始执行
  -V, --verbose       启用详细日志输出

步骤:
  all                 执行所有步骤（默认）
  precheck            预检查（检查配置文件和工具）
  k8s_base            K8S 基础环境安装
  ecosystem           生态系统组件安装

示例:
  $(basename "$0") all
  $(basename "$0") precheck
  $(basename "$0") -c config/my-cluster.yaml all
  $(basename "$0") -V all
  $(basename "$0") -d all

更多信息请访问: https://github.com/kubefoundry/kubefoundry
EOF
}

#===============================================================================
# 函数：show_version()
# 功能：显示版本信息
#===============================================================================
show_version() {
    cat << EOF
KubeFoundry - Kubernetes 集群一键安装工具
版本: 1.0.0
发布日期: 2026-03-27

更多信息请访问: https://github.com/kubefoundry/kubefoundry
EOF
}

#===============================================================================
# 函数：parse_arguments()
# 功能：解析命令行参数
#===============================================================================
parse_arguments() {
    # 默认值
    CONFIG_FILE="config/cluster.yaml"
    LOG_FILE="/tmp/kubefoundry_install.log"
    DRY_RUN=false
    SKIP_VERIFY=false
    VERBOSE=false
    RESET_PROGRESS=false
    STEP="all"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--skip-verify)
                SKIP_VERIFY=true
                shift
                ;;
            -V|--verbose)
                VERBOSE=true
                shift
                ;;
            -r|--reset)
                RESET_PROGRESS=true
                shift
                ;;
            all|precheck|k8s_base|ecosystem)
                STEP="$1"
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # 导出变量，使子 shell 可继承
    export CONFIG_FILE LOG_FILE DRY_RUN SKIP_VERIFY VERBOSE RESET_PROGRESS
}

#===============================================================================
# 步骤脚本路径
#===============================================================================
STEPS="${SCRIPT_DIR}/steps"
P1="${STEPS}/phase1_precheck"
P2="${STEPS}/phase2_k8s_base"
P3="${STEPS}/phase3_ecosystem"

VERIFY="${SCRIPT_DIR}/verify"
V2="${VERIFY}/phase2_k8s_base"
V3="${VERIFY}/phase3_ecosystem"

#===============================================================================
# 函数：verify_step()
# 功能：执行验证脚本，验证通过返回0，跳过验证时也返回0
# 参数：
#   $1 - 验证脚本路径
#   $2 - 步骤描述（用于日志）
#===============================================================================
verify_step() {
    local verify_script="$1"
    local desc="$2"

    if [ "$SKIP_VERIFY" = true ]; then
        log_info "跳过验证: ${desc}"
        return 0
    fi

    log_info "验证: ${desc}..."
    ( cd "${PROJECT_ROOT}"; source "${verify_script}" )
    return $?
}

#===============================================================================
# 阶段一：预检查
#===============================================================================
run_precheck() {
    log_separator
    log_info "阶段一：预检查"
    log_separator

    # 确保 yq/helm 可用（load_config 依赖 yq 解析 YAML）
    log_info "检查必要工具（yq/helm）..."
    bash "${SCRIPT_DIR}/lib/tools.sh"
    if [ $? -ne 0 ]; then
        log_error "工具检查失败"
        return 1
    fi

    # 加载并验证配置
    log_info "加载配置文件..."
    ( cd "${PROJECT_ROOT}"; source "${P1}/02-init-config.sh" )
    if [ $? -ne 0 ]; then
        log_error "配置文件加载失败"
        return 1
    fi

    log_info "验证配置文件完整性..."
    ( cd "${PROJECT_ROOT}"; source "${P1}/03-validate-config.sh" )
    if [ $? -ne 0 ]; then
        log_error "配置文件验证失败"
        return 1
    fi

    log_success "预检查完成"
}

#===============================================================================
# 阶段二：K8S 基础环境安装
#===============================================================================
run_k8s_base() {
    log_separator
    log_info "阶段二：K8S 基础环境安装"
    log_separator

    # 2.1 配置本地yum源（本地执行）
    if step_is_done "2.1"; then
        log_info "[跳过] 2.1 配置本地yum源（已完成）"
    else
        log_info "配置本地yum源..."
        local repo_source
        repo_source=$(config_resolve '.paths.repo_source')
        ( cd "${PROJECT_ROOT}"; source "${P2}/10-setup-yum-source.sh" "$repo_source" )
        if [ $? -ne 0 ]; then
            log_error "配置yum源失败"
            return 1
        fi
        log_success "yum源配置完成"
        verify_step "${V2}/verify-10-setup-yum-source.sh" "yum源配置"
        if [ $? -ne 0 ]; then
            log_error "yum源验证失败"
            return 1
        fi
        step_done "2.1"
    fi

    # 2.2 配置SSH免密登录（管理节点本地执行）
    if step_is_done "2.2"; then
        log_info "[跳过] 2.2 配置SSH免密登录（已完成）"
    else
        log_info "配置SSH免密登录..."
        ( cd "${PROJECT_ROOT}"; source "${P2}/11-setup-ssh-login.sh" )
        if [ $? -ne 0 ]; then
            log_error "SSH免密登录配置失败"
            return 1
        fi
        log_success "SSH免密登录配置完成"
        verify_step "${V2}/verify-11-setup-ssh-login.sh" "SSH免密登录"
        if [ $? -ne 0 ]; then
            log_error "SSH免密登录验证失败"
            return 1
        fi
        step_done "2.2"
    fi

    # 2.3 配置主机名和hosts解析（管理节点本地执行）
    if step_is_done "2.3"; then
        log_info "[跳过] 2.3 配置主机名和hosts解析（已完成）"
    else
        log_info "配置主机名和hosts解析..."
        ( cd "${PROJECT_ROOT}"; source "${P2}/11b-setup-hostname.sh" )
        if [ $? -ne 0 ]; then
            log_error "主机名和hosts解析配置失败"
            return 1
        fi
        log_success "主机名和hosts解析配置完成"
        verify_step "${V2}/verify-11b-setup-hostname.sh" "主机名和hosts解析"
        if [ $? -ne 0 ]; then
            log_error "主机名和hosts解析验证失败"
            return 1
        fi
        step_done "2.3"
    fi

    # 2.4 配置本地k8s repo源客户端（除主控制节点外所有节点）
    if step_is_done "2.4"; then
        log_info "[跳过] 2.4 配置k8s repo源客户端（已完成）"
    else
        log_info "配置k8s repo源客户端..."
        exec_script_on_workers "${P2}/12-setup-k8s-repo.sh"
        if [ $? -ne 0 ]; then
            log_error "k8s repo源配置失败"
            return 1
        fi
        log_success "k8s repo源配置完成"
        verify_step "${V2}/verify-12-setup-k8s-repo.sh" "k8s repo源"
        if [ $? -ne 0 ]; then
            log_error "k8s repo源验证失败"
            return 1
        fi
        step_done "2.4"
    fi

    # 2.5 安装K8s依赖包（所有节点）
    if step_is_done "2.5"; then
        log_info "[跳过] 2.5 安装K8s依赖包（已完成）"
    else
        log_info "安装K8s依赖包..."
        exec_script_on_all_nodes "${P2}/13-install-k8s-deps.sh"
        if [ $? -ne 0 ]; then
            log_error "K8s依赖包安装失败"
            return 1
        fi
        log_success "K8s依赖包安装完成"
        verify_step "${V2}/verify-13-install-k8s-deps.sh" "K8s依赖包"
        if [ $? -ne 0 ]; then
            log_error "K8s依赖包验证失败"
            return 1
        fi
        step_done "2.5"
    fi

    # 2.6 替换kubeadm为支持100年证书版本（仅主控制节点）
    if step_is_done "2.6"; then
        log_info "[跳过] 2.6 替换kubeadm（已完成）"
    else
        log_info "替换kubeadm..."
        exec_script_on_control_plane "${P2}/14-replace-kubeadm.sh"
        if [ $? -ne 0 ]; then
            log_error "kubeadm替换失败"
            return 1
        fi
        log_success "kubeadm替换完成"
        verify_step "${V2}/verify-14-replace-kubeadm.sh" "kubeadm替换"
        if [ $? -ne 0 ]; then
            log_error "kubeadm替换验证失败"
            return 1
        fi
        step_done "2.6"
    fi

    # 2.7 环境配置（所有节点）
    if step_is_done "2.7"; then
        log_info "[跳过] 2.7 环境配置（已完成）"
    else
        log_info "执行环境配置..."
        exec_script_on_all_nodes "${P2}/15-environment-config.sh"
        if [ $? -ne 0 ]; then
            log_error "环境配置失败"
            return 1
        fi
        log_success "环境配置完成"
        verify_step "${V2}/verify-15-environment-config.sh" "环境配置"
        if [ $? -ne 0 ]; then
            log_error "环境配置验证失败"
            return 1
        fi
        step_done "2.7"
    fi

    # 2.8 安装containerd（所有节点）
    if step_is_done "2.8"; then
        log_info "[跳过] 2.8 安装containerd（已完成）"
    else
        # 分发 container_runtime 目录到所有节点
        log_info "分发container_runtime安装包到所有节点..."
        local container_runtime_dir
        container_runtime_dir=$(config_resolve '.paths.container_runtime')
        if [ ! -d "$container_runtime_dir" ]; then
            log_error "container_runtime目录不存在: ${container_runtime_dir}"
            return 1
        fi
        scp_dir_to_all_nodes "$container_runtime_dir" "/tmp/k8s"
        if [ $? -ne 0 ]; then
            log_error "container_runtime安装包分发失败"
            return 1
        fi
        log_success "container_runtime安装包分发完成"

        log_info "安装containerd..."
        exec_script_on_all_nodes "${P2}/16-install-containerd.sh"
        if [ $? -ne 0 ]; then
            log_error "containerd安装失败"
            return 1
        fi
        log_success "containerd安装完成"
        verify_step "${V2}/verify-16-install-containerd.sh" "containerd"
        if [ $? -ne 0 ]; then
            log_error "containerd验证失败"
            return 1
        fi
        step_done "2.8"
    fi

    # 2.9 安装镜像仓库（registry节点）
    if step_is_done "2.9"; then
        log_info "[跳过] 2.9 安装镜像仓库（已完成）"
    else
        # 验证 registry 镜像仓库是否已部署
        log_info "检查 registry 镜像仓库部署状态..."
        local registry_ip_val
        registry_ip_val=$(get_registry_ip)
        local registry_check_result
        registry_check_result=$(ssh_exec_capture "$registry_ip_val" "nerdctl images | grep -c 'registry:2.8.3' || true" 2>/dev/null | tr -d '[:space:]')

        # 检查 registry 容器是否运行
        local registry_running
        registry_running=$(ssh_exec_capture "$registry_ip_val" "nerdctl ps -a | grep 'registry:2.8.3' | grep -c 'Up' || true" 2>/dev/null | tr -d '[:space:]')

        if [ "$registry_check_result" -ge 1 ] && [ "$registry_running" -ge 1 ]; then
            log_info "检测到 registry 镜像仓库已部署（镜像: ${registry_check_result}, 运行: ${registry_running}），跳过安装"
            step_done "2.9"
        else
            # 分发 registry 安装包到镜像仓库节点
            log_info "分发registry安装包到镜像仓库节点..."
            local registry_install_dir
            registry_install_dir=$(config_resolve '.paths.registry_install')
            if [ ! -d "$registry_install_dir" ]; then
                log_error "registry安装包目录不存在: ${registry_install_dir}"
                return 1
            fi
            local k8s_home_val
            k8s_home_val=$(get_k8s_home)
            scp_dir_to_node "$registry_install_dir" "$k8s_home_val" "$registry_ip_val"
            if [ $? -ne 0 ]; then
                log_error "registry安装包分发失败"
                return 1
            fi
            log_success "registry安装包分发完成"

            log_info "安装镜像仓库..."
            exec_script_on_registry "${P2}/17-install-registry.sh"
            if [ $? -ne 0 ]; then
                log_error "镜像仓库安装失败"
                return 1
            fi
            log_success "镜像仓库安装完成"
            verify_step "${V2}/verify-17-install-registry.sh" "镜像仓库"
            if [ $? -ne 0 ]; then
                log_error "镜像仓库验证失败"
                return 1
            fi
            step_done "2.9"
        fi
    fi

    # 2.10 初始化K8S集群（仅主控制节点）
    if step_is_done "2.10"; then
        log_info "[跳过] 2.10 初始化K8S集群（已完成）"
    else
        log_info "初始化K8S集群..."
        exec_script_on_control_plane "${P2}/18-init-k8s-cluster.sh"
        if [ $? -ne 0 ]; then
            log_error "K8S集群初始化失败"
            return 1
        fi
        log_success "K8S集群初始化完成"
        verify_step "${V2}/verify-18-init-k8s-cluster.sh" "K8S集群初始化"
        if [ $? -ne 0 ]; then
            log_error "K8S集群初始化验证失败"
            return 1
        fi
        step_done "2.10"
    fi

    # 2.11 修改证书有效期（仅主控制节点）
    if step_is_done "2.11"; then
        log_info "[跳过] 2.11 修改证书有效期（已完成）"
    else
        log_info "修改证书有效期..."
        exec_script_on_control_plane "${P2}/19-modify-cert-expiry.sh"
        if [ $? -ne 0 ]; then
            log_error "证书有效期修改失败"
            return 1
        fi
        log_success "证书有效期修改完成"
        verify_step "${V2}/verify-19-modify-cert-expiry.sh" "证书有效期"
        if [ $? -ne 0 ]; then
            log_error "证书有效期验证失败"
            return 1
        fi
        step_done "2.11"
    fi

    # 2.12 添加控制节点（其他控制节点）
    if step_is_done "2.12"; then
        log_info "[跳过] 2.12 添加控制节点（已完成）"
    else
        local _cp_count
        _cp_count=$(config_get_length '.control_plane')
        if [ "$_cp_count" -le 1 ]; then
            log_info "[跳过] 2.12 添加控制节点（单控制节点部署，无需join）"
        else
            log_info "添加控制节点..."
            local _primary_cp
            _primary_cp=$(get_all_control_plane_ips | head -1)
            exec_script_on_control_plane "${P2}/20-add-control-nodes.sh" "$_primary_cp"
            if [ $? -ne 0 ]; then
                log_error "添加控制节点失败"
                return 1
            fi
            log_success "控制节点添加完成"
            verify_step "${V2}/verify-20-add-control-nodes.sh" "控制节点"
            if [ $? -ne 0 ]; then
                log_error "控制节点验证失败"
                return 1
            fi
        fi
        step_done "2.12"
    fi

    # 2.13 添加工作节点
    if step_is_done "2.13"; then
        log_info "[跳过] 2.13 添加工作节点（已完成）"
    else
        log_info "添加工作节点..."
 
        joincmd=$(cat /tmp/k8s/kube_join_nodes)

        exec_script_on_workers "${P2}/21-add-worker-nodes.sh" "$joincmd"
        if [ $? -ne 0 ]; then
            log_error "添加工作节点失败"
            return 1
        fi
        log_success "工作节点添加完成"
        verify_step "${V2}/verify-21-add-worker-nodes.sh" "工作节点"
        if [ $? -ne 0 ]; then
            log_error "工作节点验证失败"
            return 1
        fi
        step_done "2.13"
    fi

    # 2.14 安装CNI插件-Flannel（仅主控制节点）
    if step_is_done "2.14"; then
        log_info "[跳过] 2.14 安装CNI插件Flannel（已完成）"
    else
        log_info "安装CNI插件Flannel..."
        exec_script_on_control_plane "${P2}/22-install-cni-flannel.sh"
        if [ $? -ne 0 ]; then
            log_error "Flannel安装失败"
            return 1
        fi
        log_success "Flannel安装完成"
        verify_step "${V2}/verify-22-install-cni-flannel.sh" "Flannel CNI"
        if [ $? -ne 0 ]; then
            log_error "Flannel验证失败"
            return 1
        fi
        step_done "2.14"
    fi

    log_success "K8S基础环境安装完成"
}

#===============================================================================
# 阶段三：生态系统组件安装
#===============================================================================
run_ecosystem() {
    log_separator
    log_info "阶段三：生态系统组件安装"
    log_separator

    # 3.1 创建命名空间（主控制节点）
    if step_is_done "3.1"; then
        log_info "[跳过] 3.1 创建命名空间（已完成）"
    else
        log_info "创建命名空间..."
        exec_script_on_control_plane "${P3}/30-create-namespace.sh"
        if [ $? -ne 0 ]; then
            log_error "创建命名空间失败"
            return 1
        fi
        log_success "命名空间创建完成"
        verify_step "${V3}/verify-30-create-namespace.sh" "命名空间"
        if [ $? -ne 0 ]; then
            log_error "命名空间验证失败"
            return 1
        fi
        step_done "3.1"
    fi

    # 3.2 安装kubemate管理界面（本地执行）
    if ! ecosystem_enabled "kubemate_ui"; then
        log_info "[跳过] 3.2 安装kubemate管理界面（配置中已禁用）"
    elif step_is_done "3.2"; then
        log_info "[跳过] 3.2 安装kubemate管理界面（已完成）"
    else
        log_info "安装kubemate管理界面..."
        ( cd "${PROJECT_ROOT}"; source "${P3}/31-install-kubemate-ui.sh" )
        if [ $? -ne 0 ]; then
            log_error "kubemate安装失败"
            return 1
        fi
        log_success "kubemate安装完成"
        verify_step "${V3}/verify-31-install-kubemate-ui.sh" "kubemate"
        if [ $? -ne 0 ]; then
            log_error "kubemate验证失败"
            return 1
        fi
        step_done "3.2"
    fi

    # 3.3 安装NFS插件（主控制节点）
    if ! ecosystem_enabled "nfs"; then
        log_info "[跳过] 3.3 安装NFS插件（配置中已禁用）"
    elif step_is_done "3.3"; then
        log_info "[跳过] 3.3 安装NFS插件（已完成）"
    else
        log_info "安装NFS插件..."
        source "${P3}/32-configure-nfs-exports.sh"
        if [ $? -ne 0 ]; then
            log_error "NFS exports配置失败"
            return 1
        fi
        exec_script_on_control_plane "${P3}/32-install-nfs.sh"
        if [ $? -ne 0 ]; then
            log_error "NFS安装失败"
            return 1
        fi

        # 配置Worker节点挂载NFS
        source "${P3}/32-mount-nfs-workers.sh"
        log_success "NFS安装完成"
        verify_step "${V3}/verify-32-install-nfs.sh" "NFS"
        if [ $? -ne 0 ]; then
            log_error "NFS验证失败"
            return 1
        fi
        step_done "3.3"
    fi

    # 3.4 安装Elasticsearch + Skywalking（主控制节点）
    if ! ecosystem_enabled "elasticsearch"; then
        log_info "[跳过] 3.4 安装Elasticsearch + Skywalking（配置中已禁用）"
    elif step_is_done "3.4"; then
        log_info "[跳过] 3.4 安装Elasticsearch + Skywalking（已完成）"
    else
        log_info "安装elasticsearch..."
        exec_script_on_control_plane "${P3}/33-install-elasticsearch.sh"
        if [ $? -ne 0 ]; then
            log_error "elasticsearch安装失败"
            return 1
        fi
        log_success "elasticsearch安装完成"
        verify_step "${V3}/verify-33-install-elasticsearch.sh" "elasticsearch"
        if [ $? -ne 0 ]; then
            log_error "elasticsearch验证失败"
            return 1
        fi

        log_info "安装skywalking..."
        exec_script_on_control_plane "${P3}/34-install-skywalking.sh"
        if [ $? -ne 0 ]; then
            log_error "skywalking安装失败"
            return 1
        fi
        log_success "skywalking安装完成"
        verify_step "${V3}/verify-34-install-skywalking.sh" "skywalking"
        if [ $? -ne 0 ]; then
            log_error "skywalking验证失败"
            return 1
        fi
        step_done "3.4"
    fi

    # 3.5 安装Traefik（主控制节点）
    if ! ecosystem_enabled "traefik"; then
        log_info "[跳过] 3.5 安装Traefik（配置中已禁用）"
    elif step_is_done "3.5"; then
        log_info "[跳过] 3.5 安装Traefik（已完成）"
    else
        log_info "安装traefik..."
        exec_script_on_control_plane "${P3}/36-install-traefik.sh"
        if [ $? -ne 0 ]; then
            log_error "traefik安装失败"
            return 1
        fi
        log_success "traefik安装完成"
        verify_step "${V3}/verify-36-install-traefik.sh" "traefik"
        if [ $? -ne 0 ]; then
            log_error "traefik验证失败"
            return 1
        fi
        step_done "3.5"
    fi

    # 3.6 安装Prometheus（主控制节点）
    if ! ecosystem_enabled "prometheus"; then
        log_info "[跳过] 3.6 安装Prometheus（配置中已禁用）"
    elif step_is_done "3.6"; then
        log_info "[跳过] 3.6 安装Prometheus（已完成）"
    else
        log_info "安装prometheus..."
        exec_script_on_control_plane "${P3}/38-install-prometheus.sh"
        if [ $? -ne 0 ]; then
            log_error "prometheus安装失败"
            return 1
        fi
        log_success "prometheus安装完成"
        verify_step "${V3}/verify-38-install-prometheus.sh" "prometheus"
        if [ $? -ne 0 ]; then
            log_error "prometheus验证失败"
            return 1
        fi
        step_done "3.6"
    fi

    # 3.7 安装OpenEBS（主控制节点）
    if ! ecosystem_enabled "openebs"; then
        log_info "[跳过] 3.7 安装OpenEBS（配置中已禁用）"
    elif step_is_done "3.7"; then
        log_info "[跳过] 3.7 安装OpenEBS（已完成）"
    else
        log_info "安装openebs..."
        exec_script_on_control_plane "${P3}/47-install-openebs.sh"
        if [ $? -ne 0 ]; then
            log_error "openebs安装失败"
            return 1
        fi
        log_success "openebs安装完成"
        verify_step "${V3}/verify-47-install-openebs.sh" "openebs"
        if [ $? -ne 0 ]; then
            log_error "openebs验证失败"
            return 1
        fi
        step_done "3.7"
    fi

    # 3.8 安装Grafana Alloy（主控制节点）
    if ! ecosystem_enabled "alloy"; then
        log_info "[跳过] 3.8 安装Grafana Alloy（配置中已禁用）"
    elif step_is_done "3.8"; then
        log_info "[跳过] 3.8 安装Grafana Alloy（已完成）"
    else
        log_info "安装alloy..."
        exec_script_on_control_plane "${P3}/48-install-alloy.sh"
        if [ $? -ne 0 ]; then
            log_error "alloy安装失败"
            return 1
        fi
        log_success "alloy安装完成"
        verify_step "${V3}/verify-48-install-alloy.sh" "alloy"
        if [ $? -ne 0 ]; then
            log_error "alloy验证失败"
            return 1
        fi
        step_done "3.8"
    fi

    # 3.9 安装Loki（主控制节点）
    if ! ecosystem_enabled "loki"; then
        log_info "[跳过] 3.9 安装Loki（配置中已禁用）"
    elif step_is_done "3.9"; then
        log_info "[跳过] 3.9 安装Loki（已完成）"
    else
        log_info "安装loki..."
        exec_script_on_control_plane "${P3}/35-install-loki.sh"
        if [ $? -ne 0 ]; then
            log_error "loki安装失败"
            return 1
        fi
        log_success "loki安装完成"
        verify_step "${V3}/verify-35-install-loki.sh" "loki"
        if [ $? -ne 0 ]; then
            log_error "loki验证失败"
            return 1
        fi
        step_done "3.9"
    fi

    # 3.10 安装MinIO（主控制节点）
    if ! ecosystem_enabled "minio"; then
        log_info "[跳过] 3.10 安装MinIO（配置中已禁用）"
    elif step_is_done "3.10"; then
        log_info "[跳过] 3.10 安装MinIO（已完成）"
    else
        log_info "安装minio..."
        exec_script_on_control_plane "${P3}/49-install-minio.sh"
        if [ $? -ne 0 ]; then
            log_error "minio安装失败"
            return 1
        fi
        log_success "minio安装完成"
        verify_step "${V3}/verify-49-install-minio.sh" "minio"
        if [ $? -ne 0 ]; then
            log_error "minio验证失败"
            return 1
        fi
        step_done "3.10"
    fi

    # 3.11 安装Traefik Mesh（主控制节点，依赖 Traefik）
    if ! ecosystem_enabled "traefik"; then
        log_info "[跳过] 3.11 安装Traefik Mesh（配置中已禁用）"
    elif step_is_done "3.11"; then
        log_info "[跳过] 3.11 安装Traefik Mesh（已完成）"
    else
        log_info "安装traefik-mesh..."
        exec_script_on_control_plane "${P3}/37-install-traefik-mesh.sh"
        if [ $? -ne 0 ]; then
            log_error "traefik-mesh安装失败"
            return 1
        fi
        log_success "traefik-mesh安装完成"
        verify_step "${V3}/verify-37-install-traefik-mesh.sh" "traefik-mesh"
        if [ $? -ne 0 ]; then
            log_error "traefik-mesh验证失败"
            return 1
        fi
        step_done "3.11"
    fi

    # 3.12 更新CoreDNS配置（主控制节点，依赖 Traefik）
    if ! ecosystem_enabled "traefik" || ! ecosystem_enabled "coredns_update"; then
        log_info "[跳过] 3.12 更新CoreDNS配置（配置中已禁用）"
    elif step_is_done "3.12"; then
        log_info "[跳过] 3.12 更新CoreDNS配置（已完成）"
    else
        log_info "更新coredns配置..."
        exec_script_on_control_plane "${P3}/39-update-coredns.sh"
        if [ $? -ne 0 ]; then
            log_error "coredns更新失败"
            return 1
        fi
        log_success "coredns更新完成"
        verify_step "${V3}/verify-39-update-coredns.sh" "coredns"
        if [ $? -ne 0 ]; then
            log_error "coredns验证失败"
            return 1
        fi
        step_done "3.12"
    fi

    # 3.13 安装Metrics Server（主控制节点）
    if ! ecosystem_enabled "metrics_server"; then
        log_info "[跳过] 3.13 安装Metrics Server（配置中已禁用）"
    elif step_is_done "3.13"; then
        log_info "[跳过] 3.13 安装Metrics Server（已完成）"
    else
        log_info "安装metrics-server..."
        exec_script_on_control_plane "${P3}/40-install-metrics-server.sh"
        if [ $? -ne 0 ]; then
            log_error "metrics-server安装失败"
            return 1
        fi
        log_success "metrics-server安装完成"
        verify_step "${V3}/verify-40-install-metrics-server.sh" "metrics-server"
        if [ $? -ne 0 ]; then
            log_error "metrics-server验证失败"
            return 1
        fi
        step_done "3.13"
    fi

    # 3.14 配置普通用户kubectl权限（主控制节点）
    if ! ecosystem_enabled "kubectl_permission"; then
        log_info "[跳过] 3.14 配置kubectl权限（配置中已禁用）"
    elif step_is_done "3.14"; then
        log_info "[跳过] 3.14 配置kubectl权限（已完成）"
    else
        log_info "配置kubectl权限..."
        exec_script_on_control_plane "${P3}/41-setup-kubectl-permission.sh"
        if [ $? -ne 0 ]; then
            log_error "kubectl权限配置失败"
            return 1
        fi
        log_success "kubectl权限配置完成"
        verify_step "${V3}/verify-41-setup-kubectl-permission.sh" "kubectl权限"
        if [ $? -ne 0 ]; then
            log_error "kubectl权限验证失败"
            return 1
        fi
        step_done "3.14"
    fi

    # 3.15 配置F5高可用（所有控制节点）
    if ! ecosystem_enabled "f5_ha"; then
        log_info "[跳过] 3.15 配置F5高可用（配置中已禁用）"
    elif step_is_done "3.15"; then
        log_info "[跳过] 3.15 配置F5高可用（已完成）"
    else
        log_info "配置F5高可用..."
        exec_script_on_control_plane "${P3}/42-setup-f5-ha.sh"
        if [ $? -ne 0 ]; then
            log_error "F5高可用配置失败"
            return 1
        fi
        log_success "F5高可用配置完成"
        verify_step "${V3}/verify-42-setup-f5-ha.sh" "F5高可用"
        if [ $? -ne 0 ]; then
            log_error "F5高可用验证失败"
            return 1
        fi
        step_done "3.15"
    fi

    # 3.16 安装Redis哨兵模式（主控制节点，可选）
    if ! ecosystem_enabled "redis_sentinel" false; then
        log_info "[跳过] 3.16 安装Redis哨兵模式（配置中已禁用）"
    elif step_is_done "3.16"; then
        log_info "[跳过] 3.16 安装Redis哨兵模式（已完成）"
    else
        log_info "安装redis哨兵模式..."
        exec_script_on_control_plane "${P3}/43-install-redis-sentinel.sh"
        if [ $? -ne 0 ]; then
            log_warn "redis哨兵模式安装失败（可选组件，不影响主流程）"
        else
            log_success "redis哨兵模式安装完成"
            verify_step "${V3}/verify-43-install-redis-sentinel.sh" "redis哨兵"
            if [ $? -ne 0 ]; then
                log_warn "redis哨兵验证失败（可选组件，不影响主流程）"
            fi
        fi
        step_done "3.16"
    fi

    # 3.17 配置定时任务
    if ! ecosystem_enabled "etcd_backup"; then
        log_info "[跳过] 3.17 配置ETCD备份定时任务（配置中已禁用）"
    elif step_is_done "3.17a"; then
        log_info "[跳过] 3.17 配置ETCD备份定时任务（已完成）"
    else
        log_info "配置ETCD备份定时任务..."
        exec_script_on_control_plane "${P3}/44-setup-etcd-backup.sh"
        if [ $? -ne 0 ]; then
            log_error "ETCD备份定时任务配置失败"
            return 1
        fi
        log_success "ETCD备份定时任务配置完成"
        verify_step "${V3}/verify-44-setup-etcd-backup.sh" "ETCD备份定时任务"
        if [ $? -ne 0 ]; then
            log_error "ETCD备份定时任务验证失败"
            return 1
        fi
        step_done "3.17a"
    fi

    if ! ecosystem_enabled "traefik" || ! ecosystem_enabled "traefik_cleanup"; then
        log_info "[跳过] 3.17 配置Traefik清理定时任务（配置中已禁用）"
    elif step_is_done "3.17b"; then
        log_info "[跳过] 3.17 配置Traefik清理定时任务（已完成）"
    else
        log_info "配置Traefik清理定时任务..."
        exec_script_on_control_plane "${P3}/45-setup-traefik-cleanup.sh"
        if [ $? -ne 0 ]; then
            log_error "Traefik清理定时任务配置失败"
            return 1
        fi
        log_success "Traefik清理定时任务配置完成"
        verify_step "${V3}/verify-45-setup-traefik-cleanup.sh" "Traefik清理定时任务"
        if [ $? -ne 0 ]; then
            log_error "Traefik清理定时任务验证失败"
            return 1
        fi
        step_done "3.17b"
    fi

    if ! ecosystem_enabled "log_cleanup"; then
        log_info "[跳过] 3.17 配置日志清理定时任务（配置中已禁用）"
    elif step_is_done "3.17c"; then
        log_info "[跳过] 3.17 配置日志清理定时任务（已完成）"
    else
        log_info "配置日志清理定时任务..."
        exec_script_on_workers "${P3}/46-setup-log-cleanup.sh"
        if [ $? -ne 0 ]; then
            log_error "日志清理定时任务配置失败"
            return 1
        fi
        log_success "日志清理定时任务配置完成"
        verify_step "${V3}/verify-46-setup-log-cleanup.sh" "日志清理定时任务"
        if [ $? -ne 0 ]; then
            log_error "日志清理定时任务验证失败"
            return 1
        fi
        step_done "3.17c"
    fi

    log_success "生态系统组件安装完成"
}

#===============================================================================
# 函数：main()
# 功能：主函数
#===============================================================================
main() {
    # 解析命令行参数
    parse_arguments "$@"

    # 初始化日志
    init_log "$LOG_FILE"

    log_separator
    log_info "KubeFoundry - Kubernetes 集群一键安装工具"
    log_info "版本: 1.0.0"
    log_info "开始时间: $(_log_timestamp)"
    log_separator

    if [ "$VERBOSE" = true ]; then
        log_info "配置文件: ${CONFIG_FILE}"
        log_info "日志文件: ${LOG_FILE}"
        log_info "执行步骤: ${STEP}"
    fi

    # 模拟运行提示
    if [ "$DRY_RUN" = true ]; then
        log_warn "模拟运行模式：不会执行实际操作"
    fi

    # 初始化进度跟踪
    progress_init
    if [ "$RESET_PROGRESS" = true ]; then
        progress_reset
        RESET_PROGRESS=false
    fi

    # 跳过验证提示
    if [ "$SKIP_VERIFY" = true ]; then
        log_warn "跳过验证步骤：不推荐在生产环境使用"
    fi

    # 根据步骤执行
    local exit_code=0

    case "$STEP" in
        all)
            if ! run_precheck; then
                exit_code=1
            elif ! run_k8s_base; then
                exit_code=1
            elif ! run_ecosystem; then
                exit_code=1
            fi
            ;;
        precheck)
            if ! run_precheck; then
                exit_code=1
            fi
            ;;
        k8s_base)
            if ! run_precheck; then
                exit_code=1
            elif ! run_k8s_base; then
                exit_code=1
            fi
            ;;
        ecosystem)
            if ! run_precheck; then
                exit_code=1
            elif ! run_k8s_base; then
                exit_code=1
            elif ! run_ecosystem; then
                exit_code=1
            fi
            ;;
        *)
            log_error "未知步骤: ${STEP}"
            show_usage
            exit_code=1
            ;;
    esac

    # 输出结束信息
    log_separator
    if [ $exit_code -eq 0 ]; then
        log_success "所有步骤执行成功"
        progress_clean
    else
        log_error "部分步骤执行失败，修复后重新运行将自动跳过已完成步骤（使用 --reset 从头执行）"
    fi
    log_info "结束时间: $(_log_timestamp)"
    log_separator

    print_log_file

    exit $exit_code
}

# 执行主函数
main "$@"
