# K8S自动部署工具 - 配置参数总结

本文档总结了从 `cmdlist.md` 中提炼出的所有可配置参数。

---

## 配置文件结构

配置文件 `config/config.yaml` 分为20个主要配置模块：

```
config/config.yaml
├── 1. 服务器规划配置 (server)
├── 2. K8S版本和架构配置 (k8s)
├── 3. YUM源配置 (yum)
├── 4. 网络配置 (network)
├── 5. Containerd配置 (containerd)
├── 6. 镜像仓库配置 (registry)
├── 7. NFS存储配置 (nfs)
├── 8. 数据路径配置 (paths)
├── 9. CNI插件配置 (cni)
├── 10. Kubemate配置 (kubemate)
├── 11. 监控和日志组件配置 (monitoring)
├── 12. Redis配置 (redis)
├── 13. 证书配置 (certificates)
├── 14. 系统配置 (system)
├── 15. 普通用户配置 (user)
├── 16. F5高可用配置 (f5)
├── 17. 定时任务配置 (cron_jobs)
├── 18. 部署选项 (deployment)
├── 19. Helm配置 (helm)
└── 20. 日志配置 (logging)
```

---

## 参数提炼来源

### 1. 从服务器规划提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| 控制节点列表 | server.nodes.control_plane | - | 包含hostname, ip, ipv6, role |
| 工作节点列表 | server.nodes.workers | - | 包含hostname, ip, ipv6, role |
| 镜像仓库节点 | server.nodes.registry | - | 包含hostname, ip, ipv6, role |
| 网卡名称 | server.network_interface | ens192 | 主网卡名称 |

**来源**: cmdlist.md 第3-18行

### 2. 从YUM源配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| YUM源文件 | yum.repo_source_file | "" | YUM源压缩包路径 |
| 本地YUM源路径 | yum.local_repo_path | /var/www/html/repo | 本地YUM源目录 |
| HTTP YUM源URL | yum.http_repo_url | http://k8sc1/repo | HTTP访问地址 |

**来源**: cmdlist.md 第24-75行

### 3. 从K8S版本和架构提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| K8S版本 | k8s.version | 1.28.0 | Kubernetes版本号 |
| 架构类型 | k8s.arch_type | amd64 | CPU架构 |

**来源**: cmdlist.md 第102-114行

### 4. 从网络配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| 网关DNS | network.dns.gateway_dns | "" | 网关地址 |
| 公网DNS | network.dns.public_dns | 8.8.8.8 | 公网DNS服务器 |
| IPv6启用 | network.ipv6.enabled | true | 是否启用IPv6 |
| IPv6网关 | network.ipv6.gateway | fd00::1 | IPv6网关地址 |
| Pod网段 | network.cluster.pod_subnet | 10.244.0.0/16 | Pod网络CIDR |
| Service网段 | network.cluster.service_subnet | 10.96.0.0/12 | Service网络CIDR |
| 控制平面端点 | network.cluster.control_plane_endpoint | - | API Server地址 |

**来源**: cmdlist.md 第130-183行

### 5. 从Containerd配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| Containerd版本 | containerd.version | 1.7.18 | Containerd版本号 |
| runc版本 | containerd.runc_version | v1.3.3 | OCI运行时版本 |
| CNI插件版本 | containerd.cni_plugins_version | v1.8.0 | CNI插件版本 |
| Buildkit版本 | containerd.buildkit_version | v0.25.2 | 镜像构建工具版本 |
| Nerdctl版本 | containerd.nerdctl_version | 2.2.0 | CLI工具版本 |

**来源**: cmdlist.md 第380-439行

### 6. 从镜像仓库配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| 镜像仓库地址 | registry.server | registry:5000 | 镜像仓库域名:端口 |
| 镜像仓库IP | registry.server_ip | 10.3.66.20:5000 | 镜像仓库IP:端口 |
| HTTP模式 | registry.insecure | true | 是否使用HTTP |
| 认证启用 | registry.auth.enabled | false | 是否启用认证 |
| 用户名 | registry.auth.username | "" | 镜像仓库用户名 |
| 密码 | registry.auth.password | "" | 镜像仓库密码 |

