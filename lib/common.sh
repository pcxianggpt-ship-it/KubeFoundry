#!/bin/bash
# common.sh - 通用工具函数库
# 提供 KubeFoundry 项目的基础工具函数

# 启用严格模式
set -euo pipefail

# 全局常量
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LIB_DIR="${PROJECT_ROOT}/lib"
readonly CONFIG_DIR="${PROJECT_ROOT}/config"
readonly SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
readonly STEPS_DIR="${PROJECT_ROOT}/steps"
readonly TOOLS_DIR="${PROJECT_ROOT}/tools"

# 颜色输出常量
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# 系统信息
detect_operating_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${ID}"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    else
        uname -s | tr '[:upper:]' '[:lower:]'
    fi
}

detect_os_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${VERSION_ID}"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -sr
    else
        echo "unknown"
    fi
}

detect_architecture() {
    local arch
    arch=$(uname -m)
    case "${arch}" in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "${arch}"
            ;;
    esac
}

# 时间和日期
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

get_iso_timestamp() {
    date -Iseconds
}

get_unix_timestamp() {
    date +%s
}

format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [[ ${hours} -gt 0 ]]; then
        printf "%dh %dm %ds" ${hours} ${minutes} ${secs}
    elif [[ ${minutes} -gt 0 ]]; then
        printf "%dm %ds" ${minutes} ${secs}
    else
        printf "%ds" ${secs}
    fi
}

# 字符串处理
trim() {
    local var="$1"
    # 移除前导和尾随空白
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo "${var}"
}

lowercase() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

uppercase() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# 随机字符串生成
generate_random_string() {
    local length="${1:-16}"
    local charset="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result=""

    for i in $(seq 1 ${length}); do
        result+="${charset:$((RANDOM % ${#charset})):1}"
    done

    echo "${result}"
}

generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x\n' \
            $((RANDOM % 65536)) $((RANDOM % 65536)) \
            $((RANDOM % 65536)) \
            $(((RANDOM % 65536) | 0x4000)) \
            $(((RANDOM % 65536) | 0x8000)) \
            $((RANDOM % 65536)) $((RANDOM % 65536))
    fi
}

# 文件操作
ensure_directory() {
    local dir_path="$1"
    local mode="${2:-755}"

    if [[ ! -d "${dir_path}" ]]; then
        mkdir -p "${dir_path}" || {
            log_error "无法创建目录: ${dir_path}"
            return 1
        }
        chmod "${mode}" "${dir_path}"
        log_debug "目录已创建: ${dir_path}"
    fi
}

backup_file() {
    local file_path="$1"
    local backup_suffix="${2:-.$(date '+%Y%m%d_%H%M%S').bak}"

    if [[ -f "${file_path}" ]]; then
        local backup_path="${file_path}${backup_suffix}"
        cp "${file_path}" "${backup_path}" || {
            log_error "无法备份文件: ${file_path}"
            return 1
        }
        log_debug "文件已备份: ${file_path} -> ${backup_path}"
        echo "${backup_path}"
    fi
}

safe_write_file() {
    local file_path="$1"
    local content="$2"
    local mode="${3:-644}"

    # 创建临时文件
    local temp_file
    temp_file=$(mktemp)

    # 写入内容到临时文件
    echo "${content}" > "${temp_file}" || {
        log_error "无法写入临时文件: ${temp_file}"
        rm -f "${temp_file}"
        return 1
    }

    # 设置权限
    chmod "${mode}" "${temp_file}"

    # 原子性移动
    mv "${temp_file}" "${file_path}" || {
        log_error "无法移动文件到目标位置: ${file_path}"
        rm -f "${temp_file}"
        return 1
    }

    log_debug "文件已安全写入: ${file_path}"
}

# 进程管理
wait_for_process() {
    local pid="$1"
    local timeout="${2:-60}"
    local interval="${3:-1}"

    local count=0
    while kill -0 "${pid}" 2>/dev/null; do
        if [[ ${count} -ge ${timeout} ]]; then
            log_error "等待进程超时: ${pid}"
            return 1
        fi
        sleep "${interval}"
        ((count++))
    done

    wait "${pid}"
    local exit_code=$?

    log_debug "进程 ${pid} 已结束，退出码: ${exit_code}"
    return ${exit_code}
}

