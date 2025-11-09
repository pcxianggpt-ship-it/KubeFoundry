# KubeFoundry 步骤与配置参数映射文档

## 概述

本文档详细说明了 KubeFoundry 自动化部署系统中 15 个安装步骤与配置文件 `deploy-config.yaml` 中各参数的对应关系。

---

## 步骤 1: 检查是否为 root 用户

### 功能描述
确保脚本以 root 权限执行，否则终止部署流程。

### 关联配置参数
**无需配置参数** - 此步骤直接检查当前用户权限。

### 验证机制
- 检查 `$EUID` 是否为 0
- 验证失败时终止流程并记录错误

---

## 步骤 2: 服务器间免密登录配置

### 功能描述
配置控制节点到所有目标节点的 SSH 免密登录。

### 关联配置参数

#### 全局 SSH 配置 (简化)
```yaml
global:
  ssh:
    port: 22                    # SSH 端口
    key_file: "/root/.ssh/kubefoundry_rsa"  # SSH 密钥文件路径
    # 用户固定为 root，其他参数使用默认值
```

#### 节点配置 (简化)
```yaml
hosts:
  control_plane:
    - name: "k8s-master-01"     # 节点名称
      ip: "192.168.1.10"        # IP 地址
      # SSH 连接使用全局配置，用户固定为 root
      # 架构使用全局配置 architecture.target
  workers:
    - name: "k8s-worker-01"
      ip: "192.168.1.20"
      # SSH 连接使用全局配置，用户固定为 root
      # 架构使用全局配置 architecture.target
```

#### 全局架构配置
```yaml
architecture:
  target: "amd64"               # 全局架构配置，所有节点统一使用
  mapping:
    amd64:
      repository_dir: "01.AMD"  # 对应介质包目录
      rpm_arch: "x86_64"        # RPM 架构标识
```

### 执行内容
1. 生成或使用现有 SSH 密钥对
2. 分发公钥到所有目标节点
3. 验证免密登录连通性

---

## 步骤 3: 依赖检查与安装（离线 rpm）

### 功能描述
检查系统依赖并使用本地 RPM 包安装缺失组件。

### 关联配置参数

#### 全局架构配置
```yaml
architecture:
  target: "amd64"               # 全局架构配置，所有节点统一使用
  mapping:
    amd64:
      repository_dir: "01.AMD"  # 对应介质包目录
      rpm_arch: "x86_64"        # RPM 架构标识
```

#### 介质包路径
```yaml
global:
  base_path: "/data/k8s_install"  # 基础路径
  repository_path: "repository"   # 介质包仓库路径
```

### 依赖包清单
系统自动检查以下依赖：
- `curl`, `iptables`, `conntrack`, `socat`, `ipset`
- `ebtables`, `nfs-utils` 等

### 安装来源
```
repository/{architecture.repository_dir}/01.rpm_package/rpms/dependencies/
```

---

## 步骤 4: 替换 kubeadm / kubelet / kubectl 文件

### 功能描述
安装指定版本的 Kubernetes 组件。

### 关联配置参数

#### Kubernetes 版本
```yaml
kubernetes:
  version: "1.30.0"             # Kubernetes 版本
```

#### 全局架构配置
```yaml
architecture:
  target: "amd64"               # 全局架构配置，所有节点统一使用
  mapping:
    amd64:
      repository_dir: "01.AMD"
      rpm_arch: "x86_64"
```

### 安装来源
```
repository/{architecture.repository_dir}/01.rpm_package/rpms/kubernetes/
```

### 安装包示例
- `kubelet-1.30.0-0.x86_64.rpm`
- `kubeadm-1.30.0-0.x86_64.rpm`
- `kubectl-1.30.0-0.x86_64.rpm`
- `kubernetes-cni-1.2.0-0.x86_64.rpm`

---

## 步骤 5: 配置系统参数

### 功能描述
配置系统参数以支持 Kubernetes 运行。

### 关联配置参数

#### 内核参数配置
```yaml
# 此步骤使用 Kubernetes 默认配置，无需额外参数
# 系统将自动配置：
# - 关闭 swap
# - 禁用 SELinux
# - 配置防火墙规则
# - 设置 sysctl 参数
# - 加载内核模块 (br_netfilter, overlay)
```

### 执行内容
1. 关闭 swap 分区
2. 禁用 SELinux (`setenforce 0`)
3. 配置防火墙规则
4. 设置内核参数 (`net.bridge.bridge-nf-call-iptables=1` 等)
5. 加载必要内核模块

