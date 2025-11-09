#!/bin/bash
# logger.sh - 日志管理模块
# 提供 KubeFoundry 项目的统一日志记录功能

# 全局日志配置
readonly LOG_DIR="${LOG_DIR:-/root/.k8s-autodeploy/logs}"
readonly LOG_FILE="${LOG_FILE:-${LOG_DIR}/kubefoundry.log}"
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}"
readonly LOG_MAX_SIZE="${LOG_MAX_SIZE:-100M}"
readonly LOG_MAX_FILES="${LOG_MAX_FILES:-5}"

# 日志级别定义
declare -A LOG_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["WARN"]=2
    ["ERROR"]=3
    ["FATAL"]=4
)

# 初始化日志系统
init_logger() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')

    # 创建日志目录
    mkdir -p "${LOG_DIR}" || {
        echo "FATAL: 无法创建日志目录: ${LOG_DIR}" >&2
        exit 1
    }

    # 设置日志文件权限
    touch "${LOG_FILE}" || {
        echo "FATAL: 无法创建日志文件: ${LOG_FILE}" >&2
        exit 1
    }
    chmod 600 "${LOG_FILE}"

    # 日志轮转
    rotate_logs

    # 记录初始化信息
    log_info "KubeFoundry 日志系统初始化完成"
    log_info "日志级别: ${LOG_LEVEL}"
    log_info "日志文件: ${LOG_FILE}"
}

# 日志轮转
rotate_logs() {
    if [[ ! -f "${LOG_FILE}" ]]; then
        return 0
    fi

    local current_size
    current_size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)
    local max_size_bytes
    max_size_bytes=$(echo "${LOG_MAX_SIZE}" | sed 's/M/*1024*1024/;s/K/*1024/;s/G/*1024*1024*1024/' | bc 2>/dev/null || echo 104857600)

    if [[ ${current_size} -gt ${max_size_bytes} ]]; then
        # 轮转日志文件
        for ((i=${LOG_MAX_FILES}; i>0; i--)); do
            if [[ -f "${LOG_FILE}.${i}" ]]; then
                mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i+1))" 2>/dev/null || true
            fi
        done

        mv "${LOG_FILE}" "${LOG_FILE}.1" || true
        touch "${LOG_FILE}"
        chmod 600 "${LOG_FILE}"

        # 删除过旧的日志文件
        for ((i=${LOG_MAX_FILES}+1; i<=20; i++)); do
            rm -f "${LOG_FILE}.${i}" 2>/dev/null || true
        done

        log_info "日志文件已轮转"
    fi
}

# 通用日志输出函数
write_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 检查日志级别
    local current_level_num=${LOG_LEVELS[${LOG_LEVEL}]}
    local message_level_num=${LOG_LEVELS[${level}]}

    if [[ -z "${message_level_num}" ]] || [[ ${message_level_num} -lt ${current_level_num} ]]; then
        return 0
    fi

    # 格式化日志消息
    local log_entry="${timestamp} [${level}] [$$] ${message}"

    # 写入日志文件
    echo "${log_entry}" >> "${LOG_FILE}" 2>/dev/null || true

    # 输出到控制台（根据级别决定输出流）
    case "${level}" in
        "DEBUG"|"INFO")
            echo "${log_entry}" | tee -a "${LOG_FILE}" >/dev/null 2>&1 || true
            ;;
        "WARN")
            echo "${log_entry}" | tee -a "${LOG_FILE}" >&2 || true
            ;;
        "ERROR"|"FATAL")
            echo "${log_entry}" | tee -a "${LOG_FILE}" >&2 || true
            ;;
    esac
}

# 各级别日志函数
log_debug() {
    write_log "DEBUG" "$@"
}

log_info() {
    write_log "INFO" "$@"
}

log_warn() {
    write_log "WARN" "$@"
}

log_error() {
    write_log "ERROR" "$@"
}

log_fatal() {
    write_log "FATAL" "$@"
    exit 1
}

