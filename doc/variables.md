# KubeFoundry 变量提取文档

本文档从 `doc/cmdlist.md` 中提取所有配置变量，用于生成配置文件 `config/cluster.yaml`。

---

## 一、集群基本信息变量

| 变量名 | 类型 | 默认值 | 说明 | 来源 |
|--------|------|--------|------|------|
| `cluster.name` | string | "k8s-cluster" | 集群名称 | 推导 |
| `cluster.k8s_version` | string | "1.29.0" | K8S 版本 | cmdlist:99 |
| `cluster.pod_subnet` | string | "10.244.0.0/16" | Pod 网络网段 | cmdlist:100 |
| `cluster.service_subnet` | string | "10.96.0.0/16" | Service 网络网段 | cmdlist:101 |
| `cluster.control_node_count` | int | 3 | 控制节点数量 | 推导 |
| `cluster.worker_node_count` | int | 6 | 工作节点数量 | 推导 |

---

## 二、节点配置变量

### 2.1 控制节点（Control Plane）

从 `doc/cmdlist.md` 第 63-65 行提取：

| 节点索引 | 变量路径 | 主机名 | IP 地址 | IPv6 地址 | 角色 |
|---------|----------|--------|---------|-----------|------|
| 0 | `control_plane[0]` | k8sc1 | 10.3.66.18 | fd00:42::18 | master（主）、repo源服务 |
| 1 | `control_plane[1]` | k8sc2 | 10.3.66.19 | fd00:42::19 | master（从） |
| 2 | `control_plane[2]` | k8sc3 | 10.3.66.20 | fd00:42::20 | master（从） |

**YAML 结构示例：**
```yaml
control_plane:
  - hostname: "k8sc1"
    ip: "10.3.66.18"
    ipv6: "fd00:42::18"
    role: "master"
  - hostname: "k8sc2"
    ip: "10.3.66.19"
    ipv6: "fd00:42::19"
    role: "master"
  - hostname: "k8sc3"
    ip: "10.3.66.20"
    ipv6: "fd00:42::20"
    role: "master"
```

### 2.2 工作节点（Workers）

从 `doc/cmdlist.md` 第 66-71 行提取：

| 节点索引 | 变量路径 | 主机名 | IP 地址 | IPv6 地址 | 角色 |
|---------|----------|--------|---------|-----------|------|
| 0 | `workers[0]` | k8sw1 | 10.3.66.21 | fd00:42::21 | 工作节点、nfs服务器 |
| 1 | `workers[1]` | k8sw2 | 10.3.66.22 | fd00:42::22 | 工作节点 |
| 2 | `workers[2]` | k8sw3 | 10.3.66.23 | fd00:42::23 | 工作节点 |
| 3 | `workers[3]` | k8sw4 | 10.3.66.24 | fd00:42::24 | 工作节点 |
| 4 | `workers[4]` | k8sw5 | 10.3.66.25 | fd00:42::25 | 工作节点 |
| 5 | `workers[5]` | k8sw6 | 10.3.66.26 | fd00:42::26 | 工作节点 |

**YAML 结构示例：**
```yaml
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
```

### 2.3 镜像仓库（Registry）

从 `doc/cmdlist.md` 第 72 行提取：

| 变量路径 | 主机名 | IP 地址 | IPv6 地址 | 端口 |
|----------|--------|---------|-----------|------|
| `registry` | registry | 10.3.66.20 | fd00:42::20 | 5000 |

**YAML 结构示例：**
```yaml
registry:
  hostname: "registry"
  ip: "10.3.66.20"
  ipv6: "fd00:42::20"
  port: 5000
```

---

## 三、网络配置变量

从配置文件和命令中推导的网络参数：

| 变量名 | 类型 | 默认值 | 说明 | 推导方式 |
|--------|------|--------|------|---------|
| `network.gateway` | string | "10.3.66.1" | IPv4 网关 | 根据节点 IP 网段推导 |
| `network.ipv6_gateway` | string | "fd00::1" | IPv6 网关 | 固定值 |
| `network.pod_cidr` | string | "10.244.0.0/16" | Pod 网络 | 与 cluster.pod_subnet 同步 |
| `network.service_cidr` | string | "10.96.0.0/16" | Service 网络 | 与 cluster.service_subnet 同步 |

**YAML 结构示例：**
```yaml
network:
  gateway: "10.3.66.1"
  ipv6_gateway: "fd00::1"
```

API Server 端口固定为 `6443`，不属于配置变量。

---

## 四、SSH 配置变量

从操作方式推导的 SSH 参数：