---

## 步骤 6: 安装容器运行时（Docker / containerd）

### 功能描述
根据配置选择并安装容器运行时。

### 关联配置参数

#### 运行时选择
```yaml
container_runtime:
  type: "docker"                # 运行时类型: docker 或 containerd
```

#### Docker 配置
```yaml
container_runtime:
  docker:
    version: "24.0.7"           # Docker 版本
    binary_package: "docker-24.0.7.tgz"  # 二进制包文件名
    plugins:
      compose: "docker-compose-plugin-2.21.0.tgz"
      buildx: "docker-buildx-plugin-0.11.2.tgz"
    install_dir: "/usr/bin"     # 安装目录
    data_dir: "/var/lib/docker" # 数据目录
    daemon_config:
      storage-driver: "overlay2"
      log-driver: "json-file"
      log-opts:
        max-size: "100m"
        max-file: "5"
      registry-mirrors:
        - "http://registry:5000"  # 私有镜像仓库地址
```

#### containerd 配置
```yaml
container_runtime:
  containerd:
    version: "1.7.18"                           # containerd 版本
    binary_package: "containerd-1.7.18-linux-{arch}.tar.gz"
    runc_binary: "runc.{arch}"
    crictl_package: "crictl-v1.29.0-linux-{arch}.tar.gz"
    install_dir: "/usr/local"
    data_dir: "/var/lib/containerd"
    config_file: "/etc/containerd/config.toml"
    config_template:
      version: 2
      plugins:
        "io.containerd.grpc.v1.cri":
          sandbox_image: "registry.k8s.io/pause:3.9"
          systemd_cgroup: true
```

### 安装来源
```
repository/{architecture.repository_dir}/02.install_package/binaries/
├── docker/
│   ├── docker-24.0.7.tgz
│   ├── docker-compose-plugin-2.21.0.tgz
│   └── docker-buildx-plugin-0.11.2.tgz
└── containerd/
    ├── containerd-1.7.18-linux-{arch}.tar.gz
    ├── runc.{arch}
    └── crictl-v1.29.0-linux-{arch}.tar.gz
```

---

## 步骤 7: 安装镜像仓库（Registry / Harbor）

### 功能描述
部署独立私有镜像仓库服务。**重要：镜像仓库必须独立部署在专用服务器上，不能部署在K8S集群内，否则无法解决初始化时的镜像拉取循环依赖问题。**

### 关联配置参数

#### 镜像仓库主机配置
```yaml
registry:
  type: "registry"              # 仓库类型: registry 或 harbor

  # 镜像仓库部署主机配置 (独立于K8S集群，集群初始化前必须就绪)
  host:
    ip: "192.168.1.9"                    # 镜像仓库专用服务器IP
    hostname: "registry.k8s.local"       # 主机名

  # 网络配置
  network:
    port: 5000                          # Registry 服务端口
    ui_port: 5080                       # Registry UI 端口
    expose_external: true               # 是否对外暴露服务
    external_ip: "192.168.1.9"          # 外部访问IP

  # 数据存储配置 (本地存储，不使用共享存储)
  storage:
    type: "local"                       # 本地存储类型
    path: "/data/registry"              # 本地存储路径
    size: "500Gi"                       # 存储容量
    disk:
      device: "/dev/sdb"                # 专用磁盘设备 (可选)
      mount_point: "/data/registry"     # 挂载点
      filesystem: "ext4"                # 文件系统类型
      mount_options: "defaults,noatime" # 挂载选项
```

#### Docker Registry 配置 (独立部署)
```yaml
registry:
  registry_config:
    image: "registry:2.7.1"              # Registry 镜像版本

    # 服务配置
    service:
      name: "docker-registry"
      container_name: "registry-init"   # 容器名称

    # 认证配置
    auth:
      enabled: false                    # 是否启用认证
      htpasswd_file: "/data/registry_data/auth/htpasswd"
      # 脚本参数：
      # - 参数3: 镜像仓库用户名
      # - 参数4: 镜像仓库密码
      # - 参数5: 是否加密 (yes/no)

    # 数据配置
    data:
      base_path: "/data/registry_data"       # 数据基础路径
      registry_path: "/data/registry_data/registry"
      auth_path: "/data/registry_data/auth"

    # 镜像加载配置
    images:
      source_path: "/data/k8s_install/04.registry/"
      packages:
        - "registry-2.7.1-{arch}.tar"     # Registry镜像包
        - "registry-ui-{arch}.tar"        # Registry UI镜像包
      data_archive: "registry-{arch}.tgz" # 镜像数据归档文件

    # 脚本执行配置
    script:
      path: "/data/k8s_install/03.registry_install.sh"
      parameters:
        - "$1"                            # 本机IP地址
        - "$2"                            # 架构型号 (arm/amd)
        - "$3"                            # 镜像仓库用户名 (可选)
        - "$4"                            # 镜像仓库密码 (可选)
        - "$5"                            # 是否加密 (yes/no)
```