# 步骤开始日志
log_step_start() {
    local step_name="$1"
    local step_number="$2"
    local total_steps="$3"

    log_info "开始步骤 ${step_number}/${total_steps}: ${step_name}"
    log_info "========================================"
}

# 步骤完成日志
log_step_complete() {
    local step_name="$1"
    local step_number="$2"
    local total_steps="$3"
    local duration="$4"

    log_info "完成步骤 ${step_number}/${total_steps}: ${step_name}"
    if [[ -n "${duration}" ]]; then
        log_info "执行时间: ${duration}"
    fi
    log_info "----------------------------------------"
}

# 步骤失败日志
log_step_failed() {
    local step_name="$1"
    local step_number="$2"
    local total_steps="$3"
    local error_msg="$4"
    local duration="$5"

    log_error "步骤失败 ${step_number}/${total_steps}: ${step_name}"
    if [[ -n "${duration}" ]]; then
        log_error "执行时间: ${duration}"
    fi
    if [[ -n "${error_msg}" ]]; then
        log_error "错误信息: ${error_msg}"
    fi
    log_error "========================================"
}

# 远程执行日志
log_remote_start() {
    local host="$1"
    local command="$2"

    log_info "[${host}] 执行命令: ${command}"
}

log_remote_output() {
    local host="$1"
    local output="$2"

    if [[ -n "${output}" ]]; then
        log_debug "[${host}] 输出: ${output}"
    fi
}

log_remote_complete() {
    local host="$1"
    local exit_code="$2"

    if [[ ${exit_code} -eq 0 ]]; then
        log_info "[${host}] 命令执行成功 (退出码: ${exit_code})"
    else
        log_error "[${host}] 命令执行失败 (退出码: ${exit_code})"
    fi
}

# 配置变更日志
log_config_change() {
    local config_file="$1"
    local action="$2"
    local details="$3"

    log_info "配置变更: ${config_file} - ${action}"
    if [[ -n "${details}" ]]; then
        log_debug "详情: ${details}"
    fi
}

# 安全事件日志
log_security_event() {
    local event_type="$1"
    local resource="$2"
    local action="$3"

    log_warn "安全事件: ${event_type} - ${resource} - ${action}"
}

# 性能监控日志
log_performance() {
    local operation="$1"
    local duration="$2"
    local details="$3"

    log_info "性能监控: ${operation} - 耗时: ${duration}"
    if [[ -n "${details}" ]]; then
        log_debug "详情: ${details}"
    fi
}

# 错误统计
increment_error_count() {
    local error_type="${1:-general}"
    local error_file="${LOG_DIR}/error_counts"

    mkdir -p "$(dirname "${error_file}")"

    # 更新错误计数
    if [[ -f "${error_file}" ]]; then
        local current_count
        current_count=$(grep "^${error_type}:" "${error_file}" 2>/dev/null | cut -d: -f2 || echo "0")
        sed -i "s/^${error_type}:.*/${error_type}:$((current_count + 1))/" "${error_file}" 2>/dev/null || {
            echo "${error_type}:1" >> "${error_file}"
        }
    else
        echo "${error_type}:1" > "${error_file}"
    fi

    log_warn "错误计数更新: ${error_type}"
}

# 获取错误统计
get_error_counts() {
    local error_file="${LOG_DIR}/error_counts"

    if [[ -f "${error_file}" ]]; then
        log_info "错误统计:"
        cat "${error_file}" | while read -r line; do
            log_info "  ${line}"
        done
    else
        log_info "暂无错误统计"
    fi
}

