# KubeFoundry

KubeFoundry 是一个专为离线环境设计的 Kubernetes 自动化部署系统，采用控制节点-代理节点架构，通过 SSH 协议协调多个目标节点的部署工作。

## 🚀 特性

- **离线部署能力**: 完全支持离线环境部署，无需外部网络连接
- **多架构支持**: 支持 x86_64 和 ARM64 架构的集群部署
- **双栈网络**: 支持 IPv4/IPv6 双栈网络配置
- **容器运行时自动选择**: 根据 Kubernetes 版本自动选择 Docker 或 containerd
- **kube-controller-manager 参数配置**: 自动配置集群签名期限参数
- **15步部署流程**: 从环境准备到备份配置的完整流程
- **状态跟踪和恢复**: 支持部署中断后的恢复和状态跟踪
- **并行执行**: 支持多节点并行部署，提高部署效率

## 📋 系统要求

### 支持的操作系统
- RHEL/CentOS/AlmaLinux/Oracle Linux 8+

### 系统架构
- x86_64 或 ARM64（集群内所有节点必须使用相同架构）

### 系统资源
- 最小内存：2GB
- 最小磁盘空间：10GB
- 推荐配置：每个节点至少 4GB 内存，50GB 磁盘空间

### 必需软件
- bash 4.4+
- ssh/scp
- tar/gzip
- yq (YAML 处理工具)
- jq (JSON 处理工具)

## 🏗️ 项目结构

```
kubefoundry/
├── README.md                    # 项目说明文档
├── CLAUDE.md                    # Claude Code 工作指导
├── controller.sh                # 主控制脚本 (入口)
├── executor.sh                  # 节点执行器脚本
├── distribute.sh                # 介质分发工具脚本
├── config/                      # 配置文件目录
│   ├── deploy-config.yaml       # 主配置文件
│   ├── deploy-config.yaml.example # 配置文件示例
│   └── defaults/                # 默认配置值目录
├── scripts/                     # 工具和辅助脚本目录
│   └── validate-config.sh       # 配置验证脚本
├── lib/                         # 核心函数库目录
│   ├── common.sh                # 通用工具函数
│   ├── logger.sh                # 日志管理函数
│   ├── state-manager.sh         # 状态管理函数
│   └── config-parser.sh         # 配置解析函数
├── steps/                       # 部署步骤脚本目录
│   ├── step-01-root-check.sh    # Root 权限验证
│   ├── step-02-ssh-keys.sh      # SSH 密钥分发
│   └── ...                      # 其他步骤脚本
├── repository/                  # 多架构介质包仓库
│   ├── 01.AMD/                  # AMD64 架构介质包
│   └── 02.ARM/                  # ARM64 架构介质包
├── tools/                       # 专用工具目录
├── test/                        # 测试目录
├── docs/                        # 文档目录
├── deployment/                  # 部署相关目录
└── monitoring/                  # 监控配置目录
```

## 🚀 快速开始

### 1. 克隆项目

```bash
git clone <repository-url>
cd kubefoundry
```

### 2. 生成配置文件

```bash
./controller.sh --generate-config
```

### 3. 编辑配置文件

```bash
vi config/deploy-config.yaml
```

主要配置项：
- `global.architecture`: 系统架构 (x86_64 或 arm64)
- `hosts.control_plane`: 控制平面节点配置
- `hosts.workers`: 工作节点配置
- `packages.kube_version`: Kubernetes 版本
- `networking.dual_stack`: 双栈网络配置

### 4. 验证配置

```bash
./controller.sh --validate-only
```

### 5. 开始部署

```bash
./controller.sh --verbose
```

## 📖 使用指南

### 命令行选项

```bash
./controller.sh [选项]

选项:
    -c, --config FILE         配置文件路径 (默认: config/deploy-config.yaml)
    -v, --verbose             详细输出
    -d, --dry-run            模拟运行，不执行实际操作
    -r, --resume             从失败的步骤继续部署
    -s, --skip STEP          跳过指定步骤 (数字或名称)
    -o, --only STEP          只执行指定步骤 (数字或名称)
    -f, --force              强制重新部署，忽略已有状态
    -p, --parallel           并行执行节点操作 (默认启用)
    --validate-only          仅验证配置文件，不执行部署
    --show-status            显示当前部署状态
    --help                   显示帮助信息
```

### 部署步骤

