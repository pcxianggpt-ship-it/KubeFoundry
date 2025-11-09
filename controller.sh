#!/bin/bash
# controller.sh - KubeFoundry 主控制脚本
# 负责协调整个 Kubernetes 集群的部署流程

# 启用严格模式
set -euo pipefail

# 获取脚本目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}" && pwd)"

# 加载依赖模块
source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/state-manager.sh"
source "${PROJECT_ROOT}/lib/config-parser.sh"

# 全局变量
CONFIG_FILE=""
DEPLOYMENT_ID=""
VERBOSE=false
DRY_RUN=false
RESUME=false
SKIP_STEP=""
ONLY_STEP=""
FORCE_REDEPLOY=false
PARALLEL_EXECUTION=true
MAX_PARALLEL_NODES=10

# 步骤定义
declare -A DEPLOYMENT_STEPS=(
    [1]="root-check"
    [2]="ssh-keys"
    [3]="dependencies"
    [4]="k8s-components"
    [5]="system-config"
    [6]="container-runtime"
    [7]="registry"
    [8]="cluster-init"
    [9]="controller-config"
    [10]="control-plane"
    [11]="worker-nodes"
    [12]="cni-network"
    [13]="nfs-storage"
    [14]="addons"
    [15]="backup"
)

declare -A STEP_DESCRIPTIONS=(
    [1]="Root 用户权限验证"
    [2]="SSH 密钥分发和免密登录"
    [3]="依赖检查与离线 RPM 安装"
    [4]="Kubernetes 组件安装"
    [5]="系统参数配置"
    [6]="容器运行时安装和配置"
    [7]="私有镜像仓库部署"
    [8]="Kubernetes 集群初始化"
    [9]="kube-controller-manager 参数配置"
    [10]="控制平面节点添加"
    [11]="工作节点添加"
    [12]="CNI 网络插件安装"
    [13]="NFS 存储配置"
    [14]="扩展组件部署"
    [15]="etcd 备份配置"
)

# 显示帮助信息
show_help() {
    cat << EOF
KubeFoundry - Kubernetes 离线自动化部署系统

用法: $(basename "$0") [选项]

选项:
    -c, --config FILE         配置文件路径 (默认: config/deploy-config.yaml)
    -v, --verbose             详细输出
    -d, --dry-run            模拟运行，不执行实际操作
    -r, --resume             从失败的步骤继续部署
    -s, --skip STEP          跳过指定步骤 (数字或名称)
    -o, --only STEP          只执行指定步骤 (数字或名称)
    -f, --force              强制重新部署，忽略已有状态
    -p, --parallel           并行执行节点操作 (默认启用)
    --no-parallel            禁用并行执行
    --max-parallel NUM       最大并行节点数 (默认: 10)
    --validate-only          仅验证配置文件，不执行部署
    --generate-config        生成配置文件示例
    --show-status            显示当前部署状态
    --reset-state            重置部署状态
    -h, --help              显示此帮助信息

步骤说明:
    1  root-check        - Root 用户权限验证
    2  ssh-keys          - SSH 密钥分发和免密登录
    3  dependencies      - 依赖检查与离线 RPM 安装
    4  k8s-components    - Kubernetes 组件安装
    5  system-config     - 系统参数配置
    6  container-runtime - 容器运行时安装和配置
    7  registry          - 私有镜像仓库部署
    8  cluster-init      - Kubernetes 集群初始化
    9  controller-config - kube-controller-manager 参数配置
    10 control-plane     - 控制平面节点添加
    11 worker-nodes      - 工作节点添加
    12 cni-network       - CNI 网络插件安装
    13 nfs-storage       - NFS 存储配置
    14 addons            - 扩展组件部署
    15 backup            - etcd 备份配置

示例:
    $(basename "$0")                           # 使用默认配置部署
    $(basename "$0") -c my-config.yaml         # 使用指定配置文件
    $(basename "$0") --verbose                 # 详细输出模式
    $(basename "$0") --resume                  # 从失败步骤继续
    $(basename "$0") --skip 7                  # 跳过第7步
    $(basename "$0") --only cluster-init       # 只执行集群初始化
    $(basename "$0") --dry-run                 # 模拟运行
    $(basename "$0") --show-status             # 显示当前状态
    $(basename "$0") --validate-only           # 仅验证配置

EOF
}

