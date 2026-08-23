# KubeFoundry K8S 集群一键安装工具设计方案

> 维护状态：本文记录早期 Bash CLI 架构。自 v0.3.2 起，项目停止支持旧 CLI，`scripts/main.sh` 已删除；当前安装入口、任务编排和状态管理以 Web Wizard Java 后端及 `doc/v0.3.2/` 版本文档为准。本文中的 CLI 示例仅作为历史设计记录，不可用于当前版本操作。

## 一、需求分析

### 1.1 功能需求
- 基于现有的 `doc/cmdlist.md` 手动安装命令
- 代码简单、可读性高
- 最小 MVP：部署 K8S 集群 + 安装 CNI 插件-Flannel
- 每个步骤预留验证步骤（可以先不实现）
- 支持多控制节点（高可用）

### 1.2 技术选型
**推荐：纯 Bash 脚本**

**理由：**
- 文档中的命令本身是 Bash 命令，可直接复用
- 无需额外依赖，简单易维护
- 可读性高，便于调试和修改
- 符合运维习惯

---

## 二、MVP 范围

根据 `doc/cmdlist.md`，MVP 覆盖以下步骤：

### 阶段 1：前置检查
- 2.1 初始化参数配置
- 2.2 检查配置文件完整性
- 2.3 检查必要工具安装

### 阶段 2：环境配置
- 3.1 配置本地 yum 源（控制节点）
- 3.3 配置 k8s repo 源客户端（其他节点）
- 3.4 安装 K8s 依赖包
- 3.5 替换 kubeadm（100年证书）
- 3.6 环境配置（DNS、网络、主机名、open files、环境变量）

### 阶段 3：容器运行时
- 3.7 安装 containerd（所有节点）
- 3.8 安装镜像仓库（registry 节点）

### 阶段 4：K8S 集群
- 3.9.1 初始化 K8S 集群（k8sc1）
- 3.9.2 修改证书有效期
- 3.9.3 添加 K8S 控制节点（k8sc2、k8sc3）
- 3.9.4 添加 K8S 工作节点（k8sw1-k8sw6）
- 3.9.5 安装 CNI 插件-Flannel

---

## 三、项目结构设计

```
KubeFoundry/
├── scripts/                    # 脚本目录
│   ├── lib/                  # 公共函数库
│   │   ├── logger.sh        # 日志函数（颜色、格式）
│   │   ├── config.sh        # 配置解析函数
│   │   ├── ssh.sh          # SSH/SCP 执行函数
│   │   └── rollback.sh     # 回滚函数
│   ├── steps/               # 各步骤脚本
│   │   ├── 01_precheck.sh   # 前置检查
│   │   ├── 02_env_config.sh # 环境配置
│   │   ├── 03_containerd.sh # Containerd 安装
│   │   ├── 04_k8s_install.sh# K8S 安装
│   │   └── 05_cni.sh       # CNI 插件
│   └── verify/              # 验证脚本（预留）
│       ├── 01_precheck_verify.sh
│       ├── 02_env_config_verify.sh
│       ├── 03_containerd_verify.sh
│       ├── 04_k8s_verify.sh
│       └── 05_cni_verify.sh
├── config/                    # 配置文件
│   └── cluster.yaml         # 集群配置（YAML 格式）
├── templates/                 # 模板文件
│   └── kube-flannel.yml     # Flannel 配置模板
└── doc/                      # 文档目录
    ├── cmdlist.md           # 原始命令清单
    └── design.md            # 本设计文档
```

---

## 四、跨服务器执行机制

### 4.1 管理节点概念

**管理节点（Management Node）：**
- 即运行 Web Wizard 服务的机器
- 负责向其他节点发送命令和传输文件
- 可以是任何可以 SSH 连接到所有 K8S 节点的机器

**节点分类：**

| 节点类型 | 数量 | 示例 | 说明 |
|---------|------|------|------|
| 控制节点（Control Plane） | 3 | k8sc1, k8sc2, k8sc3 | K8S 控制平面，k8sc1 为第一控制节点 |
| 工作节点（Worker） | 6 | k8sw1-6 | K8S 工作节点 |
| 镜像仓库（Registry） | 1 | registry | Docker 镜像仓库（与 k8sc3 同机） |

### 4.2 SSH 执行机制

#### 4.2.1 前置要求