#### Registry UI 配置
```yaml
registry:
  registry_ui:
    enabled: true
    image: "joxit/docker-registry-ui:2.2.2"  # UI 镜像版本

    service:
      name: "registry-ui"
      container_name: "registry-ui-init"    # UI 容器名称

    ports:
      - "5080:80"                           # UI 端口映射

    environment:
      REGISTRY_TITLE: "Registry"            # Registry 标题
      REGISTRY_URL: "http://192.168.1.9:5000"  # Registry URL
      DELETE_IMAGES: true                   # 允许删除镜像
```

#### Harbor 配置 (可选)
```yaml
registry:
  harbor_config:
    enabled: false                    # 是否启用 Harbor
    version: "v2.9.0"

    # 存储配置 (本地存储)
    storage:
      type: "local"
      path: "/data/harbor"
      size: "1Ti"

    auth:
      admin_password: "Harbor12345"
      mode: "db_auth"
```

### 执行内容

#### 1. 镜像仓库部署流程
```bash
# 脚本执行方式
./03.registry_install.sh <IP> <ARCH> [USERNAME] [PASSWORD] [ENCRYPT]

# 示例：
./03.registry_install.sh 192.168.1.9 amd64 "" "" no
```

#### 2. 部署步骤
1. **加载镜像**：
   - `docker load -i registry-2.7.1-{arch}.tar`
   - `docker load -i registry-ui-{arch}.tar`

2. **解压镜像数据**：
   - `tar -xzf registry-{arch}.tgz -C /data`
   - `mv registry registry_data`

3. **启动 Registry UI**：
   ```bash
   docker run -d --restart=always --name registry-ui-init -p 5080:80 \
     -e REGISTRY_TITLE=Registry \
     -e REGISTRY_URL=http://$1:5000 \
     -e DELETE_IMAGES=true \
     joxit/docker-registry-ui:2.2.2
   ```

4. **启动 Registry 服务**：
   - **非认证模式**：
     ```bash
     docker run -d --restart=always --name registry-init -p 5000:5000 \
       -v /data/registry_data/registry:/var/lib/registry \
       -v /data/registry_data/config.yml:/etc/docker/registry/config.yml \
       registry:2.7.1
     ```

   - **认证模式**：
     ```bash
     htpasswd -bBc /data/registry_data/auth/htpasswd $V_USER $V_PASSWORD
     docker run -d --name registry-init \
       -p 5000:5000 \
       -v /data/registry_data/registry:/var/lib/registry \
       -v /data/registry_data/config.yml:/etc/docker/registry/config.yml \
       -v /data/registry_data/auth:/etc/docker/registry/auth \
       -e "REGISTRY_AUTH=htpasswd" \
       -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
       -e "REGISTRY_AUTH_HTPASSWD_PATH=/etc/docker/registry/auth/htpasswd" \
       registry:2.7.1
     ```

### 安装来源
```
/data/k8s_install/
├── 03.registry_install.sh        # 镜像仓库安装脚本
└── 04.registry/                  # Registry 相关文件
    ├── registry-2.7.1-{arch}.tar # Registry 镜像包
    ├── registry-ui-{arch}.tar    # Registry UI 镜像包
    ├── registry-{arch}.tgz       # 镜像数据归档
    └── config.yml                # Registry 配置文件
```

### 验证方式
1. **Registry 服务验证**：
   - 访问：`http://192.168.1.9:5000/v2/_catalog`
   - 检查镜像列表

2. **Registry UI 验证**：
   - 访问：`http://192.168.1.9:5080`
   - 浏览镜像仓库

3. **Docker 推拉测试**：
   ```bash
   docker pull 192.168.1.9:5000/test-image
   docker push 192.168.1.9:5000/test-image
   ```

---

## 步骤 8: 初始化 Kubernetes 集群（kubeadm init）

### 功能描述
初始化 Kubernetes 控制平面。

