#!/bin/bash

#===============================================================================
# 脚本名称：11-setup-ssh-login.sh
# 功能：配置SSH免密登录（自动使用sshpass）
# 执行机器：管理节点
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

# 默认SSH密钥路径
DEFAULT_SSH_KEY="$HOME/.ssh/id_rsa"
DEFAULT_SSH_PUB_KEY="$HOME/.ssh/id_rsa.pub"

# 密钥类型和长度
KEY_TYPE="rsa"
KEY_BITS="4096"

#===============================================================================
# 开始执行
#===============================================================================
#===============================================================================
# 1. 安装 sshpass 工具（如果需要）
#===============================================================================
log_substep "检查 sshpass 工具"

if ! command -v sshpass &>/dev/null; then
    log_info "sshpass 未安装，开始安装..."

    # 检查包管理器并安装 sshpass
    if command -v yum &>/dev/null; then
        log_info "使用 yum 安装 sshpass..."
        if yum install -y sshpass >/dev/null 2>&1; then
            log_success "sshpass 安装成功"
        else
            log_error "sshpass 安装失败，请手动安装: yum install -y sshpass"
            return 1
        fi
    elif command -v apt-get &>/dev/null; then
        log_info "使用 apt-get 安装 sshpass..."
        if apt-get update && apt-get install -y sshpass >/dev/null 2>&1; then
            log_success "sshpass 安装成功"
        else
            log_error "sshpass 安装失败，请手动安装: apt-get install -y sshpass"
            return 1
        fi
    else
        log_error "未检测到支持的包管理器（yum 或 apt-get），无法自动安装 sshpass"
        return 1
    fi
else
    log_success "sshpass 已安装"
fi


#===============================================================================
# 2. 检查并生成SSH密钥对
#===============================================================================
log_substep "检查SSH密钥对"

if [ -f "$DEFAULT_SSH_KEY" ] && [ -f "$DEFAULT_SSH_PUB_KEY" ]; then
    log_success "SSH密钥对已存在: ${DEFAULT_SSH_KEY}"
else
    log_info "SSH密钥对不存在，开始生成..."

    # 创建 .ssh 目录（如果不存在）
    local ssh_dir
    ssh_dir=$(dirname "$DEFAULT_SSH_KEY")

    if [ ! -d "$ssh_dir" ]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi

    # 生成密钥对（非交互模式）
    if ssh-keygen -t "${KEY_TYPE}" -b "${KEY_BITS}" -f "$DEFAULT_SSH_KEY" -N "" -q >/dev/null 2>&1; then
        chmod 600 "$DEFAULT_SSH_KEY"
        chmod 644 "$DEFAULT_SSH_PUB_KEY"
        log_success "SSH密钥对生成成功: ${DEFAULT_SSH_KEY}"
    else
        log_error "SSH密钥对生成失败: ${DEFAULT_SSH_KEY}"
        return 1
    fi
fi


#===============================================================================
# 3. 从配置文件读取 SSH 密码
#===============================================================================
log_substep "读取 SSH 配置"

ssh_password=$(config_get '.ssh.password' '' 2>/dev/null)

if [ -z "$ssh_password" ]; then
    log_error "未配置 SSH 密码，请在配置文件中设置 .ssh.password 字段"
    return 1
fi

log_info "已从配置文件读取 SSH 密码"

#===============================================================================
# 4. 复制公钥到所有节点
#===============================================================================

# 获取SSH配置
ssh_user=$(config_get '.ssh.user' 'root' 2>/dev/null)
ssh_port=$(config_get '.ssh.port' '22' 2>/dev/null)

# 读取公钥内容
pub_key_content=$(cat "$DEFAULT_SSH_PUB_KEY")

log_substep "复制公钥到所有节点"

all_ips=$(get_all_node_ips)

if [ -n "$all_ips" ]; then
    while IFS= read -r node_ip; do
        if [ -z "$node_ip" ]; then
            continue
        fi

        # 获取节点主机名
        node_hostname=$(get_node_hostname "$node_ip" 2>/dev/null)
        node_display="${node_hostname:-$node_ip}"

        log_info "复制公钥到节点: ${node_display} (${ssh_user}@${node_ip}:${ssh_port})"

        # 使用 sshpass 创建 .ssh 目录并设置权限
        sshpass -p "$ssh_password" ssh -p "$ssh_port" -o StrictHostKeyChecking=no \
            "${ssh_user}@${node_ip}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh" >/dev/null 2>&1

        # 使用 sshpass 将公钥添加到 authorized_keys
        if sshpass -p "$ssh_password" ssh -p "$ssh_port" -o StrictHostKeyChecking=no \
            "${ssh_user}@${node_ip}" "echo '${pub_key_content}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" >/dev/null 2>&1; then
            log_success "公钥复制成功: ${node_display}"
        else
            log_error "公钥复制失败: ${node_display}（密码错误或连接失败）"
        fi
    done <<< "$all_ips"
fi

#===============================================================================
# 5. 验证所有节点的免密登录
#===============================================================================
log_substep "验证免密登录"

all_ips=$(get_all_node_ips)

if [ -n "$all_ips" ]; then
    while IFS= read -r node_ip; do
        if [ -z "$node_ip" ]; then
            continue
        fi

        # 获取节点主机名
        node_hostname=$(get_node_hostname "$node_ip" 2>/dev/null)
        node_display="${node_hostname:-$node_ip}"

        log_info "验证免密登录: ${node_display} (${ssh_user}@${node_ip}:${ssh_port})"

        # 尝试 SSH 连接（使用密钥）
        if ssh -i "${DEFAULT_SSH_KEY}" -p "$ssh_port" -o ConnectTimeout=10 \
            -o StrictHostKeyChecking=no -o BatchMode=yes \
            "${ssh_user}@${node_ip}" "echo 'SSH connection successful'" >/dev/null 2>&1; then
            log_success "免密登录验证成功: ${node_display}"
        else
            log_error "免密登录验证失败: ${node_display}"
            log_error "可能原因："
            log_error "  1. 公钥未正确复制到目标节点"
            log_error "  2. SSH密钥路径不正确"
            log_error "  3. 目标节点SSH配置不允许密钥登录"
        fi
    done <<< "$all_ips"
fi

log_success "SSH免密登录配置完成"
