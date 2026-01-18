# KubeFoundry

Kubernetes 自动化部署工具 - 基于 Shell 脚本和 YAML 配置的 K8S 集群自动化部署解决方案

## 📖 项目简介

KubeFoundry 是一个功能完整的 Kubernetes 集群自动化部署工具，支持从底层环境准备到应用组件部署的全流程自动化。

### 主要特性

- ✅ **全自动化部署** - 从系统配置到 K8S 集群初始化的完整自动化
- ✅ **灵活配置管理** - 支持 YAML 配置文件，易于定制
- ✅ **高可用架构** - 支持多控制节点和工作节点的高可用部署
- ✅ **双栈网络** - 支持 IPv4/IPv6 双栈网络配置
- ✅ **完整监控栈** - 集成 Prometheus、Grafana、Skywalking、Loki 等监控组件
- ✅ **存储管理** - 支持 NFS 存储和动态存储卷供应
- ✅ **中间件集成** - 内置 Redis 集群、哨兵模式等中间件部署
- ✅ **定时任务** - 自动化 ETCD 备份、日志清理等运维任务

## 📁 项目结构

```
KubeFoundry/
├── README.md                    # 项目说明文档（本文件）
│
├── config/                      # 配置文件目录
│   ├── README.md                # 配置系统使用指南
│   └── config.yaml              # 配置文件（所有参数和默认值）
│
├── doc/                         # 文档目录
│   ├── cmdlist.md               # K8S 安装命令清单（部署流程参考）
│   ├── config-guide.md          # 配置参数详细说明文档
│   └── config-summary.md        # 配置参数提炼总结
│
├── scripts/                     # 部署脚本目录（待开发）
└── logs/                        # 日志目录
```

## 📚 文档说明

### 核心文档

| 文档 | 作用 |
|------|------|
| **README.md** | 项目主说明文档 |
| **doc/cmdlist.md** | K8S 安装命令清单，部署流程的权威参考 |

### 配置文档

| 文档 | 作用 |
|------|------|
| **config/README.md** | 配置系统总览和快速开始指南 |
| **doc/config-guide.md** | 20 个配置模块、100+ 参数的详细说明 |
| **doc/config-summary.md** | 参数提炼来源、分类统计和映射关系 |

### 配置文件

| 文件 | 作用 |
|------|------|
| **config/config.yaml** | 配置文件模板，包含所有参数和默认值 |

## 🚀 快速开始

### 1. 准备配置文件

```bash
# 复制配置模板
cp config/config.yaml my-config.yaml

# 编辑配置文件，修改必需参数
vi my-config.yaml
```

### 2. 修改必需参数

编辑配置文件，至少修改：
- `server.network_interface` - 网卡名称
- `registry.server` - 镜像仓库地址
- `nfs.server` - NFS 服务器地址

### 3. 执行部署

```bash
./scripts/deploy.sh --config my-config.yaml
```

### 4. 验证部署

```bash
kubectl get nodes
kubectl get pods -A
```

## 🎯 必需配置参数

| 参数 | 路径 | 说明 |
|------|------|------|
| 网卡名称 | `server.network_interface` | 主网卡接口 |
| 镜像仓库 | `registry.server` | Docker Registry 地址 |
| NFS 服务器 | `nfs.server` | NFS 服务器 IP |

## 🔧 部署流程

1. **基础环境准备** - YUM 源、SSH 免密、网络配置
2. **容器运行时安装** - Containerd、镜像仓库、CNI 插件
3. **K8S 集群部署** - 控制平面、工作节点、网络插件
4. **管理平台安装** - Kubemate、NFS 存储
5. **监控组件安装** - ES、Skywalking、Loki、Prometheus、Traefik
6. **中间件安装** - Redis 集群/哨兵
7. **运维配置** - 定时任务、用户权限、F5 高可用

详细步骤请参考 [doc/cmdlist.md](doc/cmdlist.md)

## 🛠️ 技术栈

- **容器运行时**: Containerd 1.7.18
- **Kubernetes**: 1.28.0+
- **网络插件**: Flannel
- **监控**: Prometheus + Grafana
- **日志**: Loki + Promtail
- **链路追踪**: Skywalking + Elasticsearch
- **Ingress**: Traefik
- **存储**: NFS + NFS Provisioner
- **中间件**: Redis Cluster/Sentinel

## 📋 配置模块

20 个配置模块涵盖：服务器规划、K8S 版本、YUM 源、网络、Containerd、镜像仓库、NFS 存储、数据路径、CNI 插件、Kubemate、监控、Redis、证书、系统、用户、F5、定时任务、部署选项、Helm、日志。

详见 [doc/config-guide.md](doc/config-guide.md)

## 🔍 常见问题

### Q: 最少需要几台服务器？
- **最小配置**: 1 控制节点 + 1 工作节点（测试用）
- **推荐配置**: 3 控制节点 + 3 工作节点（生产用）

### Q: 必须使用 NFS 吗？
不是必须的。设置 `nfs.provisioner.enabled: false` 即可使用其他存储方案。

更多问题请查看 [config/README.md](config/README.md)

## 📞 支持和贡献

- 📖 查看文档目录下的相关文档
- 🐛 提交 Issue 描述问题
- 💬 在 Discussions 中提问

---

**版本**: 1.0.0 | **状态**: 🚧 开发中
