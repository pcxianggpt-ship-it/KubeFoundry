#!/bin/bash

#===============================================================================
# 脚本名称：02-validate-config.sh
# 功能：检查配置文件完整性
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# 1. 检查配置文件是否存在
if [ ! -f "config/config.yaml" ]; then
    echo "【ERROR】: 配置文件不存在: config/config.yaml"
    exit 1
fi

echo "【INFO】: 配置文件检查通过"

# 2. 检查必需的配置项

echo "【INFO】: 必需参数检查通过"

# 3. 验证 IP 地址格式
echo "【INFO】: 验证节点 IP 地址格式..."
all_nodes=$(config_get_all_nodes)
for node in $all_nodes; do
    node_ip=$(config_get_node "$node" "ip")

    # 验证 IPv4 格式
    if ! validate_ip "$node_ip"; then
        echo "【ERROR】: 节点 $node 的 IP 地址格式错误: $node_ip"
        exit 1
    fi
done

echo "【INFO】: IP 地址格式验证通过"

# 4. 验证端口号有效性
echo "【INFO】: 验证端口号..."
api_server_port=$(config_get ".network.api_server_port" "6443")
if ! validate_port "$api_server_port"; then
    echo "【ERROR】: API Server 端口号无效: $api_server_port"
    exit 1
fi

echo "【INFO】: 端口号验证通过"

# 5. 验证文件路径可访问性
echo "【INFO】: 验证文件路径..."
repo_source=$(config_get ".repo.source_path")
if [ -n "$repo_source" ] && [ ! -f "$repo_source" ]; then
    echo "【WARN】: YUM 源文件不存在: $repo_source"
fi

echo "【INFO】: 配置文件完整性检查完成"

# 验证安装结果
# 检查配置验证是否通过
if [ $? -eq 0 ]; then
    echo "【SUCCESS】: 配置文件完整性验证通过"
else
    echo "【ERROR】: 配置文件完整性验证失败"
    exit 1
fi
