# KubeFoundry

K8S 集群一键安装工具，支持通过网页流水线完成高可用集群部署。

Web Wizard v0.3.2 使用 Java 17、Spring Boot、H2 和 Vue 3，提供独立的“集群配置”和“集群安装”模块，复用 Bash step 脚本完成节点免密、预检查、Kubernetes 基础安装、Kubemate 组件安装、远程重置、实时日志与失败定位。目标服务器使用包内 Java 运行时，不要求安装 Java、Python、Node.js 或 `sshpass`。

## 功能特性

- ✅ 一键部署 K8S 高可用集群（多控制节点 + 多工作节点）
- ✅ 自动化环境配置（DNS、网络、主机名、内核参数等）
- ✅ 支持 IPv6 双栈网络
- ✅ 100 年证书有效期
- ✅ 集成 CNI 插件（Flannel）
- ✅ 模块化设计，易于维护和扩展
- ✅ 详细的日志输出和错误处理
- ✅ 支持回滚操作

## 系统要求

### 管理节点要求
- 操作系统：Linux（推荐 CentOS 7+ 或 RHEL 7+）
- 必需工具：ssh, scp, yq, jq, bc
- 网络连接：能够 SSH 连接到所有 K8S 节点

### K8S 节点要求
- 操作系统：CentOS 7+ 或 RHEL 7+
- CPU：2 核心以上
- 内存：4GB 以上（推荐 8GB）
- 磁盘：40GB 以上
- 网络：节点之间网络互通

## 快速开始

### Web 离线生产部署

在可联网的构建机上执行：

```bash
KF_TARGET_ARCH=x86_64 KF_JAVA_HOME=/opt/jdk-17 bash package.sh
# x86_64 主机交叉构建 ARM64，目标 JDK 必须是真实 ARM64 JDK 17
KF_TARGET_ARCH=aarch64 KF_JAVA_HOME=/opt/jdk-17-x86_64 \
  KF_TARGET_JDK_HOME=/opt/jdk-17-aarch64 bash package.sh
```

脚本会运行 Java 与前端测试、构建 JAR，并通过 `jlink` 生成当前架构的精简 Java 17 运行时：

```text
dist/kubefoundry-web-v0.3.2-x86_64.tar.gz
dist/kubefoundry-web-v0.3.2-aarch64.tar.gz
```

将匹配服务器架构的压缩包复制到目标 Linux 服务器，在计划安装目录中执行：

```bash
tar -xzf kubefoundry-web-v0.3.2-x86_64.tar.gz
cp kubefoundry-web-v0.3.2-x86_64/deploy.sh .
sudo bash deploy.sh kubefoundry-web-v0.3.2-x86_64.tar.gz
```

也可以把发布包内的 `deploy.sh` 与压缩包放到独立部署目录后执行。服务默认监听 `10001`，程序位于当前目录的 `app`，双架构 Helm 位于 `tools/helm-amd` 与 `tools/helm-arm`，H2 数据、主密钥和任务数据位于 `data`，日志位于 `logs`。组件 Chart、YAML 和 Kubernetes 离线介质位于独立维护的 `kube-media`；发布包不会携带或覆盖该目录，重复部署会保留 `kube-media`、`data` 和 `logs`。完整说明见 [v0.3.0 部署手册](doc/v0.3.0/部署手册.md)。

### Web Wizard

后端开发环境要求 JDK 17 和 Maven：

```bash
cd web/backend-java
mvn spring-boot:run
```

前端要求 Node.js 18+：

```bash
cd web/frontend
npm ci
npm run dev
```

v0.3.2 节点配置页录入密码并加密保存；节点可同时承担 Registry 与控制节点或工作节点角色。“测试全部节点”由 Java SSH 实现首次连接、分发 Ed25519 公钥并验证免密。后续预检查、安装和重置使用集群私钥，不依赖系统 `sshpass`。安装介质必须位于管理端的 `${APP_DIR}/kube-media`；Helm 由运行时按目标节点架构从 `${APP_DIR}/tools` 分发至主控制节点后执行。

### 操作入口

从 v0.3.2 起仅支持 Web Wizard，不再提供 `scripts/main.sh` 命令行安装入口。完成部署后，在浏览器访问 `http://<管理节点IP>:10001`，按“集群配置 → 节点测试 → 集群安装”流程操作。首次连接、密钥分发、安装续跑和集群重置均由 Java 服务统一编排。

### 验证安装

```bash
# 在 k8sc1 控制节点执行
export KUBECONFIG=/etc/kubernetes/admin.conf

# 检查节点状态
kubectl get nodes

# 检查 Pod 状态
kubectl get pods -A
```

## 使用说明

安装参数在 Web 集群配置页维护，安装任务由后端计划工厂生成。Bash 文件是后端调用的内部步骤实现，不作为独立 CLI 接口提供兼容性承诺。

### 步骤列表

#### 阶段 1：前置检查与准备
- **2.1** 初始化参数配置
- **2.2** 检查配置文件完整性
- **2.3** 检查必要工具安装

#### 阶段 2：安装 K8S 底座
- **3.1** 配置本地 yum 源
- **3.3** 配置本地 k8s repo 源客户端
- **3.4** 安装 K8s 依赖包
- **3.5** 替换 kubeadm 为 100 年证书版本
- **3.6.1** 修改 DNS
- **3.6.2** 修改网络配置（IPv6）
- **3.6.3** 修改主机名
- **3.6.4** 修改 open files 参数
- **3.6.5** 配置环境变量
- **3.7** 安装 containerd
- **3.8** 安装镜像仓库
- **3.9.1** 初始化 K8S 集群
- **3.9.2** 修改证书有效期
- **3.9.3** 添加 K8S 控制节点
- **3.9.4** 添加 K8S 工作节点
- **3.9.5** 安装 CNI 插件-Flannel