kill_process_tree() {
    local pid="$1"
    local signal="${2:-TERM}"

    if [[ -z "${pid}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
        log_error "无效的进程ID: ${pid}"
        return 1
    fi

    # 获取子进程
    local children
    children=$(pgrep -P "${pid}" 2>/dev/null || true)

    # 终止父进程
    kill -"${signal}" "${pid}" 2>/dev/null || true

    # 递归终止子进程
    if [[ -n "${children}" ]]; then
        for child in ${children}; do
            kill_process_tree "${child}" "${signal}"
        done
    fi

    log_debug "进程树已终止: ${pid}"
}

# 网络工具
is_port_open() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"

    if command -v nc >/dev/null 2>&1; then
        nc -z -w "${timeout}" "${host}" "${port}" 2>/dev/null
    elif command -v telnet >/dev/null 2>&1; then
        timeout "${timeout}" telnet "${host}" "${port}" </dev/null >/dev/null 2>&1
    else
        # 回退到 bash 内置的 TCP 连接
        timeout "${timeout}" bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null
    fi
}

wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-60}"
    local interval="${4:-2}"

    local count=0
    while ! is_port_open "${host}" "${port}"; do
        if [[ ${count} -ge ${timeout} ]]; then
            log_error "等待端口开放超时: ${host}:${port}"
            return 1
        fi
        sleep "${interval}"
        ((count++))
    done

    log_debug "端口已开放: ${host}:${port}"
}

get_local_ip() {
    # 尝试多种方法获取本地IP
    if command -v ip >/dev/null 2>&1; then
        ip route get 1 | awk '{print $7; exit}' 2>/dev/null
    elif command -v hostname >/dev/null 2>&1; then
        hostname -I 2>/dev/null | awk '{print $1}'
    else
        # 回退方法
        local ip
        ip=$(ping -c 1 "$(hostname)" 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)
        if [[ -n "${ip}" ]]; then
            echo "${ip}"
        else
            echo "127.0.0.1"
        fi
    fi
}

# 命令执行安全包装
safe_execute() {
    local cmd="$1"
    local description="${2:-执行命令}"
    local timeout="${3:-300}"
    local retry_count="${4:-0}"
    local retry_delay="${5:-5}"

    local attempt=1
    while [[ ${attempt} -le $((retry_count + 1)) ]]; do
        log_debug "${description} (尝试 ${attempt}/${retry_count + 1}): ${cmd}"

        # 使用 timeout 命令执行
        if timeout "${timeout}" bash -c "${cmd}"; then
            log_debug "${description} 执行成功"
            return 0
        else
            local exit_code=$?
            log_warn "${description} 执行失败 (退出码: ${exit_code})"

            if [[ ${attempt} -le ${retry_count} ]]; then
                log_info "${retry_delay} 秒后重试..."
                sleep "${retry_delay}"
            fi
        fi

        ((attempt++))
    done

    log_error "${description} 执行失败，已重试 ${retry_count} 次"
    return 1
}

# 验证函数
validate_ip() {
    local ip="$1"
    local ipv4_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    local ipv6_regex='^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$'

    if [[ "${ip}" =~ ${ipv4_regex} ]] || [[ "${ip}" =~ ${ipv6_regex} ]]; then
        return 0
    else
        return 1
    fi
}

validate_hostname() {
    local hostname="$1"
    local hostname_regex='^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'

    [[ "${hostname}" =~ ${hostname_regex} ]]
}

validate_port() {
    local port="$1"
    local port_regex='^[0-9]+$'

    if [[ "${port}" =~ ${port4_regex} ]] && [[ ${port} -ge 1 ]] && [[ ${port} -le 65535 ]]; then
        return 0
    else
        return 1
    fi
}

# 系统资源检查
check_disk_space() {
    local path="$1"
    local min_space_mb="${2:-1024}"  # 默认 1GB

    if [[ ! -d "${path}" ]]; then
        log_error "路径不存在: ${path}"
        return 1
    fi

    local available_mb
    available_mb=$(df -m "${path}" | awk 'NR==2 {print $4}')

    if [[ ${available_mb} -lt ${min_space_mb} ]]; then
        log_error "磁盘空间不足: ${path} (可用: ${available_mb}MB, 需要: ${min_space_mb}MB)"
        return 1
    fi

    log_debug "磁盘空间检查通过: ${path} (可用: ${available_mb}MB)"
    return 0
}

check_memory() {
    local min_memory_mb="${1:-2048}"  # 默认 2GB

    local total_memory_mb
    if [[ -f /proc/meminfo ]]; then
        total_memory_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    else
        log_error "无法获取内存信息"
        return 1
    fi

    if [[ ${total_memory_mb} -lt ${min_memory_mb} ]]; then
        log_error "内存不足: ${total_memory_mb}MB (需要: ${min_memory_mb}MB)"
        return 1
    fi

    log_debug "内存检查通过: ${total_memory_mb}MB"
    return 0
}