管理节点需要配置 SSH 免密登录到所有 K8S 节点：

```bash
# 在管理节点执行
ssh-keygen -t rsa -b 4096  # 生成 SSH 密钥（如果不存在）

# 复制公钥到所有节点
ssh-copy-id root@10.3.66.18  # k8sc1
ssh-copy-id root@10.3.66.19  # k8sc2
ssh-copy-id root@10.3.66.20  # k8sc3
ssh-copy-id root@10.3.66.21  # k8sw1
# ... (所有节点）
```

#### 4.2.2 执行模式

**模式 1：本地执行（管理节点）**
- 适用：配置文件解析、日志输出、主流程控制
- 示例：加载配置、生成 K8S 配置文件

**模式 2：远程单节点执行**
- 适用：仅在特定节点执行的命令
- 示例：在 k8sc1 上初始化集群

**模式 3：远程批量执行**
- 适用：在所有/某类节点上执行的命令
- 示例：在所有节点安装 containerd

**模式 4：文件传输 + 远程执行**
- 适用：需要先传输文件再执行的命令
- 示例：传输 kubeadm 二进制文件到 k8sc1

### 4.3 节点分组和批量执行

#### 4.3.1 节点分组

根据配置文件中的节点定义，将节点分为以下组：

```yaml
# 从 config/cluster.yaml 读取
control_plane:  # 控制节点组
  - k8sc1 (10.3.66.18)
  - k8sc2 (10.3.66.19)
  - k8sc3 (10.3.66.20)

workers:  # 工作节点组
  - k8sw1 (10.3.66.21)
  - k8sw2 (10.3.66.22)
  - k8sw3 (10.3.66.23)
  - k8sw4 (10.3.66.24)
  - k8sw5 (10.3.66.25)
  - k8sw6 (10.3.66.26)

registry:  # 镜像仓库节点
  - registry (10.3.66.20)

all_nodes:  # 所有节点
  - control_plane + workers + registry
```

#### 4.3.2 批量执行函数

```bash
# 函数：在所有控制节点执行命令
exec_on_control_plane() {
    local command=$1
    local nodes=$(config_get_array '.control_plane')

    for node in $nodes; do
        local node_ip=$(echo "$node" | jq -r '.ip')
        local node_hostname=$(echo "$node" | jq -r '.hostname')

        log_info "在控制节点 $node_hostname ($node_ip) 执行..."
        ssh_exec "$node_ip" "$command"
    done
}

# 函数：在所有工作节点执行命令
exec_on_workers() {
    local command=$1
    local nodes=$(config_get_array '.workers')

    for node in $nodes; do
        local node_ip=$(echo "$node" | jq -r '.ip')
        local node_hostname=$(echo "$node" | jq -r '.hostname')

        log_info "在工作节点 $node_hostname ($node_ip) 执行..."
        ssh_exec "$node_ip" "$command"
    done
}

# 函数：在镜像仓库节点执行命令
exec_on_registry() {
    local command=$1
    local node=$(config_get '.registry')

    local node_ip=$(echo "$node" | jq -r '.ip')
    local node_hostname=$(echo "$node" | jq -r '.hostname')

    log_info "在镜像仓库节点 $node_hostname ($node_ip) 执行..."
    ssh_exec "$node_ip" "$command"
}

# 函数：在所有节点执行命令
exec_on_all_nodes() {
    local command=$1

    exec_on_control_plane "$command"
    exec_on_workers "$command"
    exec_on_registry "$command"
}
```

#### 4.3.3 批量执行脚本函数（支持参数）

