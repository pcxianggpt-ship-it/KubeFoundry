#!/bin/bash
# state-manager.sh - 状态管理模块
# 提供 KubeFoundry 项目的部署状态跟踪和恢复功能

# 全局状态配置
readonly STATE_DIR="${STATE_DIR:-/root/.k8s-autodeploy/state}"
readonly STATE_FILE="${STATE_FILE:-${STATE_DIR}/deployment-state.json}"
readonly LOCK_DIR="${LOCK_DIR:-${STATE_DIR}/locks}"
readonly BACKUP_DIR="${BACKUP_DIR:-${STATE_DIR}/backups}"

# 状态定义
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

# 状态值定义
declare -A STEP_STATUSES=(
    ["PENDING"]=0
    ["IN_PROGRESS"]=1
    ["COMPLETED"]=2
    ["FAILED"]=3
    ["SKIPPED"]=4
    ["ROLLED_BACK"]=5
)

# 初始化状态管理系统
init_state_manager() {
    # 创建状态目录
    mkdir -p "${STATE_DIR}" "${LOCK_DIR}" "${BACKUP_DIR}" || {
        echo "FATAL: 无法创建状态目录: ${STATE_DIR}" >&2
        exit 1
    }

    # 设置目录权限
    chmod 700 "${STATE_DIR}" "${LOCK_DIR}" "${BACKUP_DIR}"

    # 初始化状态文件
    if [[ ! -f "${STATE_FILE}" ]]; then
        create_initial_state
    fi

    log_info "状态管理系统初始化完成"
}

# 创建初始状态
create_initial_state() {
    local initial_state='{
        "deployment_id": "'$(date '+%Y%m%d_%H%M%S')'",
        "start_time": "'$(date -Iseconds)'",
        "current_step": 0,
        "total_steps": 15,
        "overall_status": "PENDING",
        "steps": {}
    }'

    # 为每个步骤初始化状态
    local step_num
    for step_num in {1..15}; do
        local step_name="${DEPLOYMENT_STEPS[${step_num}]}"
        initial_state=$(echo "${initial_state}" | jq --arg step "${step_num}" --arg name "${step_name}" '
            .steps[$step] = {
                "name": $name,
                "status": "PENDING",
                "start_time": null,
                "end_time": null,
                "duration": null,
                "attempts": 0,
                "last_attempt": null,
                "error_message": null,
                "rollback_available": false,
                "details": {}
            }
        ')
    done

    echo "${initial_state}" > "${STATE_FILE}" || {
        echo "FATAL: 无法创建状态文件: ${STATE_FILE}" >&2
        exit 1
    }

    chmod 600 "${STATE_FILE}"
}

# 获取当前状态
get_deployment_state() {
    if [[ ! -f "${STATE_FILE}" ]]; then
        echo "null"
        return 1
    fi

    cat "${STATE_FILE}"
}

# 获取步骤状态
get_step_state() {
    local step_num="$1"

    if [[ -z "${step_num}" ]] || [[ ! "${DEPLOYMENT_STEPS[${step_num]}" ]]; then
        echo "null"
        return 1
    fi

    jq -r ".steps[\"${step_num}\"]" "${STATE_FILE}" 2>/dev/null || echo "null"
}

