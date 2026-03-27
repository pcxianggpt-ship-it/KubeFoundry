#!/bin/bash

#===============================================================================
# 脚本名称：logger.sh
# 功能：日志输出函数库
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 日志文件路径
LOG_FILE="/tmp/kubefoundry_install.log"

# 日志颜色定义
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'

#===============================================================================
# 函数：_log_timestamp()
# 功能：生成日志时间戳
# 返回值：
#   时间戳字符串（YYYY-MM-DD HH:MM:SS）
#===============================================================================
_log_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

#===============================================================================
# 函数：_log_write()
# 功能：写入日志到文件
# 参数：
#   $@ - 日志内容
# 返回值：
#   无
#===============================================================================
_log_write() {
    local timestamp
    timestamp=$(_log_timestamp)
    echo "[${timestamp}] $*" >> "${LOG_FILE}"
}

#===============================================================================
# 函数：log_info()
# 功能：输出 INFO 级别日志（蓝色）
# 参数：
#   $@ - 日志内容（支持多个参数）
# 返回值：
#   无
#===============================================================================
log_info() {
    local message="$*"
    local timestamp
    timestamp=$(_log_timestamp)

    # 输出到终端
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} ${message}"

    # 写入日志文件
    _log_write "[INFO] ${message}"
}

#===============================================================================
# 函数：log_success()
# 功能：输出 SUCCESS 级别日志（绿色）
# 参数：
#   $@ - 日志内容（支持多个参数）
# 返回值：
#   无
#===============================================================================
log_success() {
    local message="$*"
    local timestamp
    timestamp=$(_log_timestamp)

    # 输出到终端
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} ${message}"

    # 写入日志文件
    _log_write "[SUCCESS] ${message}"
}

#===============================================================================
# 函数：log_warn()
# 功能：输出 WARN 级别日志（黄色）
# 参数：
#   $@ - 日志内容（支持多个参数）
# 返回值：
#   无
#===============================================================================
log_warn() {
    local message="$*"
    local timestamp
    timestamp=$(_log_timestamp)

    # 输出到终端
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} ${message}"

    # 写入日志文件
    _log_write "[WARN] ${message}"
}

#===============================================================================
# 函数：log_error()
# 功能：输出 ERROR 级别日志（红色）
# 参数：
#   $@ - 日志内容（支持多个参数）
# 返回值：
#   无
#===============================================================================
log_error() {
    local message="$*"
    local timestamp
    timestamp=$(_log_timestamp)

    # 输出到终端（stderr）
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} ${message}" >&2

    # 写入日志文件
    _log_write "[ERROR] ${message}"
}

#===============================================================================
# 函数：log_debug()
# 功能：输出 DEBUG 级别日志（灰色）
# 参数：
#   $@ - 日志内容（支持多个参数）
# 返回值：
#   无
# 说明：
#   仅在 verbose_logging 为 true 时输出
#===============================================================================
log_debug() {
    local message="$*"
    local verbose_logging
    verbose_logging=$(config_get '.advanced.verbose_logging' 'false' 2>/dev/null)

    if [ "$verbose_logging" = "true" ]; then
        local timestamp
        timestamp=$(_log_timestamp)

        # 输出到终端
        echo -e "\033[0;90m[DEBUG]${COLOR_RESET} ${message}"

        # 写入日志文件
        _log_write "[DEBUG] ${message}"
    fi
}

#===============================================================================
# 函数：log_separator()
# 功能：输出分隔线
# 参数：
#   无
# 返回值：
#   无
#===============================================================================
log_separator() {
    local line="==============================================================================="
    echo "$line"
    _log_write "$line"
}

#===============================================================================
# 函数：log_step()
# 功能：输出步骤标题
# 参数：
#   $1 - 步骤编号
#   $2 - 步骤名称
# 返回值：
#   无
#===============================================================================
log_step() {
    local step_num="$1"
    local step_name="$2"

    log_separator
    log_info "步骤 ${step_num}: ${step_name}"
    log_separator
}

#===============================================================================
# 函数：log_substep()
# 功能：输出子步骤标题
# 参数：
#   $1 - 子步骤名称
# 返回值：
#   无
#===============================================================================
log_substep() {
    local substep_name="$1"

    log_info "└─ ${substep_name}"
}

#===============================================================================
# 函数：log_node()
# 功能：输出节点操作日志
# 参数：
#   $1 - 节点类型（control_plane, worker, registry）
#   $2 - 节点标识（IP 或 hostname）
#   $3 - 操作描述
# 返回值：
#   无
#===============================================================================
log_node() {
    local node_type="$1"
    local node_id="$2"
    local operation="$3"

    local type_label
    case "$node_type" in
        control_plane)
            type_label="[控制节点]"
            ;;
        worker)
            type_label="[工作节点]"
            ;;
        registry)
            type_label="[镜像仓库]"
            ;;
        *)
            type_label="[节点]"
            ;;
    esac

    log_info "${type_label} ${node_id}: ${operation}"
}

#===============================================================================
# 函数：init_log()
# 功能：初始化日志文件
# 参数：
#   $1 - 日志文件路径（可选，默认使用 /tmp/kubefoundry_install.log）
# 返回值：
#   无
#===============================================================================
init_log() {
    local log_path="${1:-$LOG_FILE}"

    # 创建日志文件目录（如果不存在）
    local log_dir
    log_dir=$(dirname "$log_path")

    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
    fi

    # 清空或创建日志文件
    > "$log_path"

    # 更新全局日志文件路径
    LOG_FILE="$log_path"

    # 写入日志头
    _log_write "=== KubeFoundry 安装日志 ==="
    _log_write "开始时间: $(_log_timestamp)"
    _log_write "集群名称: $(get_cluster_name 2>/dev/null || 'unknown')"
    _log_write "K8S 版本: $(get_k8s_version 2>/dev/null || 'unknown')"
    _log_write ""
}

#===============================================================================
# 函数：log_command()
# 功能：记录执行的命令
# 参数：
#   $@ - 命令内容
# 返回值：
#   无
#===============================================================================
log_command() {
    log_debug "执行命令: $*"
}

#===============================================================================
# 函数：log_result()
# 功能：记录命令执行结果
# 参数：
#   $1 - 退出码
#   $2 - 命令描述（可选）
# 返回值：
#   无
#===============================================================================
log_result() {
    local exit_code="$1"
    local description="${2:-命令}"

    if [ "$exit_code" -eq 0 ]; then
        log_success "${description} 执行成功"
    else
        log_error "${description} 执行失败，退出码: ${exit_code}"
    fi
}

#===============================================================================
# 函数：log_file()
# 功能：记录文件操作
# 参数：
#   $1 - 操作类型（create, delete, modify, read）
#   $2 - 文件路径
#   $3 - 附加信息（可选）
# 返回值：
#   无
#===============================================================================
log_file() {
    local operation="$1"
    local file_path="$2"
    local extra_info="${3:-}"

    local operation_label
    case "$operation" in
        create)
            operation_label="创建"
            ;;
        delete)
            operation_label="删除"
            ;;
        modify)
            operation_label="修改"
            ;;
        read)
            operation_label="读取"
            ;;
        *)
            operation_label="${operation}"
            ;;
    esac

    local message="${operation_label}文件: ${file_path}"

    if [ -n "$extra_info" ]; then
        message="${message} (${extra_info})"
    fi

    log_debug "${message}"
}

#===============================================================================
# 函数：print_log_file()
# 功能：打印日志文件路径
# 参数：
#   无
# 返回值：
#   无
#===============================================================================
print_log_file() {
    echo "日志文件: ${LOG_FILE}"
}