```bash
# 函数：在所有控制节点执行脚本
exec_script_on_control_plane() {
    local script_path=$1    # 本地脚本路径
    shift                   # 移除第一个参数
    local script_args="$@"   # 剩余参数（脚本参数）
    local nodes=$(config_get_array '.control_plane')

    for node in $nodes; do
        local node_ip=$(echo "$node" | jq -r '.ip')
        local node_hostname=$(echo "$node" | jq -r '.hostname')

        log_info "在控制节点 $node_hostname ($node_ip) 执行脚本: $script_path"

        # 传输脚本到远程节点
        local remote_script="/tmp/$(basename "$script_path")"
        scp_exec "$script_path" "$remote_script" "$node_ip"

        # 执行脚本（带参数）
        ssh_exec "$node_ip" "bash $remote_script $script_args"

        # 清理远程脚本（可选）
        # ssh_exec "$node_ip" "rm -f $remote_script"
    done
}

# 函数：在所有工作节点执行脚本
exec_script_on_workers() {
    local script_path=$1
    shift
    local script_args="$@"
    local nodes=$(config_get_array '.workers')

    for node in $nodes; do
        local node_ip=$(echo "$node" | jq -r '.ip')
        local node_hostname=$(echo "$node" | jq -r '.hostname')

        log_info "在工作节点 $node_hostname ($node_ip) 执行脚本: $script_path"

        local remote_script="/tmp/$(basename "$script_path")"
        scp_exec "$script_path" "$remote_script" "$node_ip"
        ssh_exec "$node_ip" "bash $remote_script $script_args"
    done
}

# 函数：在镜像仓库节点执行脚本
exec_script_on_registry() {
    local script_path=$1
    shift
    local script_args="$@"
    local node=$(config_get '.registry')

    local node_ip=$(echo "$node" | jq -r '.ip')
    local node_hostname=$(echo "$node" | jq -r '.hostname')

    log_info "在镜像仓库节点 $node_hostname ($node_ip) 执行脚本: $script_path"

    local remote_script="/tmp/$(basename "$script_path")"
    scp_exec "$script_path" "$remote_script" "$node_ip"
    ssh_exec "$node_ip" "bash $remote_script $script_args"
}

# 函数：在所有节点执行脚本
exec_script_on_all_nodes() {
    local script_path=$1
    shift
    local script_args="$@"

    exec_script_on_control_plane "$script_path" "$script_args"
    exec_script_on_workers "$script_path" "$script_args"
    exec_script_on_registry "$script_path" "$script_args"
}
```

### 4.4 SSH 执行示例

#### 4.4.1 简单命令执行

```bash
# 在管理节点定义的函数
ssh_exec() {
    local node_ip=$1
    local command=$2
    local ssh_user="root"
    local ssh_key="~/.ssh/id_rsa"

    ssh -o ConnectTimeout=30 \
        -o StrictHostKeyChecking=no \
        -i "$ssh_key" \
        "${ssh_user}@${node_ip}" \
        "$command"
}

# 使用示例
ssh_exec "10.3.66.18" "hostnamectl set-hostname k8sc1"
```

#### 4.4.2 复杂命令执行（包含变量）

```bash
# 方法 1：使用单引号包裹整个命令
ssh_exec "10.3.66.18" 'systemctl enable --now containerd'

# 方法 2：使用 HERE-DOC
ssh_exec "10.3.66.18" <<'SSH_CMD'
systemctl enable --now containerd
nerdctl version
SSH_CMD

# 方法 3：先传输脚本，再执行
scp_exec "/local/script.sh" "/tmp/script.sh" "10.3.66.18"
ssh_exec "10.3.66.18" "bash /tmp/script.sh"
```

### 4.5 SCP 文件传输

```bash
# 在管理节点定义的函数
scp_exec() {
    local source=$1      # 本地文件路径
    local dest=$2        # 目标路径（远程）
    local node_ip=$3      # 目标节点 IP
    local ssh_user="root"
    local ssh_key="~/.ssh/id_rsa"

    scp -o ConnectTimeout=30 \
        -o StrictHostKeyChecking=no \
        -i "$ssh_key" \
        "$source" \
        "${ssh_user}@${node_ip}:${dest}"
}

# 使用示例
# 传输配置文件
scp_exec "./config/kubeadm.yaml" "/tmp/kubeadm.yaml" "10.3.66.18"

# 传输二进制文件
scp_exec "./bin/kubeadm" "/usr/bin/kubeadm" "10.3.66.18"
```

### 4.6 各步骤执行节点说明