# 颜色输出
print_colored() {
    local color="$1"
    shift
    local message="$*"

    echo -e "${color}${message}${NC}"
}

print_success() {
    print_colored "${GREEN}" "$@"
}

print_error() {
    print_colored "${RED}" "$@"
}

print_warning() {
    print_colored "${YELLOW}" "$@"
}

print_info() {
    print_colored "${BLUE}" "$@"
}

print_debug() {
    print_colored "${PURPLE}" "$@"
}

# 进度条
show_progress() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"
    local description="${4:-}"

    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    local progress_bar=""
    for ((i = 0; i < filled; i++)); do
        progress_bar+="="
    done
    for ((i = 0; i < empty; i++)); do
        progress_bar+=" "
    done

    printf "\r%s [%s] %d%% (%d/%d)" "${description}" "${progress_bar}" "${percentage}" "${current}" "${total}"

    if [[ ${current} -eq ${total} ]]; then
        echo ""
    fi
}

# 配置文件工具
merge_json() {
    local base="$1"
    local overlay="$2"
    local output="$3"

    if [[ ! -f "${base}" ]] || [[ ! -f "${overlay}" ]]; then
        log_error "源文件不存在"
        return 1
    fi

    jq -s '.[0] * .[1]' "${base}" "${overlay}" > "${output}" || {
        log_error "JSON 合并失败"
        return 1
    }

    log_debug "JSON 文件已合并: ${output}"
}

# 环境变量管理
set_env_var() {
    local var_name="$1"
    local var_value="$2"
    local env_file="${3:-${PROJECT_ROOT}/.env}"

    # 确保 .env 文件存在
    touch "${env_file}"

    # 移除现有的变量定义
    if grep -q "^${var_name}=" "${env_file}"; then
        sed -i "/^${var_name}=/d" "${env_file}"
    fi

    # 添加新的变量定义
    echo "${var_name}=${var_value}" >> "${env_file}"

    export "${var_name}=${var_value}"
    log_debug "环境变量已设置: ${var_name}"
}

get_env_var() {
    local var_name="$1"
    local default_value="${2:-}"
    local env_file="${3:-${PROJECT_ROOT}/.env}"

    if [[ -f "${env_file}" ]] && grep -q "^${var_name}=" "${env_file}"; then
        grep "^${var_name}=" "${env_file}" | cut -d'=' -f2-
    else
        echo "${default_value}"
    fi
}

# 版本比较
version_compare() {
    local version1="$1"
    local operator="$2"
    local version2="$3"

    # 使用 sort -V 进行版本比较
    local result
    result=$(printf '%s\n%s\n' "${version1}" "${version2}" | sort -V | head -n1)

    case "${operator}" in
        "="|"==")
            [[ "${version1}" == "${version2}" ]]
            ;;
        "!=")
            [[ "${version1}" != "${version2}" ]]
            ;;
        "<")
            [[ "${result}" == "${version1}" ]] && [[ "${version1}" != "${version2}" ]]
            ;;
        "<=")
            [[ "${result}" == "${version1}" ]] || [[ "${version1}" == "${version2}" ]]
            ;;
        ">")
            [[ "${result}" == "${version2}" ]] && [[ "${version1}" != "${version2}" ]]
            ;;
        ">=")
            [[ "${result}" == "${version2}" ]] || [[ "${version1}" == "${version2}" ]]
            ;;
        *)
            log_error "不支持的比较操作符: ${operator}"
            return 1
            ;;
    esac
}

# 模块加载提示
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "common.sh 是一个库文件，应该被 source 调用，而不是直接执行"
    echo ""
    echo "用法示例:"
    echo "  source ${PROJECT_ROOT}/lib/common.sh"
    echo ""
    echo "可用函数:"
    echo "  detect_operating_system()    - 检测操作系统"
    echo "  detect_architecture()        - 检测系统架构"
    echo "  get_timestamp()              - 获取时间戳"
    echo "  generate_uuid()              - 生成UUID"
    echo "  ensure_directory()           - 确保目录存在"
    echo "  backup_file()                - 备份文件"
    echo "  validate_ip()                - 验证IP地址"
    echo "  show_progress()              - 显示进度条"
    exit 1
fi

log_debug "通用工具函数库已加载"