**来源**: cmdlist.md 第418-434行

### 7. 从NFS存储配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| NFS服务器 | nfs.server | 10.3.5.221 | NFS服务器IP |
| NFS路径 | nfs.path | /kvmdata/nfsdata/xdnfs | NFS导出路径 |
| 挂载点 | nfs.mount_point | /data/nas_root | 本地挂载点 |
| 自动挂载 | nfs.auto_mount | true | 开机自动挂载 |
| Provisioner启用 | nfs.provisioner.enabled | true | 启用NFS Provisioner |
| StorageClass名称 | nfs.provisioner.storage_class_name | managed-nfs-storage | 存储类名称 |

**来源**: cmdlist.md 第756-843行

### 8. 从数据路径配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| K8S安装路径 | paths.k8s_install | /data/k8s_install | 安装脚本目录 |
| Kubelet根目录 | paths.kubelet_root | /data/kubelet_root | Kubelet数据目录 |
| K8S临时目录 | paths.tmp_k8s | /tmp/k8s | 临时文件目录 |
| NAS根目录 | paths.nas_root | /data/nas_root | NAS挂载点 |
| Loki根目录 | paths.loki_root | /data/loki_root | Loki数据目录 |
| Redis根目录 | paths.redis_root | /data/redis_root | Redis数据目录 |
| 备份根目录 | paths.backup_root | /data/backup | 备份文件目录 |
| 定时任务目录 | paths.crontab_root | /data/crontab_task | 定时任务目录 |

**来源**: cmdlist.md 多处路径配置

### 9. 从CNI插件配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| CNI类型 | cni.type | flannel | 网络插件类型 |
| Flannel配置 | cni.flannel_config | kube-flannel.yml | Flannel配置文件 |

**来源**: cmdlist.md 第613-659行

### 10. 从Kubemate配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| 命名空间 | kubemate.namespace | kubemate-system | K8S命名空间 |
| Web端口 | kubemate.web_port | 30088 | Web界面端口 |
| 默认用户 | kubemate.default_user | admin | 登录用户名 |
| 默认密码 | kubemate.default_password | 000000als | 登录密码 |
| 服务IP | kubemate.server_ip | 10.3.66.18 | 服务所在IP |

**来源**: cmdlist.md 第662-728行

### 11. 从监控组件配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| Elasticsearch启用 | monitoring.elasticsearch.enabled | true | 启用ES |
| Skywalking启用 | monitoring.skywalking.enabled | true | 启用Skywalking |
| Loki启用 | monitoring.loki.enabled | true | 启用Loki |
| Loki存储类型 | monitoring.loki.storage_type | local | 存储类型 |
| Prometheus启用 | monitoring.prometheus.enabled | true | 启用Prometheus |
| Traefik启用 | monitoring.traefik.enabled | true | 启用Traefik |
| Traefik Mesh | monitoring.traefik.mesh_enabled | true | 启用Traefik Mesh |

**来源**: cmdlist.md 第847-981行

### 12. 从Redis配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| 哨兵模式启用 | redis.sentinel.enabled | false | 启用哨兵模式 |
| 集群模式启用 | redis.cluster.enabled | true | 启用集群模式 |
| Redis命名空间 | redis.cluster.namespace | redis-opt | K8S命名空间 |
| Redis密码 | redis.cluster.password | - | Redis访问密码 |
| 节点数量 | redis.cluster.node_count | 6 | 集群节点数 |
| Leader副本数 | redis.cluster.leader_replicas | 3 | Leader副本数 |
| Follower副本数 | redis.cluster.follower_replicas | 3 | Follower副本数 |
| 监控启用 | redis.monitoring.enabled | true | 启用监控 |
| Exporter端口 | redis.monitoring.exporter_port | 9121 | 监控端口 |

**来源**: cmdlist.md 第1198-1497行

### 13. 从证书配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| 证书有效期 | certificates.cluster_signing_duration | 867240h0m0s | 证书有效期(100年) |

**来源**: cmdlist.md 第516-542行