# 查询日志
query_logs() {
    local level_filter="$1"
    local time_range="$2"
    local search_pattern="$3"

    log_info "查询日志 - 级别: ${level_filter:-ALL}, 时间范围: ${time_range:-ALL}, 模式: ${search_pattern:-ALL}"

    local grep_cmd="cat"

    # 时间过滤
    case "${time_range}" in
        "today")
            grep_cmd="grep $(date '+%Y-%m-%d')"
            ;;
        "yesterday")
            grep_cmd="grep $(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d')"
            ;;
        "week")
            local week_start
            week_start=$(date -d '7 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-7d '+%Y-%m-%d')
            grep_cmd="awk '/'${week_start}'/{p=1} p'"
            ;;
    esac

    # 级别过滤
    if [[ -n "${level_filter}" ]] && [[ "${level_filter}" != "ALL" ]]; then
        grep_cmd="${grep_cmd} | grep '\\[${level_filter}\\]'"
    fi

    # 模式搜索
    if [[ -n "${search_pattern}" ]]; then
        grep_cmd="${grep_cmd} | grep '${search_pattern}'"
    fi

    eval "${grep_cmd} '${LOG_FILE}'" || log_warn "日志查询未找到匹配结果"
}

# 清理日志
cleanup_logs() {
    local days="${1:-30}"

    log_info "清理 ${days} 天前的日志文件"

    find "${LOG_DIR}" -name "*.log" -type f -mtime +${days} -delete 2>/dev/null || true
    find "${LOG_DIR}" -name "*.log.*" -type f -mtime +${days} -delete 2>/dev/null || true

    log_info "日志清理完成"
}

# 导出日志
export_logs() {
    local output_dir="$1"
    local start_date="$2"
    local end_date="$3"

    if [[ -z "${output_dir}" ]]; then
        log_error "请指定输出目录"
        return 1
    fi

    mkdir -p "${output_dir}"

    local export_file="${output_dir}/kubefoundry_logs_$(date '+%Y%m%d_%H%M%S').tar.gz"

    if [[ -n "${start_date}" ]] && [[ -n "${end_date}" ]]; then
        # 导出指定时间范围的日志
        log_info "导出日志: ${start_date} 到 ${end_date}"
        find "${LOG_DIR}" -name "*.log*" -newermt "${start_date}" ! -newermt "${end_date}" -print0 | \
            tar -czf "${export_file}" --null -T - || {
            log_error "日志导出失败"
            return 1
        }
    else
        # 导出所有日志
        log_info "导出所有日志"
        tar -czf "${export_file}" -C "$(dirname "${LOG_DIR}")" "$(basename "${LOG_DIR}")" || {
            log_error "日志导出失败"
            return 1
        }
    fi

    log_info "日志已导出到: ${export_file}"
    echo "${export_file}"
}

# 验证日志系统
validate_logger() {
    log_info "验证日志系统..."

    # 检查日志目录
    if [[ ! -d "${LOG_DIR}" ]]; then
        log_error "日志目录不存在: ${LOG_DIR}"
        return 1
    fi

    # 检查日志文件
    if [[ ! -f "${LOG_FILE}" ]]; then
        log_error "日志文件不存在: ${LOG_FILE}"
        return 1
    fi

    # 检查写入权限
    if ! echo "test" >> "${LOG_FILE}" 2>/dev/null; then
        log_error "无法写入日志文件: ${LOG_FILE}"
        return 1
    fi

    # 清理测试数据
    sed -i '/test$/d' "${LOG_FILE}" 2>/dev/null || true

    log_info "日志系统验证通过"
    return 0
}

# 显示日志系统状态
show_logger_status() {
    echo "=== 日志系统状态 ==="
    echo "日志目录: ${LOG_DIR}"
    echo "日志文件: ${LOG_FILE}"
    echo "日志级别: ${LOG_LEVEL}"
    echo "最大大小: ${LOG_MAX_SIZE}"
    echo "最大文件数: ${LOG_MAX_FILES}"

    if [[ -f "${LOG_FILE}" ]]; then
        local file_size
        file_size=$(du -h "${LOG_FILE}" 2>/dev/null | cut -f1 || echo "unknown")
        echo "当前文件大小: ${file_size}"
    fi

    get_error_counts
}

# 模块加载提示
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "logger.sh 是一个库文件，应该被 source 调用，而不是直接执行"
    exit 1
fi

log_debug "日志管理模块已加载"