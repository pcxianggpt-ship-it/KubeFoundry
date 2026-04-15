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

#===============================================================================
# 函数：show_usage()
# 功能：显示使用帮助
# 参数：
#   无
# 返回值：
#   无
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
  # 执行所有步骤
  $(basename "$0") all

  # 执行预检查
  $(basename "$0") precheck

  # 指定配置文件
  $(basename "$0") -c config/my-cluster.yaml all

  # 启用详细日志
  $(basename "$0") -V all

  # 模拟运行
  $(basename "$0") -d all

更多信息请访问: https://github.com/kubefoundry/kubefoundry
EOF
}

#===============================================================================
# 函数：show_version()
# 功能：显示版本信息
# 参数：
#   无
# 返回值：
#   无
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
# 参数：
#   $@ - 所有命令行参数
# 返回值：
#   0 - 成功
#   1 - 失败
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
}

#===============================================================================
# 函数：run_step()
# 功能：执行单个步骤
# 参数：
#   $1 - 步骤脚本路径
#   $2 - 步骤名称
# 返回值：
#   0 - 成功
#   非 0 - 失败
#===============================================================================
run_step() {
    local step_script="$1"
    local step_name="$2"

    if [ ! -f "$step_script" ]; then
        log_error "步骤脚本不存在: ${step_script}"
        return 1
    fi

    log_substep "${step_name}"

    if [ "$DRY_RUN" = true ]; then
        log_warn "模拟运行: ${step_script} (未实际执行)"
        return 0
    fi

    # 执行步骤脚本
    bash "$step_script"
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_success "${step_name} 完成"
        return 0
    else
        log_error "${step_name} 失败，退出码: ${exit_code}"
        return $exit_code
    fi
}

#===============================================================================
# 函数：run_phase()
# 功能：执行一个阶段的所有步骤
# 参数：
#   $1 - 阶段目录路径
#   $2 - 阶段名称
# 返回值：
#   0 - 所有步骤成功
#   非 0 - 至少一个步骤失败
#===============================================================================
run_phase() {
    local phase_dir="$1"
    local phase_name="$2"
    local success=true

    log_step "${phase_name}"

    # 查找并执行该阶段的所有步骤脚本
    for step_script in "${phase_dir}"/*.sh; do
        if [ -f "$step_script" ]; then
            local step_name
            step_name=$(basename "$step_script" .sh)

            if ! run_step "$step_script" "$step_name"; then
                success=false
                break
            fi
        fi
    done

    if [ "$success" = true ]; then
        log_success "${phase_name} 完成"
        return 0
    else
        log_error "${phase_name} 失败"
        return 1
    fi
}

#===============================================================================
# 函数：run_precheck()
# 功能：执行预检查阶段
# 返回值：
#   0 - 成功
#   非 0 - 失败
#===============================================================================
run_precheck() {
    run_phase "${SCRIPT_DIR}/steps/phase1_precheck" "预检查阶段"
}

#===============================================================================
# 函数：run_k8s_base()
# 功能：执行 K8S 基础环境安装阶段
# 返回值：
#   0 - 成功
#   非 0 - 失败
#===============================================================================
run_k8s_base() {
    run_phase "${SCRIPT_DIR}/steps/phase2_k8s_base" "K8S 基础环境安装"
}

#===============================================================================
# 函数：run_ecosystem()
# 功能：执行生态系统组件安装阶段
# 返回值：
#   0 - 成功
#   非 0 - 失败
#===============================================================================
run_ecosystem() {
    run_phase "${SCRIPT_DIR}/steps/phase3_ecosystem" "生态系统组件安装"
}

#===============================================================================
# 函数：main()
# 功能：主函数
# 返回值：
#   0 - 成功
#   非 0 - 失败
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

    # 确保 yq/helm 可用（load_config 依赖 yq 解析 YAML）
    bash "${SCRIPT_DIR}/lib/tools.sh"
    if [ $? -ne 0 ]; then
        exit 1
    fi

    # 加载配置文件
    log_info "加载配置文件..."
    if ! load_config "$CONFIG_FILE"; then
        log_error "配置文件加载失败"
        exit 1
    fi

    log_success "配置文件加载成功"

    # 根据步骤执行
    local exit_code=0

    case "$STEP" in
        all)
            # 执行所有步骤
            if ! run_precheck; then
                exit_code=1
            elif ! run_k8s_base; then
                exit_code=1
            elif ! run_ecosystem; then
                exit_code=1
            fi
            ;;
        precheck)
            # 只执行预检查
            if ! run_precheck; then
                exit_code=1
            fi
            ;;
        k8s_base)
            # 执行预检查 + K8S 基础环境
            if ! run_precheck; then
                exit_code=1
            elif ! run_k8s_base; then
                exit_code=1
            fi
            ;;
        ecosystem)
            # 执行预检查 + K8S 基础环境 + 生态系统
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
