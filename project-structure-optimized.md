# KubeFoundry 多架构优化项目结构

基于实际介质包存放结构，支持 AMD/ARM 多架构离线部署的优化项目结构：

```
kubefoundry/
├── README.md                          # 项目总体说明
├── CLAUDE.md                          # Claude Code 工作指导
├── LICENSE                            # 开源许可证
├── CHANGELOG.md                       # 版本变更日志
├── Makefile                           # 构建和安装脚本
├── .gitignore                         # Git 忽略文件配置
│
├── controller.sh                      # 主控制脚本 (入口)
├── executor.sh                        # 节点执行器脚本
├── distribute.sh                      # 介质分发工具脚本
│
├── config/                            # 配置文件目录
│   ├── deploy-config.yaml             # 主配置文件模板
│   ├── deploy-config.yaml.example     # 配置文件示例
│   ├── config-schema.json             # 配置文件 JSON Schema
│   ├── arch-config.yaml               # 架构配置映射
│   └── defaults/                      # 默认配置值目录
│       ├── global.yaml
│       ├── packages.yaml
│       ├── storage.yaml
│       └── arch-mapping.yaml          # 架构映射配置
│
├── scripts/                           # 工具和辅助脚本目录
│   ├── validate-config.sh             # 配置验证脚本
│   ├── setup-dev.sh                   # 开发环境设置
│   ├── lint.sh                        # 代码检查脚本
│   ├── format.sh                      # 代码格式化脚本
│   ├── generate-schema.sh             # 配置 Schema 生成
│   ├── backup-config.sh               # 配置备份脚本
│   ├── health-check.sh                # 部署后健康检查
│   ├── arch-detect.sh                 # 架构检测脚本
│   └── package-organize.sh            # 介质包组织脚本
│
├── lib/                               # 核心函数库目录
│   ├── common.sh                      # 通用工具函数
│   ├── logger.sh                      # 日志管理函数
│   ├── ssh-manager.sh                 # SSH 密钥管理
│   ├── package-installer.sh           # 离线包安装器
│   ├── k8s-utils.sh                   # Kubernetes 工具函数
│   ├── network-utils.sh               # 网络配置工具
│   ├── storage-utils.sh               # 存储配置工具
│   ├── state-manager.sh               # 状态管理函数
│   ├── arch-manager.sh                # 架构管理函数
│   └── dist-manager.sh                # 分发管理函数
│
├── steps/                             # 部署步骤脚本目录
│   ├── step-01-root-check.sh          # Root 权限验证
│   ├── step-02-ssh-keys.sh            # SSH 密钥分发
│   ├── step-03-dependencies.sh        # 依赖检查与安装
│   ├── step-04-k8s-components.sh      # K8s 组件安装
│   ├── step-05-system-config.sh       # 系统参数配置
│   ├── step-06-container-runtime.sh   # 容器运行时安装
│   ├── step-07-registry.sh            # 私有镜像仓库部署
│   ├── step-08-cluster-init.sh        # 集群初始化
│   ├── step-09-controller-config.sh   # kube-controller-manager 配置
│   ├── step-10-control-plane.sh       # 控制平面节点添加
│   ├── step-11-worker-nodes.sh        # 工作节点添加
│   ├── step-12-cni-network.sh         # CNI 网络插件安装
│   ├── step-13-nfs-storage.sh         # NFS 存储配置
│   ├── step-14-addons.sh              # 扩展组件部署
│   └── step-15-backup.sh              # etcd 备份配置
│
├── repository/                        # 多架构介质包仓库 (核心优化)
│   ├── 01.AMD/                        # AMD64 架构介质包
│   │   ├── 01.rpm_package/            # AMD 架构系统依赖包 (不含容器运行时)
│   │   │   ├── rpms/                  # RPM 包目录
│   │   │   │   ├── kubernetes/        # Kubernetes 组件 RPM
│   │   │   │   └── dependencies/      # 系统依赖 RPM (conntrack, socat, ebtables等)
│   │   │   └── manifests.json         # 包清单文件
│   │   ├── 02.install_package/        # AMD 架构运行时安装包
│   │   │   ├── binaries/              # 二进制安装文件
│   │   │   │   ├── docker/            # Docker 二进制文件
│   │   │   │   │   ├── docker-24.0.7.tgz
│   │   │   │   │   ├── docker-compose-plugin-2.21.0.tgz
│   │   │   │   │   └── docker-buildx-plugin-0.11.2.tgz
│   │   │   │   └── containerd/        # containerd 二进制文件
│   │   │   │       ├── containerd-1.7.18-linux-amd64.tar.gz
│   │   │   │       ├── runc.amd64
│   │   │   │       └── crictl-v1.29.0-linux-amd64.tar.gz
│   │   │   ├── images/                # 容器镜像
│   │   │   │   ├── kubernetes/        # K8s 核心镜像
│   │   │   │   ├── registry/          # 镜像仓库镜像
│   │   │   │   ├── harbor/            # Harbor 镜像
│   │   │   │   └── addons/            # 扩展组件镜像
│   │   │   └── manifests.json         # 安装包和镜像清单文件
│   │   ├── 03.setup_file/             # 初始化集群配置文件
│   │   │   ├── manifests/             # YAML 清单文件
│   │   │   │   ├── registry/          # 镜像仓库配置
│   │   │   │   │   ├── docker-registry/
│   │   │   │   │   └── harbor/
│   │   │   │   ├── networking/        # 网络组件 (Flannel)
│   │   │   │   ├── storage/           # 存储组件 (NFS)
│   │   │   │   └── addons/            # 扩展组件
│   │   │   │       ├── traefik/
│   │   │   │       ├── prometheus/
│   │   │   │       └── redis/
│   │   │   ├── systemd/               # 系统服务文件
│   │   │   │   ├── docker.service
│   │   │   │   ├── containerd.service
│   │   │   │   └── kubelet.service
│   │   │   └── config-templates/      # 配置模板文件
│   │   │       ├── docker-daemon.json
│   │   │       ├── containerd-config.toml
│   │   │       └── kubelet-config.yaml
│   │   ├── 04.registry/                # ARM 架构镜像仓库
│   │   │   ├── docker-registry/       # Docker Registry 配置和脚本
│   │   │   ├── certificates/          # 证书文件
│   │   │   └── config/                # 仓库配置文件
│   │   ├── 05.harbor/                  # ARM 架构 Harbor 仓库
│   │   │   ├── installer/             # Harbor 安装包
│   │   │   ├── configs/               # Harbor 配置文件
│   │   │   └── docker-compose/        # Docker Compose 文件
│   │   ├── 06.crontab/                # 定时任务脚本
│   │   │   ├── etcd-backup.sh         # etcd 备份脚本
│   │   │   ├── log-rotate.sh          # 日志轮转脚本
│   │   │   ├── health-check.sh        # 健康检查脚本
│   │   │   └── crontab-entries        # Crontab 条目模板
│   │   └── architecture-info.json     # AMD 架构信息文件
│   │
│   ├── 02.ARM/                        # ARM64 架构介质包
│   │   ├── 01.rpm_package/            # ARM 架构系统依赖包 (不含容器运行时)
│   │   │   ├── rpms/                  # RPM 包目录
│   │   │   │   ├── kubernetes/        # Kubernetes 组件 RPM
│   │   │   │   └── dependencies/      # 系统依赖 RPM (conntrack, socat, ebtables等)
│   │   │   └── manifests.json         # 包清单文件
│   │   ├── 02.install_package/        # ARM 架构运行时安装包
│   │   │   ├── binaries/              # 二进制安装文件
│   │   │   │   ├── docker/            # Docker 二进制文件
│   │   │   │   │   ├── docker-24.0.7.tgz
│   │   │   │   │   ├── docker-compose-plugin-2.21.0.tgz
│   │   │   │   │   └── docker-buildx-plugin-0.11.2.tgz
│   │   │   │   └── containerd/        # containerd 二进制文件
│   │   │   │       ├── containerd-1.7.18-linux-arm64.tar.gz
│   │   │   │       ├── runc.arm64
│   │   │   │       └── crictl-v1.29.0-linux-arm64.tar.gz
│   │   │   ├── images/                # 容器镜像
│   │   │   │   ├── kubernetes/        # K8s 核心镜像
│   │   │   │   ├── registry/          # 镜像仓库镜像
│   │   │   │   ├── harbor/            # Harbor 镜像
│   │   │   │   └── addons/            # 扩展组件镜像
│   │   │   └── manifests.json         # 安装包和镜像清单文件
│   │   ├── 03.setup_file/             # 初始化集群配置文件
│   │   │   ├── manifests/             # YAML 清单文件
│   │   │   │   ├── registry/          # 镜像仓库配置
│   │   │   │   │   ├── docker-registry/
│   │   │   │   │   └── harbor/
│   │   │   │   ├── networking/        # 网络组件 (Flannel)
│   │   │   │   ├── storage/           # 存储组件 (NFS)
│   │   │   │   └── addons/            # 扩展组件
│   │   │   │       ├── traefik/
│   │   │   │       ├── prometheus/
│   │   │   │       └── redis/
│   │   │   └── config-templates/      # 配置模板文件
│   │   ├── 04.registry/                # ARM 架构镜像仓库
│   │   │   ├── docker-registry/       # Docker Registry 配置和脚本
│   │   │   ├── certificates/          # 证书文件
│   │   │   └── config/                # 仓库配置文件
│   │   ├── 05.harbor/                  # ARM 架构 Harbor 仓库
│   │   │   ├── installer/             # Harbor 安装包
│   │   │   ├── configs/               # Harbor 配置文件
│   │   │   └── docker-compose/        # Docker Compose 文件
│   │   ├── 06.crontab/                # 定时任务脚本
│   │   │   ├── etcd-backup.sh         # etcd 备份脚本
│   │   │   ├── log-rotate.sh          # 日志轮转脚本
│   │   │   ├── health-check.sh        # 健康检查脚本
│   │   │   └── crontab-entries        # Crontab 条目模板
│   │   └── architecture-info.json     # ARM 架构信息文件
│   │
│   └── manifest.json                  # 总体清单文件
│
├── tools/                             # 专用工具目录
│   ├── etcd-backup.sh                 # etcd 备份恢复工具
│   ├── cluster-info.sh                # 集群信息查询工具
│   ├── node-status.sh                 # 节点状态检查工具
│   ├── rollback.sh                    # 回滚工具
│   ├── cleanup.sh                     # 清理工具
│   ├── arch-sync.sh                   # 架构间同步工具
│   └── repo-validate.sh               # 仓库验证工具
│
├── test/                              # 测试目录
│   ├── unit/                          # 单元测试
│   │   ├── test-logger.sh
│   │   ├── test-ssh-manager.sh
│   │   ├── test-package-installer.sh
│   │   ├── test-k8s-utils.sh
│   │   └── test-arch-manager.sh
│   ├── integration/                   # 集成测试
│   │   ├── test-deployment-flow.sh
│   │   ├── test-cluster-init.sh
│   │   ├── test-network-config.sh
│   │   ├── test-storage-setup.sh
│   │   └── test-multi-arch.sh
│   ├── e2e/                          # 端到端测试
│   │   ├── test-full-deployment.sh
│   │   ├── test-rollback.sh
│   │   ├── test-recovery.sh
│   │   └── test-multi-arch-deployment.sh
│   ├── mocks/                        # 模拟环境
│   │   ├── mock-ssh-server.sh
│   │   ├── mock-k8s-cluster.sh
│   │   ├── mock-package-repo.sh
│   │   └── mock-multi-arch.sh
│   └── data/                          # 测试数据
│       ├── test-configs/
│       ├── test-manifests/
│       └── test-packages/
│
├── docs/                              # 文档目录
│   ├── user-guide/                    # 用户指南
│   │   ├── installation.md
│   │   ├── configuration.md
│   │   ├── deployment.md
│   │   ├── multi-arch-deployment.md   # 多架构部署指南
│   │   ├── troubleshooting.md
│   │   └── best-practices.md
│   ├── developer-guide/               # 开发者指南
│   │   ├── architecture.md
│   │   ├── multi-arch-support.md      # 多架构支持文档
│   │   ├── code-conventions.md
│   │   ├── testing.md
│   │   ├── contributing.md
│   │   └── api-reference.md
│   ├── examples/                      # 示例配置
│   │   ├── small-cluster.yaml
│   │   ├── large-cluster.yaml
│   │   ├── ha-cluster.yaml
│   │   ├── custom-components.yaml
│   │   └── multi-arch-cluster.yaml    # 多架构集群示例
│   └── design/                        # 设计文档
│       ├── architecture.md
│       ├── multi-arch-design.md       # 多架构设计文档
│       └── performance.md
│
├── deployment/                        # 部署相关目录
│   ├── environments/                  # 环境配置
│   │   ├── dev.yaml
│   │   ├── staging.yaml
│   │   ├── prod.yaml
│   │   └── multi-arch.yaml           # 多架构环境配置
│   ├── scripts/                       # 部署脚本
│   │   ├── prepare-environment.sh
│   │   ├── validate-environment.sh
│   │   ├── post-deploy-check.sh
│   │   └── arch-prep.sh              # 架构准备脚本
│   └── ansible/                       # Ansible 配置 (可选)
│       ├── playbooks/
│       ├── roles/
│       └── inventory/
│
├── monitoring/                        # 监控配置目录
│   ├── prometheus/                    # Prometheus 配置
│   │   ├── rules/
│   │   ├── alerts/
│   │   └── dashboards/
│   ├── grafana/                       # Grafana 配置
│   │   ├── dashboards/
│   │   └── datasources/
│   └── scripts/                       # 监控脚本
│       ├── metrics-collector.sh
│       ├── health-monitor.sh
│       └── arch-monitor.sh           # 架构监控脚本
```