### 14. 从系统配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| 最大打开文件数 | system.max_open_files | 65535 | 文件描述符限制 |
| Swap启用 | system.swap_enabled | false | 是否启用Swap |
| 防火墙启用 | system.firewall_enabled | false | 是否启用防火墙 |
| SSH免密 | system.ssh.passwordless_login | true | SSH免密登录 |
| SSH用户 | system.ssh.user | root | SSH用户名 |

**来源**: cmdlist.md 第297-372行

### 15. 从用户配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| 用户名 | user.name | appusr | 普通用户名 |
| Kubectl权限 | user.kubectl_access | true | kubectl访问权限 |

**来源**: cmdlist.md 第1139-1165行

### 16. 从F5配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| F5启用 | f5.enabled | false | 启用F5高可用 |
| 主中心F5 IP | f5.primary_ip | "" | 主F5 IP |
| 副中心F5 IP | f5.secondary_ip | "" | 副F5 IP |

**来源**: cmdlist.md 第1169-1194行

### 17. 从定时任务配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| ETCD备份启用 | cron_jobs.etcd_backup.enabled | true | 启用ETCD备份 |
| ETCD备份时间 | cron_jobs.etcd_backup.schedule | 10 2 * * * | 备份时间 |
| 数据中心 | cron_jobs.etcd_backup.center | primary | 主/副中心 |
| Traefik清理启用 | cron_jobs.traefik_cleanup.enabled | true | 启用Traefik清理 |
| Traefik清理时间 | cron_jobs.traefik_cleanup.schedule | 0 2 * * * | 清理时间 |
| 日志清理启用 | cron_jobs.log_cleanup.enabled | true | 启用日志清理 |
| 日志清理时间 | cron_jobs.log_cleanup.schedule | 0 2 * * * | 清理时间 |
| 保留天数 | cron_jobs.log_cleanup.retention_days | 7 | 日志保留天数 |

**来源**: cmdlist.md 第1501-1607行

### 18. 从部署选项提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| HA控制平面 | deployment.ha_control_plane | true | 高可用控制平面 |
| 双栈网络 | deployment.dual_stack | true | IPv4+IPv6 |
| 部署模式 | deployment.mode | all | 部署范围 |
| 跳过步骤 | deployment.skip_steps | [] | 跳过的步骤 |
| 执行前备份 | deployment.backup_before_execution | true | 执行前备份 |
| 详细日志 | deployment.verbose_logging | true | 详细日志输出 |

**来源**: 全局部署策略

### 19. 从Helm配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| Helm版本 | helm.version | v3.0.0 | Helm版本 |
| Helm路径 | helm.binary_path | /usr/local/bin/helm | Helm二进制路径 |
| Helm仓库 | helm.repositories | [] | Helm仓库列表 |

**来源**: cmdlist.md 第783-788行

### 20. 从日志配置提炼的参数

| 参数名称 | 配置路径 | 默认值 | 说明 |
|---------|---------|--------|------|
| 日志级别 | logging.level | info | 日志详细程度 |
| 日志文件 | logging.file | /var/log/k8s-deployment.log | 日志文件路径 |
| 控制台输出 | logging.console | true | 控制台输出 |

**来源**: 全局日志配置

---

## 参数分类统计

### 按优先级分类

#### 必需配置参数（必须根据实际环境修改）

1. **服务器规划**
   - 所有节点的IP地址
   - 所有节点的IPv6地址（如启用双栈）
   - 网卡名称

2. **镜像仓库**
   - 镜像仓库地址和IP

3. **NFS存储**
   - NFS服务器IP
   - NFS导出路径

4. **网络配置**
   - DNS服务器地址
   - IPv6网关（如启用）
   - Pod和Service网段

5. **Redis**
   - Redis密码

#### 推荐配置参数（建议根据环境调整）

1. **证书配置**
   - 证书有效期（生产环境建议缩短）

2. **定时任务**
   - 执行时间
   - 日志保留天数

3. **用户配置**
   - 普通用户名
   - Kubemate登录密码

4. **日志配置**
   - 日志级别

#### 可选配置参数（使用默认值即可）

1. **版本号**
   - K8S版本
   - Containerd及其组件版本

2. **数据路径**
   - 各种数据目录路径

3. **部署选项**
   - 部署模式
   - 是否启用某些组件