| 步骤 | 执行节点 | 说明 |
|------|---------|------|
| 1. 前置检查 | 管理节点（本地） | 检查 SSH 连接到所有节点 |
| 2.1 配置 yum 源 | k8sc1 | 仅在第一控制节点 |
| 2.2 配置 repo 客户端 | k8sc2, k8sc3, k8sw1-6 | 除 k8sc1 外的所有节点 |
| 2.3 安装依赖包 | 所有节点 | control_plane + workers |
| 2.4 替换 kubeadm | k8sc1 | 仅在第一控制节点 |
| 2.5 环境配置 | 所有节点 | control_plane + workers |
| 3. 安装 containerd | 所有节点 | control_plane + workers |
| 4. 安装镜像仓库 | registry | 镜像仓库节点 |
| 4.1 初始化集群 | k8sc1 | 仅在第一控制节点 |
| 4.2 修改证书 | k8sc1 | 仅在第一控制节点 |
| 4.3 添加控制节点 | k8sc2, k8sc3 | 其他控制节点 |
| 4.4 添加工作节点 | k8sw1-6 | 所有工作节点 |
| 5. 安装 CNI | k8sc1 | 通过 kubectl 执行，影响所有节点 |

### 4.7 错误处理机制

#### 4.7.1 SSH 连接失败处理

```bash
# 检查 SSH 连接
check_ssh_connection() {
    local node_ip=$1
    local timeout=5

    if ssh -o ConnectTimeout="$timeout" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        root@"${node_ip}" \
        "echo OK" 2>/dev/null; then
        return 0  # 成功
    else
        log_error "无法连接到节点 $node_ip"
        log_error "请检查："
        log_error "  1. 节点是否启动"
        log_error "  2. SSH 服务是否运行（systemctl status sshd）"
        log_error "  3. 网络连通性（ping $node_ip）"
        log_error "  4. SSH 密钥是否配置（ssh-copy-id root@$node_ip）"
        return 1  # 失败
    fi
}
```

#### 4.7.2 远程命令执行失败处理

```bash
# 带错误检查的远程执行
ssh_exec_with_check() {
    local node_ip=$1
    local command=$2

    log_info "在节点 $node_ip 执行: $command"

    if ssh_exec "$node_ip" "$command"; then
        log_success "命令执行成功"
        return 0
    else
        log_error "命令执行失败"
        log_error "节点: $node_ip"
        log_error "命令: $command"
        log_error "请登录节点手动检查: ssh root@$node_ip"
        return 1
    fi
}
```

### 4.8 完整执行示例

```bash
# 示例：在所有节点安装 containerd
install_containerd_on_all_nodes() {
    log_info "开始在所有节点安装 containerd..."

    # 1. 传输安装包到每个节点
    for node_ip in $(get_all_node_ips); do
        log_info "传输安装包到 $node_ip..."
        scp_exec "./packages/containerd.tar.gz" "/tmp/containerd.tar.gz" "$node_ip"
    done

    # 2. 在每个节点执行安装
    for node_ip in $(get_all_node_ips); do
        log_info "在节点 $node_ip 安装 containerd..."
        ssh_exec "$node_ip" <<'SSH_CMD'
cd /tmp
tar -zxf containerd.tar.gz -C /usr/local/
systemctl enable --now containerd
SSH_CMD
    done

    # 3. 验证安装
    for node_ip in $(get_all_node_ips); do
        log_info "验证节点 $node_ip 的 containerd..."
        ssh_exec "$node_ip" "systemctl status containerd | grep active"
    done

    log_success "containerd 在所有节点安装完成"
}
```

---

## 五、执行流程设计

### 5.1 主流程

```
开始
  │
  ├─ 1. 加载配置文件（cluster.yaml）
  │
  ├─ 2. 显示配置摘要
  │
  ├─ 3. 依次执行步骤
  │   │
  │   ├─ 步骤 1: 前置检查
  │   │   ├─ 执行 01_precheck.sh
  │   │   ├─ 验证（如果 verify 脚本存在）
  │   │   └─ 记录完成状态
  │   │
  │   ├─ 步骤 2: 环境配置
  │   │   ├─ 执行 02_env_config.sh
  │   │   ├─ 验证（如果 verify 脚本存在）
  │   │   └─ 记录完成状态
  │   │
  │   ├─ 步骤 3: Containerd 安装
  │   │   ├─ 执行 03_containerd.sh
  │   │   ├─ 验证（如果 verify 脚本存在）
  │   │   └─ 记录完成状态
  │   │
  │   ├─ 步骤 4: K8S 安装
  │   │   ├─ 执行 04_k8s_install.sh
  │   │   ├─ 验证（如果 verify 脚本存在）
  │   │   └─ 记录完成状态
  │   │
  │   └─ 步骤 5: CNI 插件
  │       ├─ 执行 05_cni.sh
  │       ├─ 验证（如果 verify 脚本存在）
  │       └─ 记录完成状态
  │
  ├─ 4. 显示最终结果
  │
  └─ 结束
```