## 核心优化点

### 1. 多架构介质包仓库 (repository/)
- **01.AMD/** 和 **02.ARM/** 分别对应 x86_64 和 ARM64 架构
- 保持您现有的 6 个分类结构，并优化了安装方式：
  - `01.rpm_package`: 系统依赖包 (Kubernetes 组件 RPM，不包含容器运行时)
  - `02.install_package`: 运行时安装包（二进制文件 + 容器镜像）
    - `binaries/`: Docker 和 containerd 二进制安装文件
    - `images/`: Kubernetes 和扩展组件容器镜像
  - `03.setup_file`: 配置文件和 YAML 清单
    - `manifests/`: Kubernetes 资源清单
    - `systemd/`: 系统服务文件 (docker.service, containerd.service)
    - `config-templates/`: 配置模板文件
  - `04.registry`: 镜像仓库
  - `05.harbor`: Harbor 仓库
  - `06.crontab`: 定时任务脚本

### 2. 容器运行时二进制安装
- **Docker**: 使用官方二进制包 `docker-24.0.7.tgz` 及插件
- **containerd**: 使用官方二进制包 `containerd-1.7.18-linux-{arch}.tar.gz`
- **安装方式**: 解压到指定目录，配置 systemd 服务
- **配置管理**: 通过模板文件生成 daemon.json 和 config.toml

### 3. 架构自动检测和选择
- `lib/arch-manager.sh`: 架构检测和管理
- `scripts/arch-detect.sh`: 自动检测节点架构
- 配置文件中统一指定目标架构，确保集群一致性

### 4. 智能分发机制
- `lib/dist-manager.sh`: 分发管理，根据架构选择对应介质包
- `distribute.sh` 支持架构特定介质包分发
- 自动选择对应架构的二进制文件和镜像

### 5. 配置适配
- 架构在配置文件中统一指定 (amd64 或 arm64)
- 部署前验证所有节点架构一致性
- 根据目标架构自动选择对应的介质包
- 容器运行时支持二进制安装配置

## 使用流程

### 1. 架构配置
```bash
# 在配置文件中指定目标架构 (amd64 或 arm64)
sed -i 's/target: "amd64"/target: "arm64"/' config/deploy-config.yaml
```

### 2. 配置验证
```bash
# 验证配置文件和架构设置
./scripts/validate-config.sh --config deploy-config.yaml
```

### 3. 介质包准备
```bash
# 验证指定架构的介质包完整性
./scripts/repo-validate.sh --arch $(yq e '.architecture.target' config/deploy-config.yaml)
```

### 4. 部署执行
```bash
# 执行部署 (自动根据配置选择对应架构的二进制文件和介质包)
./controller.sh --config deploy-config.yaml
```

### 5. 容器运行时安装流程
```bash
# Docker 二进制安装示例
1. 解压: tar -xzf docker-24.0.7.tgz -C /usr/bin
2. 安装插件: tar -xzf docker-compose-plugin-2.21.0.tgz -C /usr/local/bin
3. 配置服务: cp setup-file/systemd/docker.service /etc/systemd/system/
4. 生成配置: jinja2 docker-daemon.json.j2 > /etc/docker/daemon.json
5. 启动服务: systemctl enable --now docker
```

## 优势

1. **架构单一性**: 集群内所有节点使用统一架构，避免兼容性问题
2. **二进制安装**: Docker 和 containerd 使用官方二进制包，更稳定可靠
3. **配置简化**: 通过单一配置项指定目标架构和容器运行时
4. **自动选择**: 根据配置自动选择对应架构的二进制文件和介质包
5. **一致性验证**: 部署前验证所有节点架构一致性
6. **统一管理**: 配置和操作保持一致性，降低运维复杂度
7. **介质包隔离**: 不同架构介质包完全分离，避免混淆
8. **服务管理**: 通过 systemd 统一管理容器运行时服务

这个优化结构完全基于您现有的介质包存放方式，在保持使用习惯的同时，提供了简洁的架构选择能力。集群内所有节点必须使用相同架构，通过配置文件统一指定，系统会自动选择对应架构的介质包进行部署。