#!/bin/bash

#===============================================================================
# 脚本名称：tools.sh
# 功能：检查并安装必要工具（yq、helm）
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 定位项目根目录并加载依赖库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/validator.sh"

# 获取系统架构标识
get_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)       echo "$arch" ;;
    esac
}

# 从 tools 目录安装工具
# 参数: $1-工具名 $2-目标路径 $3-源文件名
install_tool_from_dir() {
    local tool_name="$1"
    local dest_path="$2"
    local src_file="$3"
    local src_path="${PROJECT_ROOT}/tools/${src_file}"

    if [ ! -f "$src_path" ]; then
        log_error "工具安装包不存在: ${src_path}"
        return 1
    fi

    log_info "正在安装 ${tool_name} -> ${dest_path}"
    cp "$src_path" "$dest_path" && chmod +x "$dest_path"
    if [ $? -eq 0 ]; then
        log_success "${tool_name} 安装成功: ${dest_path}"
        return 0
    else
        log_error "${tool_name} 安装失败"
        return 1
    fi
}

ARCH="$(get_arch)"

# 1. 检查本地必要工具
log_info "检查本地必要工具..."

local_tools=("ssh" "scp" "rsync" "bc")

for tool in "${local_tools[@]}"; do
    if ! validate_command "$tool"; then
        log_error "本地缺少必要工具: $tool"
        log_info "请先安装: yum install -y $tool"
        exit 1
    fi
    log_debug "✓ $tool 已安装"
done

# 2. 检查并安装 yq
log_info "检查 yq 工具..."
if ! validate_command "yq"; then
    log_warn "yq 未安装，尝试从 tools 目录安装..."
    case "$ARCH" in
        amd64) install_tool_from_dir "yq" "/usr/local/bin/yq" "yq_linux_amd64" ;;
        arm64) install_tool_from_dir "yq" "/usr/local/bin/yq" "yq_linux_arm64" ;;
        *)     log_error "不支持的架构: ${ARCH}，请手动安装 yq"; exit 1 ;;
    esac
    if ! validate_command "yq"; then
        log_error "yq 安装后仍不可用，请检查"
        exit 1
    fi
fi
log_debug "✓ yq 已安装"

# 3. 检查并安装 helm
log_info "检查 helm 工具..."
if ! validate_command "helm"; then
    log_warn "helm 未安装，尝试从 tools 目录安装..."
    case "$ARCH" in
        amd64) install_tool_from_dir "helm" "/usr/local/bin/helm" "helm-amd" ;;
        arm64) install_tool_from_dir "helm" "/usr/local/bin/helm" "helm-arm" ;;
        *)     log_error "不支持的架构: ${ARCH}，请手动安装 helm"; exit 1 ;;
    esac
    if ! validate_command "helm"; then
        log_error "helm 安装后仍不可用，请检查"
        exit 1
    fi
fi
log_debug "✓ helm 已安装"

log_success "本地工具检查通过"