### 4.2 错误处理流程

```
执行步骤
  │
  ├─ 成功？
  │   ├─ 是 → 执行验证
  │   │       ├─ 验证成功 → 下一步骤
  │   │       └─ 验证失败 → 触发回滚
  │   └─ 否 → 触发回滚
  │
  回滚流程
  │
  ├─ 从后往前回滚已完成的步骤
  ├─ 每个步骤执行对应的 rollback 脚本
  ├─ 输出回滚日志
  └─ 退出并提示错误
```

---

## 五、各步骤详细设计

### 6.1 步骤 1：前置检查（01_precheck.sh）

**执行内容：**
1. 检查本地必要工具（ssh、scp、rsync、jq、bc、yq）
2. 验证配置文件格式（YAML 语法）
3. 验证配置项完整性
4. 验证节点 IP 地址格式（IPv4、IPv6）
5. 验证 SSH 连接（到所有节点）

**预留验证命令（01_precheck_verify.sh）：**
```bash
# TODO: 实现以下验证

# 1. 检查 SSH 连接
ssh root@k8sc1 "hostname"

# 2. 检查配置文件格式
yq eval '.' config/cluster.yaml

# 3. 检查必要工具
which ssh && which scp && which jq && which yq
```

---

### 6.2 步骤 2：环境配置（02_env_config.sh）

**执行内容：**

#### 2.1 配置 yum 源（仅在 k8sc1 执行）
- 解压 repo 源到 /var/www/html/
- 配置本地 yum 源
- 安装 httpd 服务
- 关闭防火墙

#### 2.2 配置 repo 源客户端（其他节点执行）
- 配置 k8s-http.repo

#### 2.3 安装 K8s 依赖包（所有节点执行）
- yum install -y cri-tools kubeadm kubectl kubelet kubernetes-cni nfs

#### 2.4 替换 kubeadm（k8sc1 执行）
- 备份原始 kubeadm
- 替换为支持 100 年证书版本

#### 2.5 环境配置（所有节点执行）
- 修改 DNS
- 修改网络配置（IPv6）
- 修改主机名
- 修改 open files 参数
- 配置环境变量
  - 关闭 swap
  - 关闭防火墙
  - 卸载 podman
  - 配置内核参数
  - 加载内核模块

**预留验证命令（02_env_config_verify.sh）：**
```bash
# TODO: 实现以下验证

# 1. 检查 swap 状态
swapoff -a && free -h

# 2. 检查防火墙状态
systemctl status firewalld | grep "inactive"

# 3. 检查主机名
hostname

# 4. 检查 hosts 文件
cat /etc/hosts | grep k8sc1

# 5. 检查内核参数
sysctl net.ipv4.ip_forward
sysctl net.bridge.bridge-nf-call-iptables

# 6. 检查内核模块
lsmod | grep overlay
lsmod | grep br_netfilter

# 7. 检查 K8s 工具版本
kubeadm version
kubectl version --client
kubelet --version
```

---

### 6.3 步骤 3：Containerd 安装（03_containerd.sh）

**执行内容（所有节点执行）：**
1. 解压 containerd 到 /usr/local/
2. 安装 runc
3. 安装 cni-plugins
4. 配置 containerd
5. 安装 buildkit
6. 安装 nerdctl
7. 配置镜像仓库地址
8. 启动 containerd 服务

**预留验证命令（03_containerd_verify.sh）：**
```bash
# TODO: 实现以下验证

# 1. 检查 containerd 服务状态
systemctl status containerd | grep "active"

# 2. 检查 nerdctl 版本
nerdctl version

# 3. 拉取测试镜像
nerdctl pull busybox

# 4. 运行测试容器
nerdctl run --rm busybox echo "Containerd 工作正常"

# 5. 检查 containerd 配置
containerd config dump
```

---

### 6.4 步骤 4：K8S 安装（04_k8s_install.sh）

**执行内容：**

#### 4.1 初始化集群（k8sc1 执行）
- 生成 kubeadm 配置文件（基于 cluster.yaml）
- 执行 kubeadm init
- 配置 kubectl
- 保存 join 命令

#### 4.2 修改证书有效期（k8sc1 执行）
- 修改 kube-controller-manager.yaml