# 解析命令行参数
parse_args() {
    CONFIG_FILE="${PROJECT_ROOT}/config/deploy-config.yaml"
    VERBOSE=false
    DRY_RUN=false
    RESUME=false
    SKIP_STEP=""
    ONLY_STEP=""
    FORCE_REDEPLOY=false
    PARALLEL_EXECUTION=true
    MAX_PARALLEL_NODES=10
    VALIDATE_ONLY=false
    GENERATE_CONFIG=false
    SHOW_STATUS=false
    RESET_STATE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--resume)
                RESUME=true
                shift
                ;;
            -s|--skip)
                SKIP_STEP="$2"
                shift 2
                ;;
            -o|--only)
                ONLY_STEP="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_REDEPLOY=true
                shift
                ;;
            -p|--parallel)
                PARALLEL_EXECUTION=true
                shift
                ;;
            --no-parallel)
                PARALLEL_EXECUTION=false
                shift
                ;;
            --max-parallel)
                MAX_PARALLEL_NODES="$2"
                shift 2
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            --generate-config)
                GENERATE_CONFIG=true
                shift
                ;;
            --show-status)
                SHOW_STATUS=true
                shift
                ;;
            --reset-state)
                RESET_STATE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 生成配置文件示例
generate_config_file() {
    local output_file="${1:-config/deploy-config.yaml}"

    if [[ -f "${output_file}" ]]; then
        read -p "配置文件已存在，是否覆盖? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "取消生成配置文件"
            exit 0
        fi
    fi

    cp "${PROJECT_ROOT}/config/deploy-config.yaml.example" "${output_file}"
    log_info "配置文件已生成: ${output_file}"
    log_info "请根据实际环境修改配置文件，然后重新运行部署"
}

# 验证环境
validate_environment() {
    log_info "验证部署环境..."

    # 检查操作系统
    local os
    os=$(detect_operating_system)
    log_info "操作系统: ${os}"

    case "${os}" in
        rhel|centos|almalinux|oracle)
            log_info "支持的操作系统: ${os}"
            ;;
        *)
            log_warn "未经过充分测试的操作系统: ${os}"
            ;;
    esac

    # 检查系统架构
    local arch
    arch=$(detect_architecture)
    log_info "系统架构: ${arch}"

    # 检查系统资源
    if ! check_memory 2048; then
        log_error "系统内存不足，至少需要 2GB 内存"
        return 1
    fi

    if ! check_disk_space "${PROJECT_ROOT}" 10240; then
        log_error "磁盘空间不足，至少需要 10GB 可用空间"
        return 1
    fi

    # 检查必需命令
    local required_commands=("bash" "ssh" "scp" "tar" "gzip")
    if [[ "${VERBOSE}" == "true" ]]; then
        required_commands+=("yq" "jq" "curl")
    fi

    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_error "缺少必需命令: ${cmd}"
            return 1
        fi
    done

    log_info "环境验证通过"
    return 0
}

# 解析步骤参数
parse_step_argument() {
    local step_arg="$1"
    local step_num=""

    # 检查是否为数字
    if [[ "${step_arg}" =~ ^[0-9]+$ ]]; then
        if [[ ${step_arg} -ge 1 ]] && [[ ${step_arg} -le 15 ]]; then
            step_num="${step_arg}"
        else
            log_error "无效的步骤编号: ${step_arg} (1-15)"
            return 1
        fi
    else
        # 通过名称查找步骤编号
        for num in {1..15}; do
            if [[ "${DEPLOYMENT_STEPS[${num}]}" == "${step_arg}" ]]; then
                step_num="${num}"
                break
            fi
        done

        if [[ -z "${step_num}" ]]; then
            log_error "未知的步骤名称: ${step_arg}"
            log_info "可用的步骤名称:"
            for num in {1..15}; do
                echo "  ${num} ${DEPLOYMENT_STEPS[${num}]}"
            done
            return 1
        fi
    fi

    echo "${step_num}"
}