1. **root-check**: Root 用户权限验证
2. **ssh-keys**: SSH 密钥分发和免密登录
3. **dependencies**: 依赖检查与离线 RPM 安装
4. **k8s-components**: Kubernetes 组件安装
5. **system-config**: 系统参数配置
6. **container-runtime**: 容器运行时安装和配置
7. **registry**: 私有镜像仓库部署
8. **cluster-init**: Kubernetes 集群初始化
9. **controller-config**: kube-controller-manager 参数配置
10. **control-plane**: 控制平面节点添加
11. **worker-nodes**: 工作节点添加
12. **cni-network**: CNI 网络插件安装
13. **nfs-storage**: NFS 存储配置
14. **addons**: 扩展组件部署
15. **backup**: etcd 备份配置

### 状态管理

KubeFoundry 提供完整的状态跟踪和恢复功能：

```bash
# 查看当前部署状态
./controller.sh --show-status

# 从失败步骤继续部署
./controller.sh --resume

# 强制重新部署
./controller.sh --force

# 跳过特定步骤
./controller.sh --skip 7
```

## 🔧 配置示例

### 基本配置

```yaml
global:
  architecture: x86_64
  cluster_name: "my-k8s-cluster"
  k8s_install_dir: "/data"
  media_source: "/data/k8s_install"

hosts:
  control_plane:
    - name: "k8s-master-01"
      ip: "192.168.1.10"
      ipv6: "fd00:100:1::10"
  workers:
    - name: "k8s-worker-01"
      ip: "192.168.1.20"
      ipv6: "fd00:100:1::20"

packages:
  container_runtime: auto  # 根据 K8s 版本自动选择
  kube_version: "1.30.14"

networking:
  dual_stack:
    enabled: true
    ipv4_pod_cidr: "192.168.0.0/16"
    ipv6_pod_cidr: "fd00:100:64::/64"
  cni:
    type: "flannel"
```

### 容器运行时自动选择

- **Kubernetes 1.23.x** → Docker CE
- **Kubernetes 1.30.x** → containerd

## 🏛️ 架构设计

KubeFoundry 采用模块化设计，包含以下核心组件：

- **控制器 (controller.sh)**: 主控脚本，协调整个部署流程
- **执行器 (executor.sh)**: 在远程节点执行具体操作
- **分发器 (distribute.sh)**: 负责离线介质包的分发
- **配置管理**: 统一的配置文件解析和验证
- **状态管理**: 跟踪部署状态，支持中断恢复
- **日志系统**: 结构化日志记录和分析

## 📊 监控和日志

### 日志位置
- 主日志：`/root/.k8s-autodeploy/logs/kubefoundry.log`
- 状态文件：`/root/.k8s-autodeploy/state/deployment-state.json`

### 监控组件
- Prometheus (可选)
- Grafana (可选)
- 自定义健康检查

## 🔒 安全考虑

- 所有敏感信息存储在 `/root/.k8s-autodeploy/creds/` 目录
- SSH 密钥自动管理和轮换
- 日志中过滤敏感信息
- 文件权限严格控制 (600 或 700)

## 🐛 故障排除

### 常见问题

1. **SSH 连接失败**
   - 检查网络连通性
   - 验证 SSH 服务状态
   - 确认防火墙配置

2. **配置文件验证失败**
   - 检查 YAML 语法
   - 验证必需字段
   - 运行 `./scripts/validate-config.sh`

3. **步骤执行失败**
   - 查看详细日志
   - 使用 `--resume` 继续
   - 检查系统资源

### 调试模式

```bash
# 详细输出模式
./controller.sh --verbose

# 模拟运行
./controller.sh --dry-run

# 只执行特定步骤
./controller.sh --only 5
```

## 🤝 贡献指南

1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 推送到分支
5. 创建 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🆘 支持

- 文档：查看 `docs/` 目录下的详细文档
- 问题报告：在 GitHub Issues 中提交问题
- 配置示例：参考 `config/deploy-config.yaml.example`

## 🗺️ 路线图

### 当前版本 (v0.1.0) - 阶段一完成 ✅
- [x] 基础项目结构搭建
- [x] 核心脚本框架开发
- [x] 配置管理系统
- [x] 日志和状态管理机制

### 计划功能 (后续版本)
- [ ] 完整的 15 步部署流程实现
- [ ] 多架构介质包管理
- [ ] Web UI 管理界面
- [ ] 更多 CNI 插件支持
- [ ] 高可用配置支持
- [ ] 完整的测试套件

---

**注意**: 此项目目前处于早期开发阶段 (v0.1.0)，主要关注基础架构和核心功能的实现。生产环境使用请谨慎评估。