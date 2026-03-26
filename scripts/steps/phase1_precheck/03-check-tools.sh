#!/bin/bash

#===============================================================================
# 脚本名称：03-check-tools.sh
# 功能：检查必要工具安装
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 1. 检查本地必要工具
echo "【INFO】: 检查本地必要工具..."

local_tools=("ssh" "scp" "rsync" "yaml" "jq" "bc")

for tool in "${local_tools[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo "【ERROR】: 本地缺少必要工具: $tool"
        echo "请先安装: yum install -y $tool"
        exit 1
    fi
    echo "【INFO】: ✓ $tool 已安装"
done

echo "【SUCCESS】: 本地工具检查通过"

# 2. 检查配置文件中指定的工具路径
echo "【INFO】: 检查配置文件中指定的工具..."

# 检查 helm 工具
helm_path=$(config_get ".tools.helm_path" "/usr/local/bin/helm")
if [ -n "$helm_path" ] && [ ! -f "$helm_path" ]; then
    echo "【WARN】: helm 未找到: $helm_path"
fi

echo "【INFO】: 工具路径检查完成"

# 3. 检查 SSH 连接（到所有节点）
echo "【INFO】: 检查 SSH 连接..."
all_nodes=$(config_get_all_nodes)
failed_nodes=()

for node in $all_nodes; do
    node_ip=$(config_get_node "$node" "ip")

    if ! ssh_check_connection "$node_ip"; then
        echo "【ERROR】: 无法连接到节点 $node ($node_ip)"
        failed_nodes+=("$node")
    else
        echo "【INFO】: ✓ 节点 $node ($node_ip) SSH 连接正常"
    fi
done

if [ ${#failed_nodes[@]} -gt 0 ]; then
    echo "【ERROR】: 以下节点 SSH 连接失败:"
    printf '%s\n' "${failed_nodes[@]}"
    echo "请检查:"
    echo "1. 节点是否启动"
    echo "2. SSH 服务是否运行"
    echo "3. 网络连通性"
    echo "4. SSH 密钥是否配置"
    exit 1
fi

echo "【SUCCESS】: SSH 连接检查通过"

# 4. 生成检查报告
echo ""
echo "======================================"
echo "前置检查报告"
echo "======================================"
echo "配置文件: ✓ 通过"
echo "配置参数: ✓ 通过"
echo "IP 地址格式: ✓ 通过"
echo "端口号: ✓ 通过"
echo "本地工具: ✓ 通过"
echo "SSH 连接: ✓ 通过"
echo "======================================"
echo ""

# 验证安装结果
# 所有检查应该通过，否则退出
if [ $? -eq 0 ]; then
    echo "【SUCCESS】: 前置检查全部通过，可以开始部署"
else
    echo "【ERROR】: 前置检查失败，请修复错误后重试"
    exit 1
fi
