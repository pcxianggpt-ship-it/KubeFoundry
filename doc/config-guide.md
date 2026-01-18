# K8S自动部署工具配置参数说明

本文档详细说明了 `config/config.yaml` 中所有配置参数的含义和用途。

---

## 目录

1. [服务器规划配置](#1-服务器规划配置)
2. [K8S版本和架构配置](#2-k8s版本和架构配置)
3. [YUM源配置](#3-yum源配置)
4. [网络配置](#4-网络配置)
5. [Containerd配置](#5-containerd配置)
6. [镜像仓库配置](#6-镜像仓库配置)
7. [NFS存储配置](#7-nfs存储配置)
8. [数据路径配置](#8-数据路径配置)
9. [CNI插件配置](#9-cni插件配置)
10. [Kubemate配置](#10-kubemate配置)
11. [监控和日志组件配置](#11-监控和日志组件配置)
12. [Redis配置](#12-redis配置)
13. [证书配置](#13-证书配置)
14. [系统配置](#14-系统配置)
15. [普通用户配置](#15-普通用户配置)
16. [F5高可用配置](#16-f5高可用配置)
17. [定时任务配置](#17-定时任务配置)
18. [部署选项](#18-部署选项)
19. [Helm配置](#19-helm配置)
20. [日志配置](#20-日志配置)

---

## 1. 服务器规划配置

### server.nodes.control_plane
**控制平面节点配置**

- **hostname**: 节点主机名（如 k8sc1）
- **ip**: IPv4地址
- **ipv6**: IPv6地址
- **role**: 节点角色说明

**示例：**
```yaml
control_plane:
  - hostname: k8sc1
    ip: 10.3.66.18
    ipv6: fd00:42::18
    role: "控制平面（主）、repo源服务"
```

### server.nodes.workers
**工作节点配置**

- **hostname**: 节点主机名（如 k8sw1）
- **ip**: IPv4地址
- **ipv6**: IPv6地址
- **role**: 节点角色说明

**示例：**
```yaml
workers:
  - hostname: k8sw1
    ip: 10.3.66.21
    ipv6: fd00:42::21
    role: "工作节点、nfs服务器"
```

### server.nodes.registry
**镜像仓库节点配置**

- **hostname**: 主机名
- **ip**: IPv4地址
- **ipv6**: IPv6地址
- **role**: 角色说明

### server.network_interface
**网卡名称**

- **默认值**: `ens192`
- **说明**: 系统主网卡名称，用于网络配置
- **获取方式**: `ip addr` 或 `ls /etc/sysconfig/network-scripts/`

---

## 2. K8S版本和架构配置

### k8s.version
**Kubernetes版本号**

- **默认值**: `"1.28.0"`
- **说明**: 要安装的Kubernetes版本
- **格式**: 字符串类型

### k8s.arch_type
**系统架构类型**

- **默认值**: `"amd64"`
- **可选值**: `amd64`, `arm64`
- **说明**: 根据服务器CPU架构选择
- **获取方式**: `uname -m`

---

## 3. YUM源配置

### yum.repo_source_file
**YUM源压缩包文件名**

- **默认值**: `""`
- **说明**: YUM源压缩包的文件名（包含路径）
- **示例**: `/path/to/k8s-repo.tar.gz`

### yum.local_repo_path
**本地YUM源路径**

- **默认值**: `"/var/www/html/repo"`
- **说明**: YUM源在控制节点上的解压路径

### yum.http_repo_url
**HTTP YUM源地址**

- **默认值**: `"http://k8sc1/repo"`
- **说明**: 其他节点通过HTTP访问YUM源的URL

---

## 4. 网络配置

### network.dns.gateway_dns
**网关DNS地址**

- **默认值**: `""`
- **说明**: 使用网关地址作为DNS
- **获取方式**: 查看 `/etc/sysconfig/network-scripts/ifcfg-ens192` 中的 GATEWAY

### network.dns.public_dns
**公网DNS地址**

- **默认值**: `"8.8.8.8"`
- **说明**: 备用DNS服务器地址

### network.ipv6
**IPv6网络配置**

- **enabled**: 是否启用IPv6（true/false）
- **gateway**: IPv6网关地址
- **说明**: 如需配置IPv6双栈网络，设置为 `enabled: true`

### network.cluster
**K8S集群网络配置**

- **pod_subnet**: Pod网络网段（默认: `"10.244.0.0/16"`）
- **service_subnet**: Service网络网段（默认: `"10.96.0.0/12"`）
- **control_plane_endpoint**: 控制平面端点地址

---

## 5. Containerd配置

### containerd.version
**Containerd版本号**

- **默认值**: `"1.7.18"`
- **说明**: Containerd容器运行时版本

### containerd.runc_version
**runc版本号**

- **默认值**: `"v1.3.3"`
- **说明**: OCI运行时runc的版本

### containerd.cni_plugins_version
**CNI插件版本**

- **默认值**: `"v1.8.0"`
- **说明**: Container网络插件版本

### containerd.buildkit_version
**Buildkit版本**

- **默认值**: `"v0.25.2"`
- **说明**: 镜像构建工具版本

### containerd.nerdctl_version
**Nerdctl版本**

- **默认值**: `"2.2.0"`
- **说明**: Docker兼容CLI工具版本

---

## 6. 镜像仓库配置

### registry.server
**镜像仓库地址**

- **默认值**: `"registry:5000"`
- **说明**: 使用域名和端口表示的镜像仓库地址

### registry.server_ip
**镜像仓库IP地址**

- **默认值**: `"10.3.66.20:5000"`
- **说明**: 使用IP和端口表示的镜像仓库地址

### registry.insecure
**是否使用HTTP协议**

- **默认值**: `true`
- **说明**: 生产环境建议使用HTTPS并设置为false

### registry.auth
**镜像仓库认证信息**

- **enabled**: 是否启用认证
- **username**: 用户名
- **password**: 密码

---

## 7. NFS存储配置

### nfs.server
**NFS服务器地址**

- **默认值**: `"10.3.5.221"`
- **说明**: NFS服务器的IP地址

### nfs.path
**NFS导出路径**

- **默认值**: `"/kvmdata/nfsdata/xdnfs"`
- **说明**: NFS服务器上的导出路径

### nfs.mount_point
**本地挂载点**

- **默认值**: `"/data/nas_root"`
- **说明**: NFS在本地节点的挂载点

### nfs.auto_mount
**是否开机自动挂载**

- **默认值**: `true`
- **说明**: 是否将NFS添加到/etc/fstab实现开机挂载

### nfs.provisioner
**NFS Provisioner配置**

- **enabled**: 是否启用NFS Provisioner
- **storage_class_name**: StorageClass名称

---

## 8. 数据路径配置

### paths.k8s_install
**K8S安装文件路径**

- **默认值**: `"/data/k8s_install"`
- **说明**: 存放K8S安装脚本和配置文件的目录

### paths.kubelet_root
**Kubelet数据根目录**

- **默认值**: `"/data/kubelet_root"`
- **说明**: Kubelet的工作数据目录

### paths.tmp_k8s
**K8S临时目录**

- **默认值**: `"/tmp/k8s"`
- **说明**: K8S安装过程中的临时文件目录**

### paths.nas_root
**NAS挂载点**

- **默认值**: `"/data/nas_root"`
- **说明**: NAS存储的挂载点

### paths.loki_root
**Loki数据目录**

- **默认值**: `"/data/loki_root"`
- **说明**: Loki日志系统的数据存储目录

### paths.redis_root
**Redis数据目录**

- **默认值**: `"/data/redis_root"`
- **说明**: Redis集群的数据存储目录**

### paths.backup_root
**备份根目录**

- **默认值**: `"/data/backup"`
- **说明**: 各种备份文件的存储目录**

### paths.crontab_root
**定时任务目录**

- **默认值**: `"/data/crontab_task"`
- **说明**: 定时任务相关文件的存储目录**

---

## 9. CNI插件配置

### cni.type
**CNI插件类型**

- **默认值**: `"flannel"`
- **可选值**: `flannel`, `calico`, `canal`, `weave-net`
- **说明**: 选择的容器网络接口插件

### cni.flannel_config
**Flannel配置文件**

- **默认值**: `"kube-flannel.yml"`
- **说明**: Flannel的部署配置文件名

---

## 10. Kubemate配置

### kubemate.namespace
**Kubemate命名空间**

- **默认值**: `"kubemate-system"`
- **说明**: Kubemate组件所在的K8S命名空间**

### kubemate.web_port
**Web管理界面端口**

- **默认值**: `30088`
- **说明**: Kubemate Web界面对外暴露的端口号**

### kubemate.default_user
**默认用户名**

- **默认值**: `"admin"`
- **说明**: Kubemate Web界面的默认登录用户名**

### kubemate.default_password
**默认密码**

- **默认值**: `"000000als"`
- **说明**: Kubemate Web界面的默认登录密码**

### kubemate.server_ip
**Kubemate服务IP**

- **默认值**: `"10.3.66.18"`
- **说明**: Kubemate服务所在的服务器IP**

---

## 11. 监控和日志组件配置

### monitoring.elasticsearch
**Elasticsearch配置**

- **enabled**: 是否启用（默认: true）
- **namespace**: 命名空间
- **deployment_name**: 部署名称

### monitoring.skywalking
**Skywalking配置**

- **enabled**: 是否启用（默认: true）
- **namespace**: 命名空间
- **elasticsearch_password**: ES密码（部署后自动获取）

### monitoring.loki
**Loki配置**

- **enabled**: 是否启用（默认: true）
- **namespace**: 命名空间
- **storage_type**: 存储类型（local或nfs）

### monitoring.prometheus
**Prometheus配置**

- **enabled**: 是否启用（默认: true）
- **namespace**: 命名空间

### monitoring.traefik
**Traefik配置**

- **enabled**: 是否启用（默认: true）
- **namespace**: 命名空间
- **mesh_enabled**: 是否启用Traefik Mesh

---

## 12. Redis配置

### redis.sentinel
**Redis哨兵模式配置**

- **enabled**: 是否启用（默认: false）
- **namespace**: 命名空间

### redis.cluster
**Redis集群模式配置**

- **enabled**: 是否启用（默认: true）
- **namespace**: 命名空间
- **password**: Redis密码
- **node_count**: 集群节点数量
- **leader_replicas**: Leader副本数
- **follower_replicas**: Follower副本数

### redis.monitoring
**Redis监控配置**

- **enabled**: 是否启用监控
- **exporter_port**: Exporter端口

---

## 13. 证书配置

### certificates.cluster_signing_duration
**集群证书有效期**

- **默认值**: `"867240h0m0s"`（100年）
- **说明**: K8S签发证书的有效期**
- **格式**: 小时数h分钟数m秒数s

---

## 14. 系统配置

### system.max_open_files
**最大打开文件数**

- **默认值**: `65535`
- **说明**: 系统允许的最大文件描述符数量**

### system.swap_enabled
**是否启用Swap**

- **默认值**: `false`
- **说明**: K8S要求关闭Swap**

### system.firewall_enabled
**是否启用防火墙**

- **默认值**: `false`
- **说明**: 部署期间建议关闭防火墙**

### system.ssh
**SSH配置**

- **passwordless_login**: 是否配置免密登录
- **user**: SSH用户名

---

## 15. 普通用户配置

### user.name
**普通用户名**

- **默认值**: `"appusr"`
- **说明**: 需要配置kubectl权限的普通用户**

### user.kubectl_access
**是否配置kubectl权限**

- **默认值**: `true`
- **说明**: 是否为普通用户配置kubectl访问权限**

---

## 16. F5高可用配置

### f5.enabled
**是否启用F5高可用**

- **默认值**: `false`
- **说明**: 是否配置F5负载均衡器**

### f5.primary_ip
**主中心F5 IP**

- **默认值**: `""`
- **说明**: 主数据中心F5设备的IP地址**

### f5.secondary_ip
**副中心F5 IP**

- **默认值**: `""`
- **说明**: 副数据中心F5设备的IP地址**

---

## 17. 定时任务配置

### cron_jobs.etcd_backup
**ETCD备份任务**

- **enabled**: 是否启用（默认: true）
- **schedule**: 执行时间（Cron表达式）
- **center**: 数据中心（primary或secondary）

### cron_jobs.traefik_cleanup
**Traefik清理任务**

- **enabled**: 是否启用（默认: true）
- **schedule**: 执行时间（Cron表达式）

### cron_jobs.log_cleanup
**应用日志清理任务**

- **enabled**: 是否启用（默认: true）
- **schedule**: 执行时间（Cron表达式）
- **retention_days**: 日志保留天数

---

## 18. 部署选项

### deployment.ha_control_plane
**是否部署高可用控制平面**

- **默认值**: `true`
- **说明**: 是否部署多个控制节点实现高可用**

### deployment.dual_stack
**是否部署双栈网络**

- **默认值**: `true`
- **说明**: 是否同时支持IPv4和IPv6**

### deployment.mode
**部署模式**

- **默认值**: `"all"`
- **可选值**:
  - `all`: 部署所有节点
  - `control-plane`: 仅部署控制节点
  - `worker`: 仅部署工作节点

### deployment.skip_steps
**跳过的部署步骤**

- **默认值**: `[]`
- **说明**: 跳过的部署步骤列表**

### deployment.backup_before_execution
**执行前是否备份**

- **默认值**: `true`
- **说明**: 执行部署前是否备份现有配置**

### deployment.verbose_logging
**是否启用详细日志**

- **默认值**: `true`
- **说明**: 是否输出详细的部署日志**

---

## 19. Helm配置

### helm.version
**Helm版本**

- **默认值**: `"v3.0.0"`
- **说明**: Helm包管理器的版本**

### helm.binary_path
**Helm可执行文件路径**

- **默认值**: `"/usr/local/bin/helm"`
- **说明**: Helm二进制文件的位置**

### helm.repositories
**Helm仓库配置**

- **默认值**: `[]`
- **说明**: Helm仓库列表**

---

## 20. 日志配置

### logging.level
**日志级别**

- **默认值**: `"info"`
- **可选值**: `debug`, `info`, `warn`, `error`
- **说明**: 控制日志输出的详细程度**

### logging.file
**日志文件路径**

- **默认值**: `"/var/log/k8s-deployment.log"`
- **说明**: 日志文件的存储路径**

### logging.console
**是否输出到控制台**

- **默认值**: `true`
- **说明**: 是否同时在控制台输出日志**

---

## 配置文件使用示例

### 最小化配置（仅修改必需参数）

```yaml
server:
  network_interface: ens192

registry:
  server: "registry:5000"
  server_ip: "10.3.66.20:5000"

nfs:
  server: "10.3.5.221"
  path: "/kvmdata/nfsdata/xdnfs"
```

### 完整配置

所有参数都按照实际环境进行配置。

---

## 注意事项

1. **IP地址配置**: 确保所有IP地址与实际环境一致
2. **主机名配置**: 主机名必须在所有节点的 `/etc/hosts` 中配置
3. **密码安全**: 生产环境务必修改默认密码
4. **网络配置**: IPv6配置根据实际需求决定是否启用
5. **存储配置**: 确保NFS服务器路径可访问
6. **证书配置**: 100年证书用于测试环境，生产环境建议根据安全策略调整

---

## 配置验证

在执行部署前，建议进行配置验证：

```bash
# 检查YAML语法
python -c "import yaml; yaml.safe_load(open('config/config.yaml'))"

# 或使用yamllint
yamllint config/config.yaml
```