| 变量名 | 类型 | 默认值 | 说明 | 推导方式 |
|--------|------|--------|------|---------|
| `ssh.user` | string | "root" | SSH 用户名 | 操作默认 root |
| `ssh.port` | int | 22 | SSH 端口 | 默认值 |
| `ssh.key_path` | string | "~/.ssh/id_rsa" | SSH 私钥路径 | 默认位置 |

**YAML 结构示例：**
```yaml
ssh:
  user: "root"
  port: 22
  key_path: "~/.ssh/id_rsa"
```

---

## 五、路径配置变量

从 `doc/cmdlist.md` 各步骤中提取的路径：

| 变量名 | 类型 | 默认值 | 说明 | 来源 |
|--------|------|--------|------|------|
| `paths.k8s_install` | string | "/data/k8s_install" | K8S 安装包路径 | cmdlist:738 |
| `paths.kubelet_root` | string | "/data/kubelet_root" | kubelet 数据目录 | cmdlist:738 |
| `paths.containerd_tmp` | string | "/tmp/k8s/02.container_runtime" | Containerd 临时路径 | cmdlist:641 |
| `paths.repo_source` | string | "/path/to/repo.tar.gz" | YUM 源压缩包 | cmdlist:287 |
| `paths.kubeadm_100y` | string | "/path/to/kubeadm-100y" | 100年证书 kubeadm | cmdlist:377 |
| `paths.flannel_config` | string | "/data/k8s_install/03.setup_file/kube-flannel.yml" | Flannel 配置 | cmdlist:881 |
| `paths.cluster_config` | string | "/data/k8s_install/03.setup_file/cluster.yaml" | K8S 集群配置 | cmdlist:729 |

**YAML 结构示例：**
```yaml
paths:
  k8s_install: "/data/k8s_install"
  kubelet_root: "/data/kubelet_root"
  repo_source: "/path/to/repo.tar.gz"
  kubeadm_100y: "/path/to/kubeadm-100y"
  flannel_config: "/data/k8s_install/03.setup_file/kube-flannel.yml"
```

---

## 十一、变量验证规则

### 11.1 IP 地址验证

- IPv4 格式：`xxx.xxx.xxx.xxx`
- IPv6 格式：`xxxx:xxxx::xxxx`
- 网段一致性：所有节点应在同一网段

### 11.2 端口验证

- 端口范围：1-65535
- 常用端口：
  - SSH: 22
  - API Server: 6443
  - Registry: 5000

### 11.3 路径验证

- 必须以 `/` 开头
- 路径不能包含特殊字符（除 `/_-.`）
- 路径权限检查

### 11.4 网段验证

- Pod 网段：不能与 Service 网段重叠
- Service 网段：不能与 Pod 网段重叠
- 网段掩码：必须是有效的 CIDR 表示

---

## 十二、变量使用示例

### 12.1 在脚本中使用

```bash
#!/bin/bash

# 加载配置文件
source "$SCRIPT_DIR/lib/config.sh"

# 读取集群信息
k8s_version=$(config_get '.cluster.k8s_version')
pod_subnet=$(config_get '.cluster.pod_subnet')

# 读取节点信息
control_plane_count=$(config_get '.control_plane | length')
worker_count=$(config_get '.workers | length')

# 读取第一个控制节点
first_control_plane=$(config_get '.control_plane[0]')
first_control_ip=$(echo "$first_control_plane" | jq -r '.ip')

# 读取网络配置
gateway=$(config_get '.network.gateway')

# 输出配置
echo "K8S 版本: $k8s_version"
echo "Pod 网段: $pod_subnet"
echo "控制节点数量: $control_plane_count"
echo "工作节点数量: $worker_count"
echo "网关: $gateway"
```

### 12.2 在模板文件中使用

```bash
#!/bin/bash

# 生成 K8S 集群配置文件
cat << EOF > /tmp/cluster.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: $(config_get '.control_plane[0].ip')
  bindPort: 6443
networking:
  podSubnet: $(config_get '.cluster.pod_subnet')
  serviceSubnet: $(config_get '.cluster.service_subnet')
EOF
```

---

## 十三、变量优先级

### 13.1 配置来源优先级

1. **命令行参数**（最高优先级）
2. **环境变量**
3. **配置文件**（cluster.yaml）
4. **默认值**（最低优先级）

### 13.2 变量覆盖示例

```bash
# 通过命令行参数覆盖
./scripts/main.sh --k8s-version "1.30.0" --pod-subnet "10.245.0.0/16"

# 通过环境变量覆盖
export K8S_VERSION="1.30.0"
export POD_SUBNET="10.245.0.0/16"
./scripts/main.sh
```

---

## 十四、变量变更记录

| 版本 | 变更内容 | 日期 |
|------|---------|------|
| 1.0.0 | 初始版本，提取基本变量 | 2026-03-22 |

---

**更新日期：** 2026-03-22
**文档版本：** 1.0.0
