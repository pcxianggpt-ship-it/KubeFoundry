# CLAUDE.md

此文件为 Claude Code (claude.ai/code) 在此代码仓库中工作时提供指导。

## 项目概述

KubeFoundry 是一个 Kubernetes 离线部署自动化系统，专为在隔离网络环境中部署 Kubernetes 集群而设计。系统采用控制节点-代理节点架构，通过 SSH 协调多个目标节点的部署工作。

## 核心架构

### 系统组件
- **控制器** (`controller.sh`): 主要协调脚本，负责部署编排
- **执行器** (`executor.sh`): 节点级远程操作执行脚本
- **分发器** (`distribute.sh`): 离线包介质分发工具
- **配置管理** (`deploy-config.yaml`): 集中式 YAML 配置管理

### 部署流程
系统执行 15 步部署流水线：
1. Root 用户权限验证
2. SSH 密钥分发
3. 依赖安装（离线 RPM 包）
4. Kubernetes 组件安装
5. 系统参数配置
6. 容器运行时设置（Docker/containerd）
7. 私有镜像仓库部署
8. Kubernetes 集群初始化
9. **kube-controller-manager 参数配置** 🆕
10. 控制平面节点添加
11. 工作节点添加
12. CNI 网络插件安装（Flannel）
13. NFS 存储提供器设置
14. 定制化组件部署（Traefik、Prometheus、Redis）
15. etcd 备份配置

## 开发命令

**注意：此项目处于早期开发阶段 - 构建命令尚未建立**

### 测试
```bash
# 单元测试（待实现）
./test/unit/run-tests.sh

# 集成测试（待实现）
./test/integration/run-deployment-tests.sh

# 配置验证（待实现）
./scripts/validate-config.sh deploy-config.yaml
```

### 开发工具
```bash
# 配置验证（待实现）
./scripts/validate-config.sh

# 代码检查和格式化（待实现）
./scripts/lint.sh
./scripts/format.sh

# 开发环境设置（待实现）
./scripts/setup-dev.sh
```

## 配置管理

### 主配置文件
- **位置**: `deploy-config.yaml`
- **格式**: YAML 结构化配置，包含主机、包、组件等信息
- **验证**: 部署前必须验证

### 关键配置节
- `global`: 路径、时区、SSH 设置
- `hosts`: 控制平面和工作节点清单
- `packages`: Kubernetes 组件版本
- `registry`: 私有容器镜像仓库设置
- `storage`: NFS 和存储配置
- `controller`: 🆕 控制器组件配置参数
- `addons`: 定制化组件（Traefik、监控等）
- `backup`: etcd 备份和保留策略

## 代码结构和模式

### 脚本组织
- 模块化设计，单一职责函数
- 完善的错误处理和回滚机制
- 通过 `/root/.k8s-autodeploy/state/` 文件进行状态跟踪
- 结构化日志记录，包含时间戳和状态码
- 幂等操作，具备适当的验证机制

### 安全要求
- 凭证存储在 `/root/.k8s-autodeploy/creds/`，权限 600
- 日志中不包含敏感数据
- SSH 密钥管理和令牌轮换
- 所有配置文件的安全文件权限

### 目标环境
- **操作系统**: RHEL/CentOS/AlmaLinux/Oracle Linux 8+
- **Kubernetes**: 版本 1.23 和 1.30
- **架构**: x86_64
- **网络**: 隔离网络/离线部署能力

## 开发指南

### 脚本开发
- 使用 Bash 4.4+，启用严格错误处理（`set -euo pipefail`）
- 实现全面的参数验证
- 使用带时间戳和状态级别的结构化日志
- 遵循幂等执行的状态管理模式
- 为所有关键操作包含回滚机制

### 错误处理
- 实现适当的退出码（0=成功，非零=失败）
- 在支持的地方使用 try/catch 模式
- 提供有意义的错误消息和上下文信息
- 记录所有操作用于调试和审计

### 测试策略
- 针对单个脚本函数的单元测试
- 部署流水线的集成测试
- 离线测试的模拟环境
- 配置验证测试

## 重要文件和位置

### 核心脚本
- `controller.sh`: 主要编排控制器
- `executor.sh`: 远程节点执行脚本
- `distribute.sh`: 介质分发工具

### 配置
- `deploy-config.yaml.example`: 配置模板
- `manifest.json`: 包和镜像清单

### 工具
- `etcd-backup.sh`: etcd 备份和恢复工具
- `scripts/`: 开发和实用脚本
- `test/`: 测试套件和验证工具

### 状态和凭证
- `/root/.k8s-autodeploy/state/`: 部署状态跟踪
- `/root/.k8s-autodeploy/creds/`: 安全凭证存储
- `/tmp/k8s-autodeploy/`: 临时工作文件

## 性能和可扩展性

### 目标
- 30 分钟内部署 50+ 节点
- 跨节点并行执行
- 全面的验证和错误恢复
- 资源优化，最小化系统影响

### 优化考虑
- 尽可能使用批量操作
- 并行节点部署
- 高效的包分发
- 进度报告和监控

## 新增步骤详细说明

### 第9步：kube-controller-manager 参数配置

#### 功能描述
在集群初始化完成后，但在添加其他控制平面节点之前，配置 kube-controller-manager 的自定义启动参数。

#### 执行内容
1. **备份原配置**：保存 `/etc/kubernetes/manifests/kube-controller-manager.yaml`
2. **修改 Pod 清单**：添加'- --cluster-signing-duration=867240h0m0s'参数到 `spec.containers.spec.command`
3. **重启 Pod**：kubelet 会自动重启以应用新配置
4. **验证生效**：检查 Pod 状态和参数加载情况


#### 验证方法
```bash
# 检查 Pod 状态
kubectl get pods -n kube-system -l component=kube-controller-manager

# 查看启动参数
kubectl describe pod kube-controller-master -n kube-system

# 检查日志确认参数生效
kubectl logs kube-controller-master -n kube-system
```

## 故障排除

### 常见问题
- SSH 连接问题
- 包依赖冲突
- 网络配置问题
- 系统资源不足
- **kube-controller-manager 参数配置失败** 🆕

### 调试
- 检查 `/root/.k8s-autodeploy/logs/` 中的日志
- 使用 `scripts/validate-config.sh` 验证配置
- 验证 SSH 连接和权限
- 检查系统需求和依赖
- **验证控制器 Pod 状态和启动参数** 🆕

## 未来开发

此项目目前处于早期开发阶段。以下领域需要实现：
- 核心脚本开发
- 配置验证系统
- 测试框架
- 开发环境设置
- CI/CD 流水线
- 文档和指南