# 执行部署步骤
execute_step() {
    local step_num="$1"
    local step_name="${DEPLOYMENT_STEPS[${step_num}]}"
    local step_desc="${STEP_DESCRIPTIONS[${step_num}]}"
    local step_script="${STEPS_DIR}/step-$(printf "%02d" ${step_num})-${step_name}.sh"

    log_step_start "${step_desc}" "${step_num}" "15"

    local start_time
    start_time=$(date +%s)

    # 更新步骤状态为进行中
    update_step_state "${step_num}" "IN_PROGRESS"

    # 检查步骤脚本是否存在
    if [[ ! -f "${step_script}" ]]; then
        local error_msg="步骤脚本不存在: ${step_script}"
        log_error "${error_msg}"
        update_step_state "${step_num}" "FAILED" "${error_msg}"
        log_step_failed "${step_desc}" "${step_num}" "15" "${error_msg}" "$(format_duration $(( $(date +%s) - start_time )))"
        return 1
    fi

    # 执行步骤脚本
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] 将执行: ${step_script}"
        update_step_state "${step_num}" "COMPLETED"
        log_step_complete "${step_desc}" "${step_num}" "15" "$(format_duration $(( $(date +%s) - start_time )))"
        return 0
    else
        local exit_code=0

        # 在锁中执行步骤
        if with_lock "step-${step_num}" 3600 bash "${step_script}" "${CONFIG_FILE}" "${PROJECT_ROOT}"; then
            exit_code=$?
        else
            exit_code=$?
        fi

        local duration
        duration=$(format_duration $(( $(date +%s) - start_time )))

        if [[ ${exit_code} -eq 0 ]]; then
            update_step_state "${step_num}" "COMPLETED"
            log_step_complete "${step_desc}" "${step_num}" "15" "${duration}"
            return 0
        else
            local error_msg="步骤脚本执行失败 (退出码: ${exit_code})"
            log_error "${error_msg}"
            update_step_state "${step_num}" "FAILED" "${error_msg}"
            log_step_failed "${step_desc}" "${step_num}" "15" "${error_msg}" "${duration}"
            return 1
        fi
    fi
}