### 按配置频率分类

#### 一次性配置（部署前设置一次）

- 服务器规划配置
- 网络配置
- 存储配置
- 证书配置

#### 环境相关配置（每个环境不同）

- IP地址
- 主机名
- 密码
- 网关地址

#### 可变配置（运行时可调整）

- 定时任务时间
- 日志级别
- 监控开关

---

## 配置文件使用建议

### 1. 配置文件选择

根据不同场景选择合适的配置文件：

| 场景 | 推荐配置文件 | 说明 |
|------|-------------|------|
| 快速测试/开发环境 | config.example.yaml | 最小化配置，快速启动 |
| 生产环境部署 | config.production.yaml | 完整配置，安全加固 |
| 定制化部署 | config.yaml | 修改默认值满足特殊需求 |

### 2. 配置验证流程

部署前建议按以下顺序验证配置：

```bash
# 1. 语法检查
yamllint config/config.yaml

# 2. 必需参数检查
# 检查所有IP地址、密码等必需参数是否已配置

# 3. 网络连通性检查
# ping 所有节点IP
# ping 镜像仓库IP
# ping NFS服务器IP

# 4. 资源检查
# 检查所有节点磁盘空间是否充足
# 检查网络带宽是否满足要求
```

### 3. 安全配置建议

生产环境部署时，务必修改以下默认配置：

1. **默认密码**
   - Kubemate登录密码
   - Redis密码
   - 镜像仓库密码（如启用认证）

2. **证书有效期**
   - 建议1-5年，避免使用100年

3. **镜像仓库**
   - 使用HTTPS而非HTTP

4. **防火墙**
   - 启用防火墙并配置合适的规则

5. **日志级别**
   - 使用info或warn级别，避免debug

---

## 配置参数映射表

### cmdlist.md → config.yaml 参数映射

| cmdlist.md章节 | 提炼的配置参数 |
|---------------|--------------|
| 1. 服务器规划 | server.nodes.*, server.network_interface |
| 2.1 配置本地yum源 | yum.*, paths.k8s_install |
| 2.3 配置本地k8s repo源客户端 | yum.http_repo_url |
| 2.4 替换kubeadm | k8s.version, k8s.arch_type |
| 2.5 安装K8s依赖包 | (无特殊参数) |
| 2.6.1 修改DNS | network.dns |
| 2.6.2 修改网络配置 | network.ipv6, server.network_interface |
| 2.6.3 修改open files参数 | system.max_open_files |
| 2.3.4 配置环境变量 | system.*, network.cluster |
| 2.4 安装containerd | containerd.* |
| 2.5 安装镜像仓库 | registry.* |
| 2.6.1 初始化K8S集群 | network.cluster, paths.kubelet_root |
| 2.6.3 修改证书有效期 | certificates.cluster_signing_duration |
| 3.1-3.2 Kubemate安装 | kubemate.* |
| 3.3 创建全局镜像仓库 | (在kubemate界面配置) |
| 3.4 安装NFS插件 | nfs.* |
| 3.5-3.8 监控组件安装 | monitoring.elasticsearch, monitoring.skywalking, monitoring.loki, monitoring.traefik |
| 3.10 安装prometheus | monitoring.prometheus |
| 3.11 更新coredns配置 | (无特殊参数) |
| 3.12 安装metrics-server | (无特殊参数) |
| 3.13 配置普通用户 | user.* |
| 3.14 配置F5 | f5.* |
| 3.15-3.17 Redis安装 | redis.* |
| 3.18 配置redis监控 | redis.monitoring |
| 3.19 定时任务 | cron_jobs.* |

---

## 总结

通过分析 `cmdlist.md` 文件，我们提炼出了 **20个主要配置模块**、**100+个配置参数**，涵盖了K8S集群部署的方方面面：

1. **基础设施配置**：服务器、网络、存储
2. **K8S核心配置**：版本、网络、证书
3. **容器运行时配置**：Containerd及组件
4. **应用组件配置**：Kubemate、监控、Redis
5. **运维配置**：定时任务、日志、备份

所有配置参数都已在 `config/config.yaml` 中定义，并提供了详细的使用说明和示例。