# 更新步骤状态
update_step_state() {
    local step_num="$1"
    local status="$2"
    local error_message="${3:-}"
    local details="${4:-}"

    if [[ -z "${step_num}" ]] || [[ ! "${DEPLOYMENT_STEPS[${step_num]}" ]]; then
        log_error "无效的步骤编号: ${step_num}"
        return 1
    fi

    if [[ -z "${STEP_STATUSES[${status}]" ]]; then
        log_error "无效的状态: ${status}"
        return 1
    fi

    local current_time
    current_time=$(date -Iseconds)

    # 更新步骤状态
    local updated_state
    updated_state=$(jq --arg step "${step_num}" --arg status "${status}" --arg time "${current_time}" '
        if .steps[$step].status == "PENDING" then
            .steps[$step].start_time = $time
        end |
        .steps[$step].status = $status |
        .steps[$step].last_attempt = $time |
        .steps[$step].attempts += 1 |
        if $status == "COMPLETED" or $status == "FAILED" then
            .steps[$step].end_time = $time |
            if .steps[$step].start_time != null then
                .steps[$step].duration = ((
                    ($time | fromdateiso8601) - (.steps[$step].start_time | fromdateiso8601)
                ) | floor)
            end
        end
    ' "${STATE_FILE}")

    # 添加错误信息
    if [[ -n "${error_message}" ]]; then
        updated_state=$(jq --arg step "${step_num}" --arg error "${error_message}" '
            .steps[$step].error_message = $error
        ' <<< "${updated_state}")
    fi

    # 添加详情信息
    if [[ -n "${details}" ]]; then
        updated_state=$(jq --arg step "${step_num}" --argjson details "${details}" '
            .steps[$step].details = .steps[$step].details + $details
        ' <<< "${updated_state}")
    fi

    # 更新当前步骤和整体状态
    if [[ "${status}" == "IN_PROGRESS" ]]; then
        updated_state=$(jq --arg step "${step_num}" --arg overall "IN_PROGRESS" '
            .current_step = ($step | tonumber) |
            .overall_status = $overall
        ' <<< "${updated_state}")
    elif [[ "${status}" == "COMPLETED" ]]; then
        # 检查是否所有步骤都已完成
        local completed_steps
        completed_steps=$(echo "${updated_state}" | jq '
            [.steps[] | select(.status == "COMPLETED")] | length
        ')

        if [[ ${completed_steps} -eq 15 ]]; then
            updated_state=$(jq --arg step "${step_num}" --arg overall "COMPLETED" --arg time "${current_time}" '
                .current_step = ($step | tonumber) |
                .overall_status = $overall |
                .end_time = $time |
                .total_duration = ((
                    ($time | fromdateiso8601) - (.start_time | fromdateiso8601)
                ) | floor)
            ' <<< "${updated_state}")
        else
            updated_state=$(jq --arg step "${step_num}" '
                .current_step = ($step | tonumber)
            ' <<< "${updated_state}")
        fi
    elif [[ "${status}" == "FAILED" ]]; then
        updated_state=$(jq --arg step "${step_num}" --arg overall "FAILED" '
            .current_step = ($step | tonumber) |
            .overall_status = $overall
        ' <<< "${updated_state}")
    fi

    # 写入状态文件
    echo "${updated_state}" > "${STATE_FILE}" || {
        log_error "无法更新状态文件: ${STATE_FILE}"
        return 1
    }

    log_debug "步骤 ${step_num} 状态已更新为: ${status}"
}

# 标记步骤可回滚
mark_step_rollback_available() {
    local step_num="$1"
    local rollback_data="$2"

    local updated_state
    updated_state=$(jq --arg step "${step_num}" '
        .steps[$step].rollback_available = true |
        .steps[$step].rollback_data = {}
    ' "${STATE_FILE}")

    if [[ -n "${rollback_data}" ]]; then
        updated_state=$(jq --arg step "${step_num}" --argjson data "${rollback_data}" '
            .steps[$step].rollback_data = $data
        ' <<< "${updated_state}")
    fi

    echo "${updated_state}" > "${STATE_FILE}"
}

# 获取下一个待执行的步骤
get_next_pending_step() {
    local current_state
    current_state=$(get_deployment_state)

    echo "${current_state}" | jq -r '
        .steps | to_entries[] |
        select(.value.status == "PENDING") |
        .key |
        tonumber |
        sort_by(.) |
        .[0]
    ' 2>/dev/null || echo "null"
}

# 获取失败的步骤
get_failed_steps() {
    local current_state
    current_state=$(get_deployment_state)

    echo "${current_state}" | jq -r '
        .steps | to_entries[] |
        select(.value.status == "FAILED") |
        .key
    ' 2>/dev/null
}

# 检查步骤是否完成
is_step_completed() {
    local step_num="$1"
    local step_state
    step_state=$(get_step_state "${step_num}")

    if [[ "${step_state}" == "null" ]]; then
        return 1
    fi

    local status
    status=$(echo "${step_state}" | jq -r '.status')
    [[ "${status}" == "COMPLETED" ]]
}

# 检查步骤是否失败
is_step_failed() {
    local step_num="$1"
    local step_state
    step_state=$(get_step_state "${step_num}")

    if [[ "${step_state}" == "null" ]]; then
        return 1
    fi

    local status
    status=$(echo "${step_state}" | jq -r '.status')
    [[ "${status}" == "FAILED" ]]
}

# 重置步骤状态
reset_step_state() {
    local step_num="$1"

    local updated_state
    updated_state=$(jq --arg step "${step_num}" '
        .steps[$step].status = "PENDING" |
        .steps[$step].start_time = null |
        .steps[$step].end_time = null |
        .steps[$step].duration = null |
        .steps[$step].error_message = null |
        .steps[$step].rollback_available = false |
        .steps[$step].rollback_data = {}
    ' "${STATE_FILE}")

    echo "${updated_state}" > "${STATE_FILE}"
    log_info "步骤 ${step_num} 状态已重置"
}

# 备份状态
backup_state() {
    local backup_name="${1:-state_backup_$(date '+%Y%m%d_%H%M%S')}"
    local backup_file="${BACKUP_DIR}/${backup_name}.json"

    cp "${STATE_FILE}" "${backup_file}" || {
        log_error "无法备份状态文件到: ${backup_file}"
        return 1
    }

    log_info "状态已备份到: ${backup_file}"
    echo "${backup_file}"
}

# 恢复状态
restore_state() {
    local backup_file="$1"

    if [[ -z "${backup_file}" ]] || [[ ! -f "${backup_file}" ]]; then
        log_error "备份文件不存在: ${backup_file}"
        return 1
    fi

    # 备份当前状态
    backup_state "before_restore_$(date '+%Y%m%d_%H%M%S')"

    # 恢复状态
    cp "${backup_file}" "${STATE_FILE}" || {
        log_error "无法恢复状态文件"
        return 1
    }

    log_info "状态已从备份恢复: ${backup_file}"
}

# 列出可用备份
list_state_backups() {
    log_info "可用的状态备份:"

    find "${BACKUP_DIR}" -name "*.json" -type f -printf "%T@ %p\n" | \
        sort -n | while read -r timestamp file; do
        local backup_name
        backup_name=$(basename "${file}" .json)
        local formatted_time
        formatted_time=$(date -d "@${timestamp%.*}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || \
                        date -r "${timestamp%.*}" '+%Y-%m-%d %H:%M:%S')
        echo "  ${backup_name} (${formatted_time})"
    done
}

# 获取锁文件路径
get_lock_path() {
    local resource="$1"
    echo "${LOCK_DIR}/${resource}.lock"
}

# 获取锁
acquire_lock() {
    local resource="$1"
    local timeout="${2:-300}"  # 默认5分钟超时
    local lock_file
    lock_file=$(get_lock_path "${resource}")

    local start_time
    start_time=$(date +%s)

    while [[ $(( $(date +%s) - start_time )) -lt ${timeout} ]]; do
        if (set -C; echo $$ > "${lock_file}") 2>/dev/null; then
            log_debug "获取锁成功: ${resource}"
            return 0
        fi

        local lock_pid
        lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "")
        if [[ -n "${lock_pid}" ]] && ! kill -0 "${lock_pid}" 2>/dev/null; then
            # 锁进程不存在，强制删除
            rm -f "${lock_file}"
            continue
        fi

        sleep 1
    done

    log_error "获取锁超时: ${resource}"
    return 1
}

# 释放锁
release_lock() {
    local resource="$1"
    local lock_file
    lock_file=$(get_lock_path "${resource}")

    # 验证锁的所有者
    if [[ -f "${lock_file}" ]]; then
        local lock_pid
        lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "")
        if [[ "${lock_pid}" == "$$" ]]; then
            rm -f "${lock_file}"
            log_debug "释放锁: ${resource}"
            return 0
        else
            log_error "无权释放锁: ${resource} (所有者: ${lock_pid})"
            return 1
        fi
    fi

    return 0
}

# 在锁中执行命令
with_lock() {
    local resource="$1"
    local timeout="${2:-300}"
    shift 2

    if acquire_lock "${resource}" "${timeout}"; then
        local exit_code
        "$@"
        exit_code=$?
        release_lock "${resource}"
        return ${exit_code}
    else
        log_error "无法获取锁: ${resource}"
        return 1
    fi
}

# 验证状态管理器
validate_state_manager() {
    log_info "验证状态管理器..."

    # 检查目录
    if [[ ! -d "${STATE_DIR}" ]]; then
        log_error "状态目录不存在: ${STATE_DIR}"
        return 1
    fi

    if [[ ! -d "${LOCK_DIR}" ]]; then
        log_error "锁目录不存在: ${LOCK_DIR}"
        return 1
    fi

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log_error "备份目录不存在: ${BACKUP_DIR}"
        return 1
    fi

    # 检查状态文件
    if [[ ! -f "${STATE_FILE}" ]]; then
        log_error "状态文件不存在: ${STATE_FILE}"
        return 1
    fi

    # 验证JSON格式
    if ! jq empty "${STATE_FILE}" 2>/dev/null; then
        log_error "状态文件格式无效"
        return 1
    fi

    # 检查写权限
    if ! echo '{}' > "${STATE_FILE}.test" 2>/dev/null; then
        log_error "无法写入状态文件"
        rm -f "${STATE_FILE}.test"
        return 1
    fi
    rm -f "${STATE_FILE}.test"

    log_info "状态管理器验证通过"
    return 0
}

# 显示部署状态摘要
show_deployment_summary() {
    local current_state
    current_state=$(get_deployment_state)

    echo "=== 部署状态摘要 ==="
    echo "部署ID: $(echo "${current_state}" | jq -r '.deployment_id')"
    echo "开始时间: $(echo "${current_state}" | jq -r '.start_time')"
    echo "当前步骤: $(echo "${current_state}" | jq -r '.current_step')/15"
    echo "整体状态: $(echo "${current_state}" | jq -r '.overall_status')"

    local end_time
    end_time=$(echo "${current_state}" | jq -r '.end_time // "进行中"')
    echo "结束时间: ${end_time}"

    if echo "${current_state}" | jq -e '.total_duration' >/dev/null 2>&1; then
        local duration
        duration=$(echo "${current_state}" | jq -r '.total_duration')
        echo "总耗时: ${duration} 秒"
    fi

    echo ""
    echo "步骤状态:"
    echo "${current_state}" | jq -r '
        .steps | to_entries[] |
        "\(.key): \(.value.name) - \(.value.status) (\(.value.attempts // 0) 次尝试)"
    ' | while read -r line; do
        echo "  ${line}"
    done

    echo ""
    local failed_count
    failed_count=$(echo "${current_state}" | jq '[.steps[] | select(.status == "FAILED")] | length')
    local completed_count
    completed_count=$(echo "${current_state}" | jq '[.steps[] | select(.status == "COMPLETED")] | length')
    echo "统计: ${completed_count} 已完成, ${failed_count} 失败"
}

# 模块加载提示
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "state-manager.sh 是一个库文件，应该被 source 调用，而不是直接执行"
    exit 1
fi

log_debug "状态管理模块已加载"