#### 4.3 添加控制节点（k8sc2、k8sc3 执行）
- 执行 kubeadm join 控制节点命令

#### 4.4 添加工作节点（k8sw1-k8sw6 执行）
- 执行 kubeadm join 工作节点命令

**预留验证命令（04_k8s_verify.sh）：**
```bash
# TODO: 实现以下验证

# 1. 检查节点状态
kubectl get nodes

# 2. 检查系统 Pod 状态
kubectl get pods -n kube-system

# 3. 检查证书有效期
kubeadm certs check-expiration

# 4. 检查 kubectl 配置
kubectl config view
```

---

### 6.5 步骤 5：CNI 插件（05_cni.sh）

**执行内容（k8sc1 执行）：**
1. 检查 Flannel 配置文件
2. 应用 Flannel YAML

**预留验证命令（05_cni_verify.sh）：**
```bash
# TODO: 实现以下验证

# 1. 检查节点状态（应为 Ready）
kubectl get nodes

# 2. 检查 Flannel Pod 状态
kubectl get pods -n kube-flannel

# 3. 检查所有 Pod 状态
kubectl get pods -A

# 4. 部署测试应用
kubectl run test-nginx --image=nginx --replicas=1
kubectl get pods

# 5. 清理测试应用
kubectl delete pod test-nginx
```

---

## 七、配置文件设计

### 7.1 配置文件格式（config/cluster.yaml）

```yaml
# 集群基本信息
cluster:
  name: "k8s-cluster"
  k8s_version: "1.29.0"
  pod_subnet: "10.244.0.0/16"
  service_subnet: "10.96.0.0/16"

# 控制节点配置
control_plane:
  - hostname: "k8sc1"
    ip: "10.3.66.18"
    ipv6: "fd00:42::18"
  - hostname: "k8sc2"
    ip: "10.3.66.19"
    ipv6: "fd00:42::19"
  - hostname: "k8sc3"
    ip: "10.3.66.20"
    ipv6: "fd00:42::20"

# 工作节点配置
workers:
  - hostname: "k8sw1"
    ip: "10.3.66.21"
    ipv6: "fd00:42::21"
  - hostname: "k8sw2"
    ip: "10.3.66.22"
    ipv6: "fd00:42::22"
  - hostname: "k8sw3"
    ip: "10.3.66.23"
    ipv6: "fd00:42::23"
  - hostname: "k8sw4"
    ip: "10.3.66.24"
    ipv6: "fd00:42::24"
  - hostname: "k8sw5"
    ip: "10.3.66.25"
    ipv6: "fd00:42::25"
  - hostname: "k8sw6"
    ip: "10.3.66.26"
    ipv6: "fd00:42::26"

# 镜像仓库配置
registry:
  hostname: "registry"
  ip: "10.3.66.20"
  port: 5000

# 网络配置
network:
  gateway: "10.3.66.1"
  ipv6_gateway: "fd00::1"

# API Server 端口固定为 6443，不提供配置项

# SSH 配置
ssh:
  user: "root"
  port: 22
  key_path: "~/.ssh/id_rsa"

# 路径配置
paths:
  k8s_install: "/data/k8s_install"
  repo_source: "/path/to/repo.tar.gz"
  kubeadm_100y: "/path/to/kubeadm-100y"
```

### 7.2 配置解析

使用 `yq` 工具解析 YAML 配置：
```bash
# 安装 yq
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# 使用 yq 读取配置
k8s_version=$(yq eval '.cluster.k8s_version' config/cluster.yaml)
control_plane_count=$(yq eval '.control_plane | length' config/cluster.yaml)
```

---

## 八、公共函数设计

**详细接口文档请参考：** [doc/api.md](./api.md)

### 8.1 函数库说明

项目提供以下公共函数库，每个步骤脚本都可以引用：