### 关联配置参数

#### 集群网络配置
```yaml
# 此步骤使用 Kubernetes 默认配置
# 系统自动使用默认值：
# - Pod CIDR: 10.244.0.0/16
# - Service CIDR: 10.96.0.0/12
# - DNS Domain: cluster.local
```

#### 控制平面节点
```yaml
hosts:
  control_plane:
    - name: "k8s-master-01"
      ip: "192.168.1.10"        # 主控制节点 IP (作为 advertise_address)
```

#### Kubernetes 版本
```yaml
kubernetes:
  version: "1.30.0"             # 指定初始化版本
```

### 执行内容
1. 生成 kubeadm 配置文件
2. 执行 `kubeadm init`
3. 保存 join token 和配置
4. 配置 kubectl 访问权限
5. 验证控制平面 Pod 状态

---

## 步骤 9: 配置 kube-controller-manager 参数

### 功能描述
配置 kube-controller-manager 的证书签名期限参数。

### 关联配置参数

#### Controller Manager 配置
```yaml
# 此步骤执行固定操作
# 自动添加参数: --cluster-signing-duration=867240h0m0s
# 这是 100 年的证书有效期，符合需求文档要求
```

### 执行内容
1. 备份原始配置文件 `/etc/kubernetes/manifests/kube-controller-manager.yaml`
2. 修改 Pod 清单，在 `spec.containers[0].command` 末尾添加参数
3. 等待 kubelet 自动重启 Pod
4. 验证参数生效

---

## 步骤 10: 添加控制平面节点

### 功能描述
将其他控制平面节点加入集群。

### 关联配置参数

#### 控制平面节点配置
```yaml
hosts:
  control_plane:
    - name: "k8s-master-02"     # 其他控制平面节点
      ip: "192.168.1.11"
    - name: "k8s-master-03"
      ip: "192.168.1.12"
    # SSH 连接使用全局配置，用户固定为 root
    # 架构使用全局配置 architecture.target
```

### 执行内容
1. 分发 join 命令到其他控制平面节点
2. 执行 control-plane join 操作
3. 验证 etcd 成员状态
4. 检查节点状态

---

## 步骤 11: 添加工作节点

### 功能描述
将工作节点加入集群。

### 关联配置参数

#### 工作节点配置
```yaml
hosts:
  workers:
    - name: "k8s-worker-01"
      ip: "192.168.1.20"        # 工作节点 IP
    # SSH 连接使用全局配置，用户固定为 root
    # 架构使用全局配置 architecture.target，所有节点架构一致
    # ... 其他工作节点
```

### 执行内容
1. 分发 worker join 命令
2. 执行 join 操作
3. 验证节点 `Ready` 状态
4. 检查 kubelet 运行状态

---

## 步骤 12: 安装 CNI 插件（Flannel）

### 功能描述
安装网络插件以实现 Pod 网络通信。

### 关联配置参数

#### 网络配置
```yaml
networking:
  cni: "flannel"                # CNI 插件类型
  flannel:
    version: "v0.22.0"         # Flannel 版本
    backend: "vxlan"           # 后端类型
    port: 8472                 # VXLAN 端口
    vni: 1                     # VNI 标识
    direct_routing: false
```

### 安装来源
```
repository/{architecture.repository_dir}/03.setup_file/manifests/networking/flannel/
```

### 执行内容
1. 部署 Flannel DaemonSet
2. 验证网络连通性
3. 检查 Pod 状态和网络配置

---

## 步骤 13: 安装 NFS Client Provisioner

### 功能描述
部署 NFS 存储提供器，支持动态 PVC 创建。

### 关联配置参数

#### NFS 存储配置
```yaml
storage:
  nfs:
    server: "192.168.1.100"     # NFS 服务器地址
    path: "/data/nfs"           # NFS 导出路径
    read_only: false
    storage_class:
      name: "nfs-client"
      provisioner: "nfs.csi.k8s.io"
      parameters:
        server: "192.168.1.100"
        share: "/data/nfs"
        readOnly: "false"
      reclaim_policy: "Delete"
      volume_binding_mode: "Immediate"
```

### 安装来源
```
repository/{architecture.repository_dir}/03.setup_file/manifests/storage/nfs-client/
```

### 执行内容
1. 部署 NFS Client Provisioner
2. 创建 StorageClass
3. 验证 PVC 自动创建功能
4. 测试存储读写权限

---

## 步骤 14: 安装定制化组件

