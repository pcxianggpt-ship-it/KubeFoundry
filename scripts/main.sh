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
    export CONFIG_FILE LOG_FILE DRY_RUN SKIP_VERIFY VERBOSE
}

#===============================================================================
# 步骤脚本路径
#===============================================================================
STEPS="${SCRIPT_DIR}/steps"
P1="${STEPS}/phase1_precheck"
P2="${STEPS}/phase2_k8s_base"
P3="${STEPS}/phase3_ecosystem"

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
    log_info "配置本地yum源..."
    local repo_source
    repo_source=$(config_get '.paths.repo_source')
    ( cd "${PROJECT_ROOT}"; source "${P2}/10-setup-yum-source.sh" "$repo_source" )
    if [ $? -ne 0 ]; then
        log_error "配置yum源失败"
        return 1
    fi
    log_success "yum源配置完成"

    # 2.2 配置SSH免密登录（管理节点本地执行）
    log_info "配置SSH免密登录..."
    ( cd "${PROJECT_ROOT}"; source "${P2}/11-setup-ssh-login.sh" )
    if [ $? -ne 0 ]; then
        log_error "SSH免密登录配置失败"
        return 1
    fi
    log_success "SSH免密登录配置完成"

    # 2.3 配置本地k8s repo源客户端（除主控制节点外所有节点）
    log_info "配置k8s repo源客户端..."
    exec_script_on_workers "${P2}/12-setup-k8s-repo.sh"
    if [ $? -ne 0 ]; then
        log_error "k8s repo源配置失败"
        return 1
    fi
    log_success "k8s repo源配置完成"

    # 2.4 安装K8s依赖包（所有节点）
    log_info "安装K8s依赖包..."
    exec_script_on_all_nodes "${P2}/13-install-k8s-deps.sh"
    if [ $? -ne 0 ]; then
        log_error "K8s依赖包安装失败"
        return 1
    fi
    log_success "K8s依赖包安装完成"

    # 2.5 替换kubeadm为支持100年证书版本（仅主控制节点）
    log_info "替换kubeadm..."
    exec_script_on_control_plane "${P2}/14-replace-kubeadm.sh"
    if [ $? -ne 0 ]; then
        log_error "kubeadm替换失败"
        return 1
    fi
    log_success "kubeadm替换完成"

    # 2.6 环境配置（所有节点）
    log_info "执行环境配置..."
    exec_script_on_all_nodes "${P2}/15-environment-config.sh"
    if [ $? -ne 0 ]; then
        log_error "环境配置失败"
        return 1
    fi
    log_success "环境配置完成"

    # 2.7 安装containerd（所有节点）
    log_info "安装containerd..."
    exec_script_on_all_nodes "${P2}/16-install-containerd.sh"
    if [ $? -ne 0 ]; then
        log_error "containerd安装失败"
        return 1
    fi
    log_success "containerd安装完成"

    # 2.8 安装镜像仓库（registry节点）
    log_info "安装镜像仓库..."
    exec_script_on_registry "${P2}/17-install-registry.sh"
    if [ $? -ne 0 ]; then
        log_error "镜像仓库安装失败"
        return 1
    fi
    log_success "镜像仓库安装完成"

    # 2.9 初始化K8S集群（仅主控制节点）
    log_info "初始化K8S集群..."
    exec_script_on_control_plane "${P2}/18-init-k8s-cluster.sh"
    if [ $? -ne 0 ]; then
        log_error "K8S集群初始化失败"
        return 1
    fi
    log_success "K8S集群初始化完成"

    # 2.10 修改证书有效期（仅主控制节点）
    log_info "修改证书有效期..."
    exec_script_on_control_plane "${P2}/19-modify-cert-expiry.sh"
    if [ $? -ne 0 ]; then
        log_error "证书有效期修改失败"
        return 1
    fi
    log_success "证书有效期修改完成"

    # 2.11 添加控制节点（其他控制节点）
    log_info "添加控制节点..."
    exec_script_on_control_plane "${P2}/20-add-control-nodes.sh"
    if [ $? -ne 0 ]; then
        log_error "添加控制节点失败"
        return 1
    fi
    log_success "控制节点添加完成"

    # 2.12 添加工作节点
    log_info "添加工作节点..."
    exec_script_on_workers "${P2}/21-add-worker-nodes.sh"
    if [ $? -ne 0 ]; then
        log_error "添加工作节点失败"
        return 1
    fi
    log_success "工作节点添加完成"

    # 2.13 安装CNI插件-Flannel（仅主控制节点）
    log_info "安装CNI插件Flannel..."
    exec_script_on_control_plane "${P2}/22-install-cni-flannel.sh"
    if [ $? -ne 0 ]; then
        log_error "Flannel安装失败"
        return 1
    fi
    log_success "Flannel安装完成"

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
    log_info "创建命名空间..."
    exec_script_on_control_plane "${P3}/30-create-namespace.sh"
    if [ $? -ne 0 ]; then
        log_error "创建命名空间失败"
        return 1
    fi
    log_success "命名空间创建完成"

    # 3.2 安装kubemate管理界面（主控制节点）
    log_info "安装kubemate管理界面..."
    exec_script_on_control_plane "${P3}/31-install-kubemate-ui.sh"
    if [ $? -ne 0 ]; then
        log_error "kubemate安装失败"
        return 1
    fi
    log_success "kubemate安装完成"

    # 3.3 安装NFS插件（主控制节点）
    log_info "安装NFS插件..."
    exec_script_on_control_plane "${P3}/32-install-nfs.sh"
    if [ $? -ne 0 ]; then
        log_error "NFS安装失败"
        return 1
    fi
    log_success "NFS安装完成"

    # 3.4 安装elasticsearch（主控制节点）
    log_info "安装elasticsearch..."
    exec_script_on_control_plane "${P3}/33-install-elasticsearch.sh"
    if [ $? -ne 0 ]; then
        log_error "elasticsearch安装失败"
        return 1
    fi
    log_success "elasticsearch安装完成"

    # 3.5 安装skywalking（主控制节点）
    log_info "安装skywalking..."
    exec_script_on_control_plane "${P3}/34-install-skywalking.sh"
    if [ $? -ne 0 ]; then
        log_error "skywalking安装失败"
        return 1
    fi
    log_success "skywalking安装完成"

    # 3.6 安装loki（主控制节点）
    log_info "安装loki..."
    exec_script_on_control_plane "${P3}/35-install-loki.sh"
    if [ $? -ne 0 ]; then
        log_error "loki安装失败"
        return 1
    fi
    log_success "loki安装完成"

    # 3.7 安装traefik（主控制节点）
    log_info "安装traefik..."
    exec_script_on_control_plane "${P3}/36-install-traefik.sh"
    if [ $? -ne 0 ]; then
        log_error "traefik安装失败"
        return 1
    fi
    log_success "traefik安装完成"

    # 3.8 安装traefik-mesh（主控制节点）
    log_info "安装traefik-mesh..."
    exec_script_on_control_plane "${P3}/37-install-traefik-mesh.sh"
    if [ $? -ne 0 ]; then
        log_error "traefik-mesh安装失败"
        return 1
    fi
    log_success "traefik-mesh安装完成"

    # 3.9 安装prometheus（主控制节点）
    log_info "安装prometheus..."
    exec_script_on_control_plane "${P3}/38-install-prometheus.sh"
    if [ $? -ne 0 ]; then
        log_error "prometheus安装失败"
        return 1
    fi
    log_success "prometheus安装完成"

    # 3.10 更新coredns配置（主控制节点）
    log_info "更新coredns配置..."
    exec_script_on_control_plane "${P3}/39-update-coredns.sh"
    if [ $? -ne 0 ]; then
        log_error "coredns更新失败"
        return 1
    fi
    log_success "coredns更新完成"

    # 3.11 安装metrics-server（主控制节点）
    log_info "安装metrics-server..."
    exec_script_on_control_plane "${P3}/40-install-metrics-server.sh"
    if [ $? -ne 0 ]; then
        log_error "metrics-server安装失败"
        return 1
    fi
    log_success "metrics-server安装完成"

    # 3.12 配置普通用户kubectl权限（主控制节点）
    log_info "配置kubectl权限..."
    exec_script_on_control_plane "${P3}/41-setup-kubectl-permission.sh"
    if [ $? -ne 0 ]; then
        log_error "kubectl权限配置失败"
        return 1
    fi
    log_success "kubectl权限配置完成"

    # 3.13 配置F5高可用（所有控制节点）
    log_info "配置F5高可用..."
    exec_script_on_control_plane "${P3}/42-setup-f5-ha.sh"
    if [ $? -ne 0 ]; then
        log_error "F5高可用配置失败"
        return 1
    fi
    log_success "F5高可用配置完成"

    # 3.14 安装redis哨兵模式（主控制节点，可选）
    log_info "安装redis哨兵模式..."
    exec_script_on_control_plane "${P3}/43-install-redis-sentinel.sh"
    if [ $? -ne 0 ]; then
        log_warn "redis哨兵模式安装失败（可选组件，不影响主流程）"
    else
        log_success "redis哨兵模式安装完成"
    fi

    # 3.15 配置定时任务
    log_info "配置ETCD备份定时任务..."
    exec_script_on_control_plane "${P3}/44-setup-etcd-backup.sh"
    if [ $? -ne 0 ]; then
        log_error "ETCD备份定时任务配置失败"
        return 1
    fi
    log_success "ETCD备份定时任务配置完成"

    log_info "配置Traefik清理定时任务..."
    exec_script_on_control_plane "${P3}/45-setup-traefik-cleanup.sh"
    if [ $? -ne 0 ]; then
        log_error "Traefik清理定时任务配置失败"
        return 1
    fi
    log_success "Traefik清理定时任务配置完成"

    log_info "配置日志清理定时任务..."
    exec_script_on_workers "${P3}/46-setup-log-cleanup.sh"
    if [ $? -ne 0 ]; then
        log_error "日志清理定时任务配置失败"
        return 1
    fi
    log_success "日志清理定时任务配置完成"

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
    else
        log_error "部分步骤执行失败"
    fi
    log_info "结束时间: $(_log_timestamp)"
    log_separator

    print_log_file

    exit $exit_code
}

# 执行主函数
main "$@"