### 查看日志

在 Web 安装进度页查看阶段、步骤状态及实时日志；服务端日志保存在部署目录的 `logs` 中。

## 回滚操作

如果安装失败，可在 Web 安装进度页续跑失败任务；需要重新安装时，在 Web 中执行集群重置。

**注意：** 回滚操作将删除已安装的组件和数据，请谨慎操作。

## 配置文件说明

配置文件 `config/cluster.yaml` 包含以下主要部分：

### 集群基本信息
```yaml
cluster:
  name: "k8s-cluster"
  k8s_version: "1.30.14"
  pod_subnet: "10.244.0.0/16"
  service_subnet: "10.96.0.0/16"
```

### 节点配置
```yaml
control_plane:
  - hostname: "k8sc1"
    ip: "10.3.66.18"
    ipv6: "fd00:42::18"
```

### 网络配置
```yaml
network:
  gateway: "10.3.66.1"
  ipv6_gateway: "fd00::1"
```

Kubernetes API Server 端口固定为 `6443`，不提供配置项。

### 路径配置
```yaml
paths:
  k8s_install: "/data/k8s_install"
  repo_source: "/data/repo/rhel7-k8s-repo.tar.gz"
  kubeadm_100y: "/data/k8s_install/01.rpm_package/kubeadm-1.30.14-100y-amd64"
  container_runtime: "/data/k8s_install/02.container_runtime"
```

## 项目结构

```
KubeFoundry/
├── config/
│   └── cluster.yaml                 # 集群配置文件
├── doc/
│   ├── cmdlist.md                   # 原始命令清单
│   ├── design.md                    # 设计文档
│   ├── api.md                       # 接口文档
│   ├── steps_execution_guide.md     # 步骤执行指南
│   └── v0.3.2/                      # 当前版本设计与验收文档
├── scripts/
│   ├── lib/                         # 公共函数库
│   │   ├── logger.sh                # 日志函数
│   │   ├── config.sh                # 配置解析
│   │   ├── ssh.sh                  # SSH/SCP 操作
│   │   ├── exec.sh                  # 批量执行（命令）
│   │   ├── exec_script.sh           # 批量执行（脚本）
│   │   ├── rollback.sh              # 回滚操作
│   │   └── validator.sh            # 验证函数
│   ├── steps/                       # 步骤脚本
│   │   ├── 02_precheck/            # 前置检查
│   │   └── 03_k8s_base/            # K8S 底座安装
│   ├── rollback/                    # 回滚脚本
│   └── verify/                      # 验证脚本（预留）
└── templates/                        # 模板文件
```

## 常见问题

### Q1: SSH 连接失败怎么办？

**A:** 请检查以下项目：
1. 节点是否启动
2. SSH 服务是否运行：`systemctl status sshd`
3. 网络连通性：`ping <node_ip>`
4. SSH 密钥是否配置：`ssh-copy-id root@<node_ip>`

### Q2: 安装失败后如何重新安装？

**A:** 在 Web 安装进度页续跑失败任务；如需从头安装，先在 Web 中执行集群重置，再重新发起安装。

### Q3: 如何支持不同版本的 K8S？

**A:** 修改配置文件中的 `k8s_version`：
```yaml
cluster:
  k8s_version: "1.30.14"  # Web Wizard v0.3.2 当前固定版本
```

### Q4: 节点状态一直 NotReady 怎么办？

**A:** 检查以下几点：
1. CNI 插件是否安装：`kubectl get pods -n kube-flannel`
2. 防火墙是否关闭：`systemctl status firewalld`
3. 网络是否互通：`ping <node_ip>`
4. 查看节点详细信息：`kubectl describe node <node_name>`

## 开发指南

### 代码规范
- 所有脚本使用 LF 换行符
- 使用统一的日志函数（log_info, log_success, log_warn, log_error）
- 函数命名使用小写加下划线（如 `init_params`）
- 变量命名使用小写加下划线（如 `local node_ip`）
- 所有函数必须返回退出码（0 成功，非 0 失败）

### 添加新步骤
1. 在对应的章节目录创建脚本文件
2. 定义函数（不包含 main 函数）
3. 在后端安装计划工厂中注册步骤和对应 verify 脚本
4. 更新文档

## 文档

- [设计文档](doc/design.md) - 整体架构和流程设计
- [接口文档](doc/api.md) - 公共函数接口定义
- [命令清单](doc/cmdlist.md) - 手动安装命令参考
- [步骤执行指南](doc/steps_execution_guide.md) - 各步骤服务器执行清单

## 版本历史

### v1.1.0 (2026-03-23)
- ✨ 新增服务器分组管理功能
- ✨ 新增执行进度显示功能
- ✨ 新增服务器状态预检功能
- ✨ 优化日志输出，标注执行服务器信息
- 📝 新增步骤执行指南文档（steps_execution_guide.md）
- 📝 新增主脚本分析文档（main_script_analysis.md）
- 🐛 修复多个节点执行时缺少服务器信息的问题

### v1.0.0 (2026-03-22)
- 初始版本
- 支持 K8S 高可用集群部署
- 支持多控制节点和多工作节点
- 支持回滚操作

## 许可证

MIT License

## 联系方式

- 项目地址：https://github.com/yourusername/KubeFoundry
- 问题反馈：https://github.com/yourusername/KubeFoundry/issues

---

**KubeFoundry Team**