### 功能描述
部署扩展组件：KubeMate、NFS Client、Prometheus、Traefik (必装) 和 Redis、Loki (选装)。

### 关联配置参数

#### 扩展组件配置 (简化版)
```yaml
addons:
  # KubeMate Kubernetes 管理工具 (必装)
  kubemate:
    enabled: true

  # NFS Client 存储提供器 (必装)
  nfs_client:
    enabled: true

  # Prometheus 监控系统 (必装)
  prometheus:
    enabled: true

  # Traefik Ingress Controller (必装)
  traefik:
    enabled: true

  # Redis 缓存服务 (选装)
  redis:
    enabled: false

  # Loki 日志聚合系统 (选装)
  loki:
    enabled: false
```

### 组件分类
- **必装组件**: KubeMate, NFS Client, Prometheus, Traefik
- **选装组件**: Redis, Loki

### 安装来源
```
repository/{architecture.repository_dir}/03.setup_file/manifests/addons/
├── kubemate/           # KubeMate 管理工具
├── nfs-client/         # NFS Client 存储提供器
├── prometheus/         # Prometheus 监控系统
├── traefik/            # Traefik Ingress Controller
├── redis/              # Redis 缓存服务
└── loki/               # Loki 日志聚合系统
```

### 执行内容
1. 根据配置部署启用的组件
2. 替换配置模板中的变量
3. 验证组件 Pod 状态
4. 检查服务可访问性

---

## 步骤 15: 配置 etcd 定时备份任务

### 功能描述
部署 etcd 备份脚本并配置定时任务。

### 关联配置参数

#### 备份配置
```yaml
backup:
  etcd:
    enabled: true               # 是否启用备份
    schedule: "0 2 * * *"       # Crontab 调度 (每天凌晨2点)
    retention: "30d"            # 备份保留期限
    storage_path: "/backup/etcd" # 备份存储路径
    storage_size: "10Gi"        # 备份存储大小
    compression: true           # 是否压缩
    encryption: false           # 是否加密
    encryption_key: ""          # 加密密钥
```

### 安装来源
```
repository/{architecture.repository_dir}/06.crontab/
├── etcd-backup.sh             # etcd 备份脚本
├── log-rotate.sh              # 日志轮转脚本
├── health-check.sh            # 健康检查脚本
└── crontab-entries            # Crontab 条目模板
```

### 执行内容
1. 部署备份脚本到控制节点
2. 配置 Crontab 定时任务
3. 执行一次备份测试
4. 验证备份文件有效性
5. 配置日志轮转

---

## 全局配置参数影响

### 全局基础配置
```yaml
global:
  base_path: "/data/k8s_install"           # 影响所有路径
  repository_path: "repository"           # 介质包路径
  log_path: "/var/log/kubefoundry"        # 日志路径
  temp_path: "/tmp/kubefoundry"           # 临时文件路径
  timezone: "Asia/Shanghai"               # 时区设置
  deployment:
    parallel_nodes: 5                     # 并行部署节点数
    retry_count: 3                        # 失败重试次数
    rollback_on_failure: true             # 失败时回滚
```

### 架构配置影响
```yaml
architecture:
  target: "amd64"                         # 全局架构配置，影响所有节点和介质包选择
  mapping:
    amd64:
      repository_dir: "01.AMD"            # 介质包目录映射
      kernel_arch: "x86_64"
      rpm_arch: "x86_64"
      platform: "linux/amd64"
```

## 配置参数优先级

1. **全局配置统一**
   - SSH 用户固定为 root，所有节点使用相同用户
   - SSH 端口使用全局配置 (port: 22)
   - 架构使用全局配置 `architecture.target`，所有节点架构一致

2. **明确配置** > **默认值**
   - 明确指定的参数优先于系统默认值

3. **必需参数缺失时终止**
   - 缺少必需参数时，部署流程将终止并报错

## 参数验证机制

每个步骤执行前，系统会验证：
- 所需配置参数是否存在
- 参数值格式是否正确
- 参数值是否在有效范围内
- 相关的介质包文件是否存在

验证失败将终止部署并输出详细的错误信息。

---

## 总结

此映射文档明确了 15 个部署步骤与配置文件中各参数的对应关系。用户可以通过修改 `deploy-config.yaml` 文件来定制部署行为，系统会根据配置自动选择对应的介质包和参数进行部署。

所有配置参数都有明确的用途和默认值，用户只需关注需要修改的部分，其他参数使用默认值即可完成标准部署。