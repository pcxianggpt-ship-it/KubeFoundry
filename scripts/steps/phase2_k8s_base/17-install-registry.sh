#!/bin/bash

#===============================================================================
# 脚本名称：17-install-registry.sh
# 功能：安装镜像仓库
# 执行机器：镜像仓库节点
# 作者：KubeFoundry Team
# 版本：1.0.0
# 环境变量依赖（由 exec_script_on_single_node 注入）：
#   REGISTRY_IP - 镜像仓库IP地址
#   INSTALL_MEDIA - 安装介质目录
#   ARCH        - 系统架构（amd64/arm64）
#===============================================================================

# 参数校验
if [[ -z "$REGISTRY_IP" ]]; then
    echo "【ERROR】：缺少环境变量 REGISTRY_IP（镜像仓库IP地址）"
    exit 1
fi

if [[ -z "$ARCH" ]]; then
    echo "【ERROR】：缺少环境变量 ARCH（系统架构）"
    exit 1
fi

if [[ -z "$INSTALL_MEDIA" ]]; then
    echo "【ERROR】：缺少环境变量 INSTALL_MEDIA（安装介质目录）"
    exit 1
fi

# 检查容器运行时
if command -v nerdctl &> /dev/null; then
    CONTAINER_CMD="nerdctl"
elif command -v docker &> /dev/null; then
    CONTAINER_CMD="docker"
else
    echo "【ERROR】：未找到容器运行时(docker或nerdctl)"
    exit 1
fi

echo "【INFO】：使用容器运行时: ${CONTAINER_CMD}"
echo "【INFO】：镜像仓库IP: ${REGISTRY_IP}, 架构: ${ARCH}, 安装目录: ${INSTALL_MEDIA}"

# 进入 registry 安装目录（由 2.9 步骤分发到此）
REGISTRY_DIR="${K8S_HOME}/04.registry"
if [ ! -d "$REGISTRY_DIR" ]; then
    echo "【ERROR】：registry安装目录不存在: ${REGISTRY_DIR}"
    exit 1
fi
cd "$REGISTRY_DIR"

# 解压镜像文件
echo "----正在解压镜像文件----"
if [ -f registry-2.8.3.tar.gz ]; then
    tar -xzf registry-2.8.3.tar.gz --checkpoint=.1000
    echo "----镜像文件解压成功----"
else
    echo "【WARN】：未找到 registry-2.8.3.tar.gz，跳过解压（假设已解压）"
fi

cd "$REGISTRY_DIR"/docker-registry
# 加载 registry 镜像
if [ -f rg2.8.3.tar ]; then
    $CONTAINER_CMD load -i rg2.8.3.tar > /dev/null 2>&1
fi

if $CONTAINER_CMD images | grep registry | awk '{print $2}' | grep -q "2.8.3" ; then
    echo "【SUCCESS】：registry-2.8.3-${ARCH}.tar镜像导入成功"
else
    echo "【ERROR】：registry-2.8.3镜像导入失败"
    exit 1
fi

# 生成 registry 配置文件
cat > config.yml <<EOF
version: 0.1
log:
  level: info
  fields:
    service: registry
storage:
  delete:
    enabled: true
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
    Access-Control-Allow-Origin: ["http://${REGISTRY_IP}:5080"]
    Access-Control-Allow-Methods: ["HEAD", "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    Access-Control-Allow-Headers: ["Authorization", "Content-Type", "Accept"]
    Access-Control-Max-Age: [1728000]
    Access-Control-Allow-Credentials: [true]
    Access-Control-Expose-Headers: ["Docker-Content-Digest"]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF

# 启动 registry 服务端
echo "----正在启动镜像服务端----"
mkdir -p registry-data
$CONTAINER_CMD run -d --name registry --restart always \
    -p 5000:5000 \
    -v $(pwd)/registry-data:/var/lib/registry \
    -v $(pwd)/config.yml:/etc/docker/registry/config.yml \
    registry:2.8.3

if [ $? -ne 0 ]; then
    echo "【ERROR】：registry服务端启动失败"
    exit 1
fi
echo "【SUCCESS】：镜像服务端启动成功"

sleep 10

# 拉取并启动 UI
echo "----正在拉取UI镜像----"
$CONTAINER_CMD pull registry:5000/joxit/docker-registry-ui:main
if $CONTAINER_CMD images | grep docker-registry-ui | wc -l | grep -q "1" ; then
    echo "【SUCCESS】：镜像仓库UI镜像拉取成功"
else
    echo "【ERROR】：镜像仓库UI镜像拉取失败"
    exit 1
fi

echo "----正在启动镜像仓库UI----"
$CONTAINER_CMD run -d --name registry-ui-5080 --restart always -p 5080:80 \
    -e REGISTRY_TITLE=Registry \
    -e REGISTRY_URL=http://${REGISTRY_IP}:5000 \
    -e DELETE_IMAGES=true \
    registry:5000/joxit/docker-registry-ui:main

if [ $? -ne 0 ]; then
    echo "【ERROR】：镜像仓库UI启动失败"
    exit 1
fi
echo "【SUCCESS】：镜像仓库UI启动成功"