| 函数库文件 | 功能 | 包含函数 |
|----------|------|---------|
| `scripts/lib/logger.sh` | 日志输出 | log_info, log_success, log_warn, log_error |
| `scripts/lib/config.sh` | 配置解析 | load_config, config_get, config_get_array, config_get_length |
| `scripts/lib/ssh.sh` | SSH/SCP 操作 | ssh_exec, scp_exec, check_ssh_connection |
| `scripts/lib/exec.sh` | 批量执行（命令） | exec_on_control_plane, exec_on_workers, exec_on_registry, exec_on_all_nodes |
| `scripts/lib/exec_script.sh` | 批量执行（脚本） | exec_script_on_control_plane, exec_script_on_workers, exec_script_on_registry, exec_script_on_all_nodes |
| `scripts/lib/rollback.sh` | 回滚操作 | rollback_package, rollback_service, rollback_file, rollback_directory, backup_file, backup_directory |
| `scripts/lib/validator.sh` | 验证函数 | validate_ip, validate_ipv6, validate_port, validate_command, validate_file, validate_directory, validate_ssh |

### 8.2 函数引用方式

**步骤脚本中引用函数库：**
```bash
#!/bin/bash

# 引入公共函数库
source "$SCRIPT_DIR/lib/logger.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/ssh.sh"
source "$SCRIPT_DIR/lib/exec.sh"
source "$SCRIPT_DIR/lib/exec_script.sh"
source "$SCRIPT_DIR/lib/rollback.sh"
source "$SCRIPT_DIR/lib/validator.sh"

# 使用函数
log_info "开始安装..."
exec_on_control_plane "hostnamectl set-hostname k8sc1"
```

### 8.3 关键函数使用说明

```bash
# 颜色定义
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_NC='\033[0m' # No Color

# 日志文件
LOG_FILE="/tmp/kubefoundry_install.log"

# 日志函数
log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $*" | tee -a "$LOG_FILE"
}
```

### 8.2 配置解析函数（lib/config.sh）

```bash
# 加载配置
load_config() {
    local config_file="config/cluster.yaml"
    yq eval '.' "$config_file" &>/dev/null || return 1
    return 0
}

# 获取配置值
config_get() {
    local path=$1
    yq eval "$path" config/cluster.yaml
}

# 获取数组
config_get_array() {
    local path=$1
    yq eval "$path[]" config/cluster.yaml
}
```

### 8.3 SSH 执行函数

**详细接口请参考：** [doc/api.md#三sshscp-函数](./api.md#三sshscp-函数)

```bash
# 基础 SSH 执行
ssh_exec "10.3.66.18" "hostnamectl set-hostname k8sc1"

# 文件传输
scp_exec "./config/kubeadm.yaml" "/tmp/kubeadm.yaml" "10.3.66.18"
```

```bash
# SSH 执行
ssh_exec() {
    local node=$1
    local command=$2
    local ssh_user="root"
    local ssh_key="~/.ssh/id_rsa"

    ssh -o StrictHostKeyChecking=no \
        -i "$ssh_key" \
        "${ssh_user}@${node}" \
        "$command"
}

# SCP 传输
scp_exec() {
    local source=$1
    local dest=$2
    local node=$3
    local ssh_user="root"
    local ssh_key="~/.ssh/id_rsa"

    scp -o StrictHostKeyChecking=no \
        -i "$ssh_key" \
        "$source" \
        "${ssh_user}@${node}:${dest}"
}
```

### 8.6 回滚函数

**详细接口请参考：** [doc/api.md#六回滚函数](./api.md#六回滚函数)

```bash
# 卸载包
rollback_package "containerd"

# 停止服务
rollback_service "containerd"

# 回滚文件
rollback_file "/etc/containerd/config.toml"

# 回滚目录
rollback_directory "/etc/containerd"

# 备份文件
backup_file "/etc/containerd/config.toml"

# 备份目录
backup_directory "/etc/containerd"
```

```bash
# 回滚包
rollback_package() {
    local package=$1
    rpm -q "$package" &>/dev/null && yum remove -y "$package"
}

# 回滚服务
rollback_service() {
    local service=$1
    systemctl stop "$service" 2>/dev/null
    systemctl disable "$service" 2>/dev/null
}

# 回滚文件
rollback_file() {
    local file=$1
    local backup="${file}.backup"
    [ -f "$backup" ] && mv "$backup" "$file" || rm -f "$file"
}
```

---

## 九、使用方式

### 9.1 准备工作

```bash
# 1. 克隆项目
git clone <repo> KubeFoundry
cd KubeFoundry

# 2. 安装必要工具
yum install -y yq jq bc

# 3. 配置 SSH 免密登录
ssh-copy-id root@k8sc1
ssh-copy-id root@k8sc2
# ... (所有节点）
```

### 9.2 编辑配置

```bash
# 根据实际环境修改配置
vi config/cluster.yaml
```

### 9.3 执行安装

在 Web Wizard 中完成集群配置和节点测试后发起安装。Java 后端负责生成任务计划并调用 Bash 步骤，不提供独立 CLI 入口。

### 9.4 查看日志

```bash
# 查看安装日志
tail -f /tmp/kubefoundry_install.log
```

---

## 十、验证清单

### 10.1 各步骤验证命令

| 步骤 | 验证命令 | 期望结果 |
|------|---------|---------|
| 前置检查 | `ssh root@k8sc1 "hostname"` | 能连接到所有节点 |
| 环境配置 | `kubeadm version` | 工具安装成功 |
| Containerd | `nerdctl pull busybox` | 能拉取镜像 |
| K8S 安装 | `kubectl get nodes` | 能看到节点 |
| CNI 插件 | `kubectl get pods -A` | 所有 Pod Running |

### 10.2 最终验证

```bash
# 1. 检查节点状态
kubectl get nodes
# 期望：所有节点状态为 Ready

# 2. 检查系统 Pod
kubectl get pods -n kube-system
# 期望：所有 Pod 状态为 Running

# 3. 检查 Flannel Pod
kubectl get pods -n kube-flannel
# 期望：Flannel Pod 状态为 Running

# 4. 部署测试应用
kubectl run test-nginx --image=nginx --replicas=3
kubectl get pods
# 期望：所有 Pod 状态为 Running

# 5. 清理测试应用
kubectl delete pod test-nginx
```

---

## 十一、实现优先级

### Phase 1：基础框架（优先）
1. 创建项目目录结构
2. 实现 Web Wizard 后端任务编排入口
3. 实现公共函数库（logger.sh、config.sh、ssh.sh、rollback.sh）
4. 创建配置文件模板（cluster.yaml）

### Phase 2：核心步骤（优先）
1. 实现前置检查（01_precheck.sh）
2. 实现环境配置（02_env_config.sh）
3. 实现容器运行时安装（03_containerd.sh）
4. 实现 K8S 安装（04_k8s_install.sh）
5. 实现 CNI 插件（05_cni.sh）

### Phase 3：验证完善（可延后）
1. 实现各步骤验证脚本
2. 完善错误处理
3. 完善回滚机制
4. 更新文档

---

## 十二、注意事项

### 12.1 开发原则
1. 代码简单，可读性高
2. 每个步骤独立，易于调试
3. 详细的日志输出
4. 完善的错误提示
5. 预留验证接口

### 12.2 测试建议
1. 先在测试环境验证
2. 分步骤测试，逐步完善
3. 保留完整的日志
4. 记录遇到的问题和解决方案

### 12.3 后续扩展
1. 第二阶段可扩展 Kubemate 等生态组件
2. 支持不同的 CNI 插件（Calico、Cilium）
3. 支持不同的容器运行时
4. 支持 ARM64 架构
5. 支持 Windows 工作节点

---

## 十三、文件清单

### 13.1 需要创建的文件

**脚本文件：**
- `scripts/lib/logger.sh` - 日志函数
- `scripts/lib/config.sh` - 配置解析
- `scripts/lib/ssh.sh` - SSH 执行
- `scripts/lib/rollback.sh` - 回滚函数
- `scripts/steps/01_precheck.sh` - 前置检查
- `scripts/steps/02_env_config.sh` - 环境配置
- `scripts/steps/03_containerd.sh` - Containerd 安装
- `scripts/steps/04_k8s_install.sh` - K8S 安装
- `scripts/steps/05_cni.sh` - CNI 插件
- `scripts/verify/*.sh` - 验证脚本（5个）

**配置文件：**
- `config/cluster.yaml` - 集群配置

**文档文件：**
- `doc/design.md` - 设计文档（本文件）

### 13.2 需要修改的文件

- `README.md` - 更新项目说明
- `CLAUDE.md` - 更新开发指南

---

## 十四、总结

本设计方案满足以下要求：

1. ✅ 代码简单、可读性高（纯 Bash 脚本）
2. ✅ MVP 覆盖 K8S 集群 + CNI 插件安装
3. ✅ 每个步骤预留验证步骤
4. ✅ 支持多控制节点（高可用）
5. ✅ 模块化设计，易于维护和扩展

**下一步：** 请审阅本方案，确认后开始开发实现。