# 执行部署流程
execute_deployment() {
    local start_time
    start_time=$(date +%s)
    local deployment_id
    deployment_id="kubefoundry-$(date '+%Y%m%d_%H%M%S')"

    # 初始化状态管理器
    init_state_manager

    # 更新部署信息
    local updated_state
    updated_state=$(jq --arg id "${deployment_id}" --arg time "$(date -Iseconds)" '
        .deployment_id = $id |
        .start_time = $time |
        .overall_status = "IN_PROGRESS"
    ' "${STATE_FILE}")

    echo "${updated_state}" > "${STATE_FILE}"

    log_info "开始部署流程 (ID: ${deployment_id})"

    # 确定执行范围
    local start_step=1
    local end_step=15

    if [[ -n "${ONLY_STEP}" ]]; then
        start_step=$(parse_step_argument "${ONLY_STEP}")
        end_step="${start_step}"
    elif [[ "${RESUME}" == "true" ]]; then
        local next_step
        next_step=$(get_next_pending_step)
        if [[ "${next_step}" == "null" ]]; then
            log_info "没有待执行的步骤"
            show_deployment_summary
            return 0
        fi
        start_step="${next_step}"
    fi

    # 执行步骤
    for ((step_num = start_step; step_num <= end_step; step_num++)); do
        local step_name="${DEPLOYMENT_STEPS[${step_num}]}"
        local step_desc="${STEP_DESCRIPTIONS[${step_num}]}"

        # 检查是否需要跳过
        if [[ -n "${SKIP_STEP}" ]]; then
            local skip_step_num
            skip_step_num=$(parse_step_argument "${SKIP_STEP}")
            if [[ ${step_num} -eq ${skip_step_num} ]]; then
                log_info "跳过步骤 ${step_num}: ${step_desc}"
                update_step_state "${step_num}" "SKIPPED"
                continue
            fi
        fi

        # 检查步骤是否已完成（除非强制重新部署）
        if [[ "${FORCE_REDEPLOY}" != "true" ]] && is_step_completed "${step_num}"; then
            log_info "步骤 ${step_num} 已完成，跳过"
            continue
        fi

        # 执行步骤
        if ! execute_step "${step_num}"; then
            log_error "步骤 ${step_num} 执行失败，部署流程中断"
            return 1
        fi
    done

    # 更新整体状态
    local total_duration
    total_duration=$(format_duration $(( $(date +%s) - start_time )))

    local final_state
    final_state=$(jq --arg time "$(date -Iseconds)" --arg duration "${total_duration}" '
        .overall_status = "COMPLETED" |
        .end_time = $time |
        .total_duration = $duration
    ' "${STATE_FILE}")

    echo "${final_state}" > "${STATE_FILE}"

    log_info "部署流程完成! 总耗时: ${total_duration}"
    show_deployment_summary
    return 0
}

# 处理失败步骤
handle_failure() {
    log_error "部署流程失败"

    # 显示失败步骤
    local failed_steps
    failed_steps=$(get_failed_steps)

    if [[ -n "${failed_steps}" ]]; then
        log_error "失败的步骤:"
        for step in ${failed_steps}; do
            local step_name="${DEPLOYMENT_STEPS[${step}]}"
            local step_state
            step_state=$(get_step_state "${step}")
            local error_message
            error_message=$(echo "${step_state}" | jq -r '.error_message // "未知错误"')
            log_error "  步骤 ${step}: ${step_name} - ${error_message}"
        done
    fi

    log_info "使用 --resume 选项可以从失败步骤继续部署"
    log_info "使用 --show-status 选项查看详细状态"
}

# 清理函数
cleanup() {
    # 释放所有锁
    if [[ -d "${LOCK_DIR}" ]]; then
        find "${LOCK_DIR}" -name "*.lock" -type f -delete 2>/dev/null || true
    fi

    log_info "部署流程清理完成"
}

# 主函数
main() {
    # 设置清理陷阱
    trap cleanup EXIT INT TERM

    # 解析命令行参数
    parse_args "$@"

    # 初始化日志系统
    init_logger

    # 显示横幅
    if [[ "${VALIDATE_ONLY}" != "true" ]] && [[ "${SHOW_STATUS}" != "true" ]] && [[ "${GENERATE_CONFIG}" != "true" ]] && [[ "${RESET_STATE}" != "true" ]]; then
        cat << 'EOF'
 _                     _            _
| |                   | |          | |
| |     ___   __ _  __| | ___ _ __ | |_
| |    / _ \ / _` |/ _` |/ _ \ '_ \| __|
| |___| (_) | (_| | (_| |  __/ | | | |_
|______\___/ \__, |\__,_|\___|_| |_|\__|
              __/ |
             |___/

Kubernetes 离线自动化部署系统
EOF
        echo ""
    fi

    # 处理特殊命令
    if [[ "${GENERATE_CONFIG}" == "true" ]]; then
        generate_config_file
        exit 0
    fi

    if [[ "${RESET_STATE}" == "true" ]]; then
        create_initial_state
        log_info "部署状态已重置"
        exit 0
    fi

    if [[ "${SHOW_STATUS}" == "true" ]]; then
        if load_config; then
            show_deployment_summary
        else
            log_error "无法加载配置文件"
            exit 1
        fi
        exit 0
    fi

    # 验证环境
    if ! validate_environment; then
        log_error "环境验证失败"
        exit 1
    fi

    # 加载并验证配置文件
    log_info "加载配置文件: ${CONFIG_FILE}"
    if ! load_config "${CONFIG_FILE}"; then
        log_error "配置文件加载失败"
        exit 1
    fi

    if ! validate_config_integrity "${CONFIG_FILE}"; then
        log_error "配置文件验证失败"
        exit 1
    fi

    if [[ "${VALIDATE_ONLY}" == "true" ]]; then
        log_info "配置文件验证通过"
        exit 0
    fi

    # 执行部署流程
    if execute_deployment; then
        log_success "KubeFoundry 部署成功完成!"
        exit 0
    else
        handle_failure
        exit 1
    fi
}

# 检查是否直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi