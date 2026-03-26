# KubeFoundry 接口文档

本文档描述 KubeFoundry 一键安装工具的所有公共函数接口。

---

## 目录

- [一、日志函数](#一日志函数)
- [二、配置解析函数](#二配置解析函数)
- [三、SSH/SCP 函数](#三sshscp-函数)
- [四、批量执行函数（命令）](#四批量执行函数命令）
- [五、批量执行函数（脚本）](#五批量执行函数脚本)
- [六、回滚函数](#六回滚函数)
- [七、验证函数](#七验证函数)

---

## 一、日志函数

文件位置：`scripts/lib/logger.sh`

### 1.1 log_info()

**功能：** 输出 INFO 级别日志

**参数：**
- `$@` - 日志内容（支持多个参数）

**返回值：** 无

**示例：**
```bash
log_info "开始安装 containerd..."
log_info "节点 $hostname 配置完成"
```

---

### 1.2 log_success()

**功能：** 输出 SUCCESS 级别日志（绿色）

**参数：**
- `$@` - 日志内容（支持多个参数）

**返回值：** 无

**示例：**
```bash
log_success "containerd 安装完成"
log_success "K8S 集群部署成功"
```

---

### 1.3 log_warn()

**功能：** 输出 WARN 级别日志（黄色）

**参数：**
- `$@` - 日志内容（支持多个参数）

**返回值：** 无

**示例：**
```bash
log_warn "registry 节点与 k8sc3 同机"
log_warn "证书有效期未配置，使用默认值"
```

---

### 1.4 log_error()

**功能：** 输出 ERROR 级别日志（红色）

**参数：**
- `$@` - 日志内容（支持多个参数）

**返回值：** 无

**示例：**
```bash
log_error "SSH 连接失败: $node_ip"
log_error "配置文件不存在: $config_file"
```

---

## 二、配置解析函数

文件位置：`scripts/lib/config.sh`

### 2.1 config_get()

**功能：** 从配置文件中获取单个配置值

**参数：**
- `$1` - YAML 路径（如 `.cluster.k8s_version`）
- `$2` - 默认值（可选）

**返回值：** 配置值（字符串）

**示例：**
```bash
# 获取 K8S 版本
k8s_version=$(config_get '.cluster.k8s_version')

# 获取 Pod 网段，默认值
pod_subnet=$(config_get '.cluster.pod_subnet' "10.244.0.0/16")

# 获取 API 端口，默认值
api_port=$(config_get '.network.api_server_port' 6443)
```

---

### 2.2 config_get_array()

**功能：** 从配置文件中获取数组

**参数：**
- `$1` - YAML 路径（如 `.control_plane`）

**返回值：** 数组（每行一个元素）

**示例：**
```bash
# 获取控制节点列表
control_plane=$(config_get_array '.control_plane')

# 获取工作节点列表
workers=$(config_get_array '.workers')
```

---

### 2.3 config_get_length()

**功能：** 获取数组长度

**参数：**
- `$1` - YAML 路径（如 `.control_plane`）

**返回值：** 数组长度（数字）

**示例：**
```bash
# 获取控制节点数量
control_plane_count=$(config_get_length '.control_plane')

# 获取工作节点数量
worker_count=$(config_get_length '.workers')
```

---

### 2.4 load_config()

**功能：** 加载并验证配置文件

**参数：**
- `$1` - 配置文件路径

**返回值：**
- `0` - 成功
- `1` - 失败

**示例：**
```bash
if ! load_config "config/cluster.yaml"; then
    log_error "配置加载失败"
    exit 1
fi
```

---

### 2.5 get_node_hostname()

**功能：** 根据节点 IP 地址获取主机名

**参数：**
- `$1` - 节点 IP 地址

**返回值：** 节点主机名

**示例：**
```bash
# 获取节点主机名
hostname=$(get_node_hostname "10.3.66.18")
# 返回：k8sc1

# 用于日志输出
node_ip="10.3.66.18"
node_hostname=$(get_node_hostname "$node_ip")
log_info "正在处理节点: $node_hostname ($node_ip)"
```

---

## 三、SSH/SCP 函数

文件位置：`scripts/lib/ssh.sh`

### 3.1 ssh_exec()

**功能：** 在远程节点执行单个命令

**参数：**
- `$1` - 节点 IP 地址
- `$2` - 要执行的命令

**返回值：**
- `0` - 成功
- 非 0 - 失败

**示例：**
```bash
# 设置主机名
ssh_exec "10.3.66.18" "hostnamectl set-hostname k8sc1"

# 启动服务
ssh_exec "10.3.66.18" "systemctl enable --now containerd"

# 检查服务状态
ssh_exec "10.3.66.18" "systemctl status containerd"
```

---

### 3.2 scp_exec()

**功能：** 传输文件到远程节点

**参数：**
- `$1` - 本地文件路径
- `$2` - 远程目标路径
- `$3` - 目标节点 IP

**返回值：**
- `0` - 成功
- 非 0 - 失败

**示例：**
```bash
# 传输配置文件
scp_exec "./config/kubeadm.yaml" "/tmp/kubeadm.yaml" "10.3.66.18"

# 传输二进制文件
scp_exec "./bin/kubeadm" "/usr/bin/kubeadm" "10.3.66.18"

# 传输压缩包
scp_exec "./packages/containerd.tar.gz" "/tmp/" "10.3.66.18"
```

---

### 3.3 check_ssh_connection()

**功能：** 检查 SSH 连接是否可用

**参数：**
- `$1` - 节点 IP 地址
- `$2` - SSH 用户名（可选，默认从配置文件读取）
- `$3` - SSH 端口（可选，默认从配置文件读取）
- `$4` - SSH 密钥路径（可选，默认从配置文件读取）
- `$5` - 连接超时时间（可选，默认从配置文件读取）

**返回值：**
- `0` - 连接成功
- `1` - 连接失败

**说明：**
- 如果未提供可选参数，将从 `config/cluster.yaml` 读取默认值
- 连接失败时会输出详细的错误提示信息

**示例：**
```bash
# 基本使用（使用配置文件中的默认值）
if ! check_ssh_connection "10.3.66.18"; then
    log_error "无法连接到节点 10.3.66.18"
    exit 1
fi

# 使用自定义参数
if ! check_ssh_connection "10.3.66.18" "root" 22 "/path/to/key" 30; then
    log_error "无法连接到节点 10.3.66.18"
    exit 1
fi
```

---

## 四、批量执行函数（命令）

文件位置：`scripts/lib/exec.sh`

### 4.1 exec_on_control_plane()

**功能：** 在所有控制节点执行命令

**参数：**
- `$1` - 要执行的命令

**返回值：**
- `0` - 所有节点执行成功
- 非 0 - 至少一个节点执行失败

**示例：**
```bash
# 在所有控制节点启动 containerd
exec_on_control_plane "systemctl enable --now containerd"

# 在所有控制节点配置主机名
exec_on_control_plane "hostnamectl set-hostname test-node"

# 在所有控制节点检查服务状态
exec_on_control_plane "systemctl status containerd"
```

---

### 4.2 exec_on_workers()

**功能：** 在所有工作节点执行命令

**参数：**
- `$1` - 要执行的命令

**返回值：**
- `0` - 所有节点执行成功
- 非 0 - 至少一个节点执行失败

**示例：**
```bash
# 在所有工作节点安装依赖包
exec_on_workers "yum install -y kubeadm kubectl kubelet"

# 在所有工作节点关闭 swap
exec_on_workers "swapoff -a"

# 在所有工作节点检查内核参数
exec_on_workers "sysctl net.ipv4.ip_forward"
```

---

### 4.3 exec_on_registry()

**功能：** 在镜像仓库节点执行命令

**参数：**
- `$1` - 要执行的命令

**返回值：**
- `0` - 执行成功
- 非 0 - 执行失败

**示例：**
```bash
# 在镜像仓库节点启动 registry 服务
exec_on_registry "systemctl enable --now registry"

# 在镜像仓库节点检查服务状态
exec_on_registry "systemctl status registry"
```

---

### 4.4 exec_on_all_nodes()

**功能：** 在所有节点（控制节点 + 工作节点 + 镜像仓库）执行命令

**参数：**
- `$1` - 要执行的命令

**返回值：**
- `0` - 所有节点执行成功
- 非 0 - 至少一个节点执行失败

**示例：**
```bash
# 在所有节点关闭防火墙
exec_on_all_nodes "systemctl stop firewalld"

# 在所有节点检查网络配置
exec_on_all_nodes "ip a"

# 在所有节点重启网络服务
exec_on_all_nodes "systemctl restart NetworkManager"
```

---

## 五、批量执行函数（脚本）

文件位置：`scripts/lib/exec_script.sh`

### 5.1 exec_script_on_control_plane()

**功能：** 在所有控制节点执行脚本并传递参数

**参数：**
- `$1` - 本地脚本路径
- `$2...$N` - 传递给脚本的参数（可选，支持多个）

**返回值：**
- `0` - 所有节点执行成功
- 非 0 - 至少一个节点执行失败

**示例：**
```bash
# 执行脚本（无参数）
exec_script_on_control_plane "./scripts/steps/common_config.sh"

# 执行脚本并传递单个参数
exec_script_on_control_plane "./scripts/steps/03_containerd.sh" "registry_ip=10.3.66.20"

# 执行脚本并传递多个参数
exec_script_on_control_plane "./scripts/steps/env_config.sh" \
    "pod_subnet=10.244.0.0/16" \
    "service_subnet=10.96.0.0/16" \
    "gateway=10.3.66.1"
```

---

### 5.2 exec_script_on_workers()

**功能：** 在所有工作节点执行脚本并传递参数

**参数：**
- `$1` - 本地脚本路径
- `$2...$N` - 传递给脚本的参数（可选，支持多个）

**返回值：**
- `0` - 所有节点执行成功
- 非 0 - 至少一个节点执行失败

**示例：**
```bash
# 在所有工作节点安装 containerd
exec_script_on_workers "./scripts/steps/03_containerd.sh" \
    "registry_ip=10.3.66.20" \
    "registry_port=5000"

# 在所有工作节点配置环境
exec_script_on_workers "./scripts/steps/env_config.sh" \
    "gateway=10.3.66.1" \
    "ipv6_gateway=fd00::1"
```

---

### 5.3 exec_script_on_registry()

**功能：** 在镜像仓库节点执行脚本并传递参数

**参数：**
- `$1` - 本地脚本路径
- `$2...$N` - 传递给脚本的参数（可选，支持多个）

**返回值：**
- `0` - 执行成功
- 非 0 - 执行失败

**示例：**
```bash
# 在镜像仓库节点安装 registry
exec_script_on_registry "./scripts/steps/install_registry.sh" "10.3.66.20"

# 在镜像仓库节点配置 registry
exec_script_on_registry "./scripts/steps/configure_registry.sh" \
    "port=5000" \
    "storage=/var/lib/registry"
```

---

### 5.4 exec_script_on_all_nodes()

**功能：** 在所有节点执行脚本并传递参数

**参数：**
- `$1` - 本地脚本路径
- `$2...$N` - 传递给脚本的参数（可选，支持多个）

**返回值：**
- `0` - 所有节点执行成功
- 非 0 - 至少一个节点执行失败

**示例：**
```bash
# 在所有节点配置通用环境
exec_script_on_all_nodes "./scripts/steps/common_config.sh" \
    "gateway=10.3.66.1" \
    "ipv6_gateway=fd00::1"

# 在所有节点执行系统配置
exec_script_on_all_nodes "./scripts/steps/sys_config.sh" \
    "swap_off=true" \
    "firewall_off=true" \
    "ipv4_forward=true"
```

---

### 5.5 exec_script_on_single_node()

**功能：** 在单个节点上执行本地脚本（底层实现函数）

**参数：**
- `$1` - 节点 IP 地址
- `$2` - 本地脚本路径
- `$3...$N` - 传递给脚本的参数（可选，支持多个）

**返回值：**
- `0` - 执行成功
- 非 0 - 执行失败

**说明：**
- 这是所有批量执行函数的底层实现
- 自动将脚本传输到远程节点的 `/tmp/` 目录
- 执行失败时会保留远程脚本用于调试
- 使用配置文件中的 SSH 参数（用户、端口、密钥、超时）

**执行流程：**
1. 检查 SSH 连接是否可用
2. 生成远程脚本路径（`/tmp/scriptname.$$`）
3. 使用 SCP 将本地脚本传输到远程节点
4. 使用 SSH 在远程节点执行脚本并传递参数
5. 清理远程脚本（失败时保留）

**示例：**
```bash
# 在单个节点上执行脚本
exec_script_on_single_node "10.3.66.18" "./scripts/steps/install_containerd.sh"

# 带参数执行
exec_script_on_single_node "10.3.66.18" "./scripts/steps/install_containerd.sh" \
    "registry_ip=10.3.66.20" \
    "registry_port=5000"
```

---

### 5.6 exec_remote_script()

**功能：** 远程执行本地 shell 脚本的统一入口函数

**参数：**
- `$1` - 目标节点类型或 IP
  - `control_plane` - 所有控制节点
  - `workers` - 所有工作节点
  - `registry` - 镜像仓库节点
  - `all` - 所有节点
  - 具体 IP 地址 - 单个节点
- `$2` - 本地脚本路径
- `$3...$N` - 传递给脚本的参数（可选，支持多个）

**返回值：**
- `0` - 所有节点执行成功
- 非 0 - 至少一个节点执行失败

**说明：**
- 这是远程脚本执行的主要入口函数
- 根据目标类型自动路由到相应的执行函数
- 支持脚本文件存在性和可执行性验证
- 提供统一的错误处理和日志记录

**使用场景：**
- 安装 containerd
- 配置环境变量
- 部署应用
- 执行维护脚本

**示例：**
```bash
# 单节点执行
exec_remote_script "10.3.66.18" "./scripts/steps/install_containerd.sh"

# 带参数的单节点执行
exec_remote_script "10.3.66.18" "./scripts/steps/install_containerd.sh" \
    "registry_ip=10.3.66.20" \
    "registry_port=5000"

# 在所有控制节点执行
exec_remote_script "control_plane" "./scripts/steps/config_environment.sh" \
    "gateway=10.3.66.1" \
    "ipv6_gateway=fd00::1"

# 在所有工作节点执行
exec_remote_script "workers" "./scripts/steps/install_containerd.sh" \
    "registry_ip=10.3.66.20" \
    "registry_port=5000"

# 在镜像仓库节点执行
exec_remote_script "registry" "./scripts/steps/install_registry.sh"

# 在所有节点执行
exec_remote_script "all" "./scripts/steps/common_config.sh" \
    "swap_off=true" \
    "firewall_off=true"
```

---

## 六、回滚函数

文件位置：`scripts/lib/rollback.sh`

### 6.1 rollback_package()

**功能：** 卸载软件包

**参数：**
- `$1` - 包名

**返回值：** 无

**示例：**
```bash
# 卸载 containerd
rollback_package "containerd"

# 卸载 kubeadm
rollback_package "kubeadm"

# 卸载 kubelet
rollback_package "kubelet"
```

---

### 6.2 rollback_service()

**功能：** 停止并禁用服务

**参数：**
- `$1` - 服务名

**返回值：** 无

**示例：**
```bash
# 停止并禁用 containerd
rollback_service "containerd"

# 停止并禁用 kubelet
rollback_service "kubelet"

# 停止并禁用 registry
rollback_service "registry"
```

---

### 6.3 rollback_file()

**功能：** 回滚文件（恢复备份或删除）

**参数：**
- `$1` - 文件路径

**返回值：** 无

**示例：**
```bash
# 回滚配置文件
rollback_file "/etc/containerd/config.toml"

# 回滚系统配置
rollback_file "/etc/sysctl.conf"

# 回滚网络配置
rollback_file "/etc/sysconfig/network-scripts/ifcfg-ens192"
```

---

### 6.4 rollback_directory()

**功能：** 回滚目录（恢复备份或删除）

**参数：**
- `$1` - 目录路径

**返回值：** 无

**示例：**
```bash
# 回滚配置目录
rollback_directory "/etc/containerd"

# 回滚数据目录
rollback_directory "/var/lib/containerd"

# 回滚安装目录
rollback_directory "/opt/cni/bin"
```

---

### 6.5 backup_file()

**功能：** 备份文件

**参数：**
- `$1` - 文件路径

**返回值：** 无

**示例：**
```bash
# 备份配置文件
backup_file "/etc/containerd/config.toml"

# 备份系统配置
backup_file "/etc/sysctl.conf"

# 备份网络配置
backup_file "/etc/sysconfig/network-scripts/ifcfg-ens192"
```

---

### 6.6 backup_directory()

**功能：** 备份目录

**参数：**
- `$1` - 目录路径

**返回值：** 无

**示例：**
```bash
# 备份配置目录
backup_directory "/etc/containerd"

# 备份数据目录
backup_directory "/var/lib/containerd"

# 备份安装目录
backup_directory "/opt/cni/bin"
```

---

## 七、验证函数

文件位置：`scripts/lib/validator.sh`

### 7.1 validate_ip()

**功能：** 验证 IPv4 地址格式

**参数：**
- `$1` - IP 地址

**返回值：**
- `0` - 有效
- `1` - 无效

**示例：**
```bash
if ! validate_ip "10.3.66.18"; then
    log_error "IP 地址格式错误: 10.3.66.18"
    exit 1
fi
```

---

### 7.2 validate_ipv6()

**功能：** 验证 IPv6 地址格式

**参数：**
- `$1` - IPv6 地址

**返回值：**
- `0` - 有效
- `1` - 无效

**示例：**
```bash
if ! validate_ipv6 "fd00:42::18"; then
    log_error "IPv6 地址格式错误: fd00:42::18"
    exit 1
fi
```

---

### 7.3 validate_port()

**功能：** 验证端口号有效性

**参数：**
- `$1` - 端口号

**返回值：**
- `0` - 有效
- `1` - 无效

**示例：**
```bash
if ! validate_port "6443"; then
    log_error "端口号无效: 6443"
    exit 1
fi
```

---

### 7.4 validate_command()

**功能：** 验证命令是否存在

**参数：**
- `$1` - 命令名称

**返回值：**
- `0` - 命令存在
- `1` - 命令不存在

**示例：**
```bash
if ! validate_command "ssh"; then
    log_error "缺少必要工具: ssh"
    exit 1
fi
```

---

### 7.5 validate_file()

**功能：** 验证文件是否存在

**参数：**
- `$1` - 文件路径

**返回值：**
- `0` - 文件存在
- `1` - 文件不存在

**示例：**
```bash
if ! validate_file "/path/to/file"; then
    log_error "文件不存在: /path/to/file"
    exit 1
fi
```

---

### 7.6 validate_directory()

**功能：** 验证目录是否存在

**参数：**
- `$1` - 目录路径

**返回值：**
- `0` - 目录存在
- `1` - 目录不存在

**示例：**
```bash
if ! validate_directory "/path/to/dir"; then
    log_error "目录不存在: /path/to/dir"
    exit 1
fi
```

---

### 7.7 validate_ssh()

**功能：** 验证 SSH 连接

**参数：**
- `$1` - 节点配置（JSON 格式）

**返回值：**
- `0` - 连接成功
- `1` - 连接失败

**示例：**
```bash
# 从配置中获取节点信息
node=$(config_get '.control_plane[0]')

if ! validate_ssh "$node"; then
    log_error "无法连接到节点"
    exit 1
fi
```

---

## 附录

### A. 全局变量

| 变量名 | 类型 | 说明 |
|--------|------|------|
| `CONFIG_FILE` | string | 配置文件路径 |
| `LOG_FILE` | string | 日志文件路径（默认：/tmp/kubefoundry_install.log） |
| `SCRIPT_DIR` | string | 脚本目录路径 |

### B. 退出码

| 退出码 | 含义 |
|--------|------|
| `0` | 成功 |
| `1` | 一般错误 |
| `2` | 配置错误 |
| `3` | SSH 连接错误 |

### C. 配置文件路径

| 配置项 | YAML 路径 |
|--------|-----------|
| 集群名称 | `.cluster.name` |
| K8S 版本 | `.cluster.k8s_version` |
| Pod 网段 | `.cluster.pod_subnet` |
| Service 网段 | `.cluster.service_subnet` |
| 控制节点 | `.control_plane` |
| 工作节点 | `.workers` |
| 镜像仓库 | `.registry` |
| 网络配置 | `.network` |
| SSH 配置 | `.ssh` |
| 路径配置 | `.paths` |

### D. 节点分组

| 分组 | YAML 路径 | 说明 |
|------|-----------|------|
| 控制节点 | `.control_plane` | K8S 控制平面节点 |
| 工作节点 | `.workers` | K8S 工作节点 |
| 镜像仓库 | `.registry` | 镜像仓库节点 |
| 所有节点 | `.control_plane` + `.workers` + `.registry` | 所有 K8S 节点 |

---

## 使用示例

### 示例 1：在所有控制节点执行命令

```bash
#!/bin/bash

source "./scripts/lib/logger.sh"
source "./scripts/lib/exec.sh"

# 在所有控制节点启动 containerd
exec_on_control_plane "systemctl enable --now containerd"

if [ $? -eq 0 ]; then
    log_success "containerd 在所有控制节点启动成功"
else
    log_error "containerd 启动失败"
    exit 1
fi
```

### 示例 2：在所有工作节点执行脚本并传递参数

```bash
#!/bin/bash

source "./scripts/lib/logger.sh"
source "./scripts/lib/exec_script.sh"

# 在所有工作节点安装 containerd
exec_script_on_workers "./scripts/steps/03_containerd.sh" \
    "registry_ip=10.3.66.20" \
    "registry_port=5000"

if [ $? -eq 0 ]; then
    log_success "containerd 在所有工作节点安装成功"
else
    log_error "containerd 安装失败"
    exit 1
fi
```

### 示例 3：在镜像仓库节点安装 registry

```bash
#!/bin/bash

source "./scripts/lib/logger.sh"
source "./scripts/lib/exec_script.sh"

# 在镜像仓库节点执行安装脚本
exec_script_on_registry "./scripts/steps/install_registry.sh" "10.3.66.20"

if [ $? -eq 0 ]; then
    log_success "registry 安装成功"
else
    log_error "registry 安装失败"
    exit 1
fi
```

### 示例 4：在所有节点配置环境

```bash
#!/bin/bash

source "./scripts/lib/logger.sh"
source "./scripts/lib/exec_script.sh"

# 在所有节点执行环境配置脚本
exec_script_on_all_nodes "./scripts/steps/env_config.sh" \
    "pod_subnet=10.244.0.0/16" \
    "service_subnet=10.96.0.0/16" \
    "gateway=10.3.66.1" \
    "ipv6_gateway=fd00::1"

if [ $? -eq 0 ]; then
    log_success "环境配置在所有节点完成"
else
    log_error "环境配置失败"
    exit 1
fi
```

---

### 示例 5：使用统一入口函数 exec_remote_script()

```bash
#!/bin/bash

source "./scripts/lib/logger.sh"
source "./scripts/lib/config.sh"
source "./scripts/lib/ssh.sh"
source "./scripts/lib/exec_script.sh"

# 在单个节点安装 containerd
log_info "开始在单个节点安装 containerd..."
exec_remote_script "10.3.66.18" "./scripts/steps/install_containerd.sh" \
    "registry_ip=10.3.66.20" \
    "registry_port=5000"

# 在所有工作节点安装 containerd
log_info "开始在所有工作节点安装 containerd..."
if exec_remote_script "workers" "./scripts/steps/install_containerd.sh" \
    "registry_ip=10.3.66.20" \
    "registry_port=5000"; then
    log_success "containerd 在所有工作节点安装成功"
else
    log_error "containerd 安装失败"
    exit 1
fi

# 在镜像仓库节点安装 registry
log_info "开始在镜像仓库节点安装 registry..."
exec_remote_script "registry" "./scripts/steps/install_registry.sh"

# 在所有节点配置通用环境
log_info "开始在所有节点配置通用环境..."
exec_remote_script "all" "./scripts/steps/common_config.sh" \
    "swap_off=true" \
    "firewall_off=true"
```

---

**更新日期：** 2026-03-22
**版本：** 1.0.0
