#!/bin/bash
# step-01-root-check.sh - Root 用户权限验证
# 验证所有目标节点是否具有 root 权限

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 加载依赖模块
source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/state-manager.sh"
source "${PROJECT_ROOT}/lib/config-parser.sh"

# 参数检查
if [[ $# -ne 2 ]]; then
    log_error "用法: $0 <config_file> <project_root>"
    exit 1
fi

CONFIG_FILE="$1"
PROJECT_ROOT="$2"

# 加载配置
if ! load_config "${CONFIG_FILE}"; then
    log_error "无法加载配置文件: ${CONFIG_FILE}"
    exit 1
fi

log_info "开始步骤 1: Root 用户权限验证"

# 获取主机列表
get_all_hosts() {
    local hosts=()

    # 控制平面节点
    while IFS= read -r ip; do
        [[ -n "${ip}" ]] && hosts+=("${ip}")
    done < <(yq eval '.hosts.control_plane[].ip' "${CONFIG_FILE}")

    # 工作节点
    while IFS= read -r ip; do
        [[ -n "${ip}" ]] && hosts+=("${ip}")
    done < <(yq eval '.hosts.workers[].ip?' "${CONFIG_FILE}")

    echo "${hosts[@]}"
}

# 验证单个主机的 root 权限
verify_root_access() {
    local host="$1"
    local ssh_port
    ssh_port=$(get_config "global.ssh.port" "22" "${CONFIG_FILE}")
    local ssh_timeout
    ssh_timeout=$(get_config "global.ssh.timeout" "300" "${CONFIG_FILE}")

    log_info "验证主机 ${host} 的 root 访问权限..."

    # 尝试连接并检查权限
    local ssh_opts="-o ConnectTimeout=${ssh_timeout} -o StrictHostKeyChecking=no -o BatchMode=yes"

    # 检查是否可以 SSH 连接
    if ! ssh ${ssh_opts} -p ${ssh_port} root@${host} "exit" 2>/dev/null; then
        log_error "无法通过 SSH 连接到主机 ${host}"
        return 1
    fi

    # 检查是否为 root 用户
    local current_user
    current_user=$(ssh ${ssh_opts} -p ${ssh_port} root@${host} "whoami" 2>/dev/null || echo "")

    if [[ "${current_user}" != "root" ]]; then
        log_error "主机 ${host} 当前用户不是 root: ${current_user}"
        return 1
    fi

    # 检查 sudo 权限（如果需要）
    if ! ssh ${ssh_opts} -p ${ssh_port} root@${host} "sudo -n whoami" >/dev/null 2>&1; then
        log_error "主机 ${host} 没有 sudo 权限"
        return 1
    fi

    # 检查系统信息
    local os_info
    os_info=$(ssh ${ssh_opts} -p ${ssh_port} root@${host} "cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"'" 2>/dev/null || echo "未知")

    local arch_info
    arch_info=$(ssh ${ssh_opts} -p ${ssh_port} root@${host} "uname -m" 2>/dev/null || echo "未知")

    log_info "主机 ${host} 验证通过 - 系统: ${os_info}, 架构: ${arch_info}"

    return 0
}

# 并行验证主机权限
parallel_verify_hosts() {
    local hosts=("$@")
    local max_parallel=5
    local pids=()
    local failed_hosts=()

    log_info "开始并行验证 ${#hosts[@]} 个主机的 root 权限..."

    for host in "${hosts[@]}"; do
        # 限制并发数
        while [[ ${#pids[@]} -ge ${max_parallel} ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[i]}" 2>/dev/null; then
                    wait "${pids[i]}"
                    if [[ $? -ne 0 ]]; then
                        failed_hosts+=("${hosts[i]}")
                    fi
                    unset pids[i]
                    break
                fi
            done
            sleep 1
        done

        # 启动新的验证进程
        (
            verify_root_access "${host}"
        ) &
        pids+=("$!")

        # 记录 PID 和主机的对应关系
        local last_idx=$((${#pids[@]} - 1))
        eval "host_${last_idx}='${host}'"
    done

    # 等待所有进程完成
    for i in "${!pids[@]}"; do
        wait "${pids[i]}"
        if [[ $? -ne 0 ]]; then
            local host_name
            eval "host_name=\${host_${i}}"
            failed_hosts+=("${host_name}")
        fi
    done

    if [[ ${#failed_hosts[@]} -gt 0 ]]; then
        log_error "以下主机验证失败:"
        for host in "${failed_hosts[@]}"; do
            log_error "  ${host}"
        done
        return 1
    fi

    log_success "所有主机 root 权限验证通过"
    return 0
}

# 生成主机信息报告
generate_host_report() {
    local hosts=("$@")
    local report_file="${PROJECT_ROOT}/host-report-$(date '+%Y%m%d_%H%M%S').json"

    log_info "生成主机信息报告: ${report_file}"

    local report='{"hosts":['
    local first=true

    for host in "${hosts[@]}"; do
        if [[ "${first}" == "true" ]]; then
            first=false
        else
            report+=','
        fi

        local ssh_port
        ssh_port=$(get_config "global.ssh.port" "22" "${CONFIG_FILE}")
        local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes"

        # 获取主机信息
        local hostname
        hostname=$(ssh ${ssh_opts} -p ${ssh_port} root@${host} "hostname" 2>/dev/null || echo "未知")

        local os_info
        os_info=$(ssh ${ssh_opts} -p ${ssh_port} root@${host} "cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"'" 2>/dev/null || echo "未知")

        local arch_info
        arch_info=$(ssh ${ssh_opts} -p ${ssh_port} root@${host} "uname -m" 2>/dev/null || echo "未知")

        local memory_info
        memory_info=$(ssh ${ssh_opts} -p ${ssh_port} root@${host} "free -h | grep '^Mem:' | awk '{print \$2}'" 2>/dev/null || echo "未知")

        local disk_info
        disk_info=$(ssh ${ssh_opts} -p ${ssh_port} root@${host} "df -h / | tail -1 | awk '{print \$2}'" 2>/dev/null || echo "未知")

        local uptime_info
        uptime_info=$(ssh ${ssh_opts} -p ${ssh_port} root@${host} "uptime -p" 2>/dev/null || echo "未知")

        report+="{"
        report+="\"ip\":\"${host}\","
        report+="\"hostname\":\"${hostname}\","
        report+="\"os\":\"${os_info}\","
        report+="\"architecture\":\"${arch_info}\","
        report+="\"memory\":\"${memory_info}\","
        report+="\"disk\":\"${disk_info}\","
        report+="\"uptime\":\"${uptime_info}\","
        report+="\"root_access\":true"
        report+="}"
    done

    report+=']}'

    echo "${report}" | jq '.' > "${report_file}"
    log_info "主机信息报告已生成: ${report_file}"
}

# 主执行流程
main() {
    log_info "步骤 1: Root 用户权限验证开始"

    local start_time
    start_time=$(date +%s)

    # 获取所有主机
    local hosts
    read -ra hosts <<< "$(get_all_hosts)"

    if [[ ${#hosts[@]} -eq 0 ]]; then
        log_error "未找到任何主机配置"
        exit 1
    fi

    log_info "找到 ${#hosts[@]} 个主机需要验证"

    # 并行验证所有主机
    if ! parallel_verify_hosts "${hosts[@]}"; then
        log_error "Root 权限验证失败"
        exit 1
    fi

    # 生成主机报告
    generate_host_report "${hosts[@]}"

    local duration
    duration=$(format_duration $(( $(date +%s) - start_time )))

    log_success "步骤 1 完成: 所有主机的 root 权限验证通过，耗时: ${duration}"

    # 标记步骤可回滚
    mark_step_rollback_available 1 '{"hosts":['$(printf '"%s",' "${hosts[@]}" | sed 's/,$//')]'}'

    exit 0
}

# 执行主函数
main "$@"