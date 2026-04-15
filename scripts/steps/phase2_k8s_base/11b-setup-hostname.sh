#!/bin/bash

#===============================================================================
# 脚本名称：11b-setup-hostname.sh
# 功能：配置所有节点的主机名和 /etc/hosts 集群解析
# 执行机器：管理节点
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"
source "${PROJECT_ROOT}/scripts/lib/ssh.sh"

# /etc/hosts 标记（用于重复执行时替换旧条目）
HOSTS_BEGIN="# >>>KubeFoundry>>>"
HOSTS_END="# <<<KubeFoundry<<<"

#===============================================================================
# 1. 设置所有节点主机名
#===============================================================================
log_substep "设置节点主机名"

declare -A done_ips

# 1.1 控制节点
control_count=$(config_get_length '.control_plane')
for ((i = 0; i < control_count; i++)); do
    ip=$(config_get_node 'control_plane' "$i" 'ip')
    hn=$(config_get_node 'control_plane' "$i" 'hostname')
    log_info "设置控制节点主机名: ${hn} (${ip})"
    if ssh_exec "$ip" "hostnamectl set-hostname ${hn}"; then
        log_success "主机名设置成功: ${hn}"
        done_ips["$ip"]=1
    else
        log_error "主机名设置失败: ${hn} (${ip})"
        return 1
    fi
done

# 1.2 工作节点
worker_count=$(config_get_length '.workers')
for ((i = 0; i < worker_count; i++)); do
    ip=$(config_get_node 'workers' "$i" 'ip')
    hn=$(config_get_node 'workers' "$i" 'hostname')
    log_info "设置工作节点主机名: ${hn} (${ip})"
    if ssh_exec "$ip" "hostnamectl set-hostname ${hn}"; then
        log_success "主机名设置成功: ${hn}"
        done_ips["$ip"]=1
    else
        log_error "主机名设置失败: ${hn} (${ip})"
        return 1
    fi
done

# 1.3 镜像仓库节点（如果独立于控制/工作节点）
registry_ip=$(config_get '.registry.ip')
registry_hn=$(config_get '.registry.hostname')

if [ -z "${done_ips[$registry_ip]}" ]; then
    log_info "设置镜像仓库主机名: ${registry_hn} (${registry_ip})"
    if ssh_exec "$registry_ip" "hostnamectl set-hostname ${registry_hn}"; then
        log_success "主机名设置成功: ${registry_hn}"
    else
        log_error "主机名设置失败: ${registry_hn} (${registry_ip})"
        return 1
    fi
fi

#===============================================================================
# 2. 生成 /etc/hosts 集群条目
#===============================================================================
log_substep "生成 /etc/hosts 集群解析条目"

hosts_body=""

# 控制节点（registry 同机时追加别名）
for ((i = 0; i < control_count; i++)); do
    ip=$(config_get_node 'control_plane' "$i" 'ip')
    hn=$(config_get_node 'control_plane' "$i" 'hostname')
    line="${ip}    ${hn}"
    if [ "$ip" = "$registry_ip" ]; then
        line="${line}    ${registry_hn}"
    fi
    hosts_body="${hosts_body}${line}"$'\n'
done

# 工作节点
for ((i = 0; i < worker_count; i++)); do
    ip=$(config_get_node 'workers' "$i" 'ip')
    hn=$(config_get_node 'workers' "$i" 'hostname')
    hosts_body="${hosts_body}${ip}    ${hn}"$'\n'
done

# 写入临时文件
temp_hosts=$(mktemp)
{
    echo "${HOSTS_BEGIN}"
    printf '%s' "$hosts_body"
    echo "${HOSTS_END}"
} > "$temp_hosts"

log_info "集群 hosts 条目:"
cat "$temp_hosts"

#===============================================================================
# 3. 分发 /etc/hosts 到所有节点
#===============================================================================
log_substep "分发 /etc/hosts 到所有节点"

all_ips=$(get_all_node_ips)

if [ -n "$all_ips" ]; then
    while IFS= read -r node_ip <&3; do
        if [ -z "$node_ip" ]; then
            continue
        fi

        node_display=$(get_node_hostname "$node_ip" 2>/dev/null)
        node_display="${node_display:-$node_ip}"

        log_info "更新 /etc/hosts: ${node_display}"

        # 备份 + 删除旧标记段
        ssh_exec "$node_ip" "cp /etc/hosts /etc/hosts.bak && sed -i '/^${HOSTS_BEGIN}/,/^${HOSTS_END}/d' /etc/hosts" || true

        # 上传新条目并追加
        scp_exec "$temp_hosts" "/tmp/.kf_hosts" "$node_ip" || { rm -f "$temp_hosts"; return 1; }
        ssh_exec "$node_ip" "cat /tmp/.kf_hosts >> /etc/hosts && rm -f /tmp/.kf_hosts" || { rm -f "$temp_hosts"; return 1; }

        log_success "/etc/hosts 更新成功: ${node_display}"
    done 3<<< "$all_ips"
fi

# 清理临时文件
rm -f "$temp_hosts"

log_success "主机名和 hosts 解析配置完成"
