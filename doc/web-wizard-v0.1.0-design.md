# KubeFoundry Web Wizard v0.1.0 设计文档

## 1. 版本目标

v0.1.0 的目标是提供一个基于 Python3 + SQLite 的网页向导安装 MVP，让用户可以通过浏览器完成 Kubernetes 集群安装的主要闭环。

本版本不把现有 Bash 脚本推倒重写，而是把 `main.sh` 中的主流程控制逐步迁移到 Python 后端：

```text
Web 向导
  -> Python 后端 API
  -> SQLite 配置与任务状态
  -> Python Installer Orchestrator
  -> SSH/SCP
  -> scripts/steps/* 单步骤 Bash 脚本
```

v0.1.0 的一句话定义：

```text
使用 Python3 后端替代 main.sh 的安装编排职责，复用现有 Bash step 脚本完成一次可视化、可跟踪、可审计的 Kubernetes 集群安装。
```

## 2. MVP 范围

### 2.1 包含范围

1. 提供网页向导入口，支持创建和编辑集群安装配置。
2. 使用 SQLite 保存集群配置、节点配置、SSH 凭据引用、预检查结果、安装任务、步骤状态和配置快照。
3. Python 后端读取 SQLite 配置，生成任务级 `cluster.yaml` 和 JSON 快照。
4. Python 编排器替代 `scripts/main.sh` 的主流程控制。
5. Python 通过 SSH/SCP 在目标节点执行现有 `scripts/steps/` 下的 Bash 脚本。
6. Python 统一生成 `runtime.env`，让远端脚本从标准环境变量读取配置。
7. 支持基础预检查，包括 SSH 连通性、权限、系统版本、CPU、内存、磁盘、swap、hostname、端口占用。
8. 支持安装任务进度展示、节点级步骤状态展示、实时日志查看。
9. 保留 `cluster.yaml` 作为 CLI 兼容格式和任务审计产物。

### 2.2 不包含范围

1. 用户登录、RBAC、多租户。
2. 多集群长期运维控制台。
3. Kubernetes 升级、扩容、缩容。
4. 完整回滚编排。
5. 离线包管理 UI。
6. 组件市场。
7. 高可用后端和分布式任务队列。
8. 大规模重写现有 Bash step 脚本。

## 3. 技术选型

### 3.1 后端

后端使用 Python3，优先考虑信创系统和国产操作系统的部署便利性。

建议要求：

```text
Python >= 3.7
Flask
SQLite
PyYAML
```

SSH/SCP 执行方式建议分阶段：

```text
v0.1.0: 优先调用系统 ssh/scp 命令，贴近现有实现，减少 Python 第三方依赖。
后续版本: 可选引入 Paramiko，以支持密码认证、连接池和更细粒度的执行控制。
```

说明：

```text
v0.1.0 需要兼容 Python 3.7，默认不使用 FastAPI、Pydantic v2、SQLAlchemy 新版本和 Python 3.8+ 类型语法。
后端实现应避免 list[str]、dict[str, str]、str | None 等语法，统一使用 typing.List、typing.Dict、typing.Optional。
SQLite 操作优先使用标准库 sqlite3，降低信创系统和离线环境的部署复杂度。
```

### 3.2 前端

前端建议使用 Vue 3 + Element Plus，原因是表单、步骤条、表格、日志视图和状态标签都比较贴合运维向导场景。

v0.1.0 前端重点不是视觉复杂度，而是安装流程清晰、配置校验明确、失败定位直观。

### 3.3 数据库

v0.1.0 使用 SQLite。SQLite 的定位是：

```text
当前配置中心
任务状态库
历史安装快照索引
预检查结果库
```

`cluster.yaml` 不再是 Web 模式的唯一配置源，而是导入导出格式和任务执行快照。

## 4. 推荐目录结构

```text
KubeFoundry/
├── web/
│   ├── backend/
│   │   ├── app.py
│   │   ├── requirements.txt
│   │   └── kubefoundry/
│   │       ├── api/
│   │       ├── config/
│   │       ├── installer/
│   │       │   ├── context.py
│   │       │   ├── plan.py
│   │       │   ├── runner.py
│   │       │   └── ssh.py
│   │       ├── store/
│   │       └── logs/
│   └── frontend/
├── scripts/
│   ├── steps/
│   ├── verify/
│   └── lib/
├── config/
├── data/
│   ├── kubefoundry.db
│   └── jobs/
└── logs/
```

## 5. SQLite 数据范围

### 5.1 集群表 clusters

保存集群基础配置。

```text
id
name
description
k8s_version
pod_subnet
service_subnet
api_server_port
registry_hostname
registry_ip
registry_port
install_mode
status
created_at
updated_at
```

### 5.2 节点表 nodes

保存控制节点、工作节点和镜像仓库节点信息。

```text
id
cluster_id
hostname
ip
ipv6
role              # control_plane / worker / registry
ssh_port
ssh_user
os_type
arch
status
created_at
updated_at
```

### 5.3 SSH 凭据表 ssh_credentials

MVP 阶段不建议明文长期保存密码。

```text
id
cluster_id
auth_type         # key / password
username
private_key_path
password_encrypted
sudo_password_encrypted
created_at
updated_at
```

推荐策略：

```text
私钥路径可以持久化。
密码只在任务运行期间保存在内存，确需持久化时必须加密。
```

### 5.4 路径和系统设置 settings

保存全局默认值和安装介质路径。

```text
key
value
updated_at
```

示例：

```text
default_install_media
default_k8s_home
default_arch
default_log_retention_days
```

### 5.5 安装任务表 jobs

每次预检查或安装都创建任务。

```text
id
cluster_id
job_type          # precheck / install
status            # pending / running / success / failed / canceled
current_step_key
config_snapshot
config_yaml_path
log_dir
created_at
started_at
finished_at
```

`config_snapshot` 保存任务创建时的完整 JSON 配置，保证历史任务不受后续配置修改影响。

### 5.6 步骤状态表 job_steps

保存任务级步骤状态。

```text
id
job_id
step_key
step_name
phase
target_scope
status
started_at
finished_at
exit_code
message
```

### 5.7 节点级步骤状态表 job_step_nodes

保存每个步骤在每个节点上的执行结果。

```text
id
job_step_id
node_id
status
started_at
finished_at
exit_code
log_path
message
```

### 5.8 预检查结果表 precheck_results

保存节点级预检查项。

```text
id
cluster_id
job_id
node_id
check_key
check_name
severity          # info / warning / error
status            # pass / warning / fail
message
detail
created_at
```

## 6. 配置流转

Web 模式下以 SQLite 为当前配置源。

```text
用户填写网页表单
  -> 写入 SQLite
  -> 点击预检查或安装
  -> Python 读取 SQLite，构造 ClusterContext
  -> 保存 jobs.config_snapshot
  -> 写入 data/jobs/{job_id}/config_snapshot.json
  -> 生成 data/jobs/{job_id}/cluster.yaml
  -> Python 编排器基于 ClusterContext 执行
```

`config/cluster.yaml` 的定位调整为：

```text
CLI 模式默认配置文件
Web 配置导入来源
Web 配置导出目标
```

任务执行时使用：

```text
data/jobs/{job_id}/cluster.yaml
```

## 7. Python 全局上下文

Python 后端统一管理配置，不再让每个 Shell 脚本自行解析 YAML。

建议核心对象：

```text
ClusterContext
- cluster
- nodes
- registry
- network
- ssh
- paths
- storage
- advanced
- ecosystem
```

每个节点执行前生成运行时变量文件：

```text
/tmp/kubefoundry/runtime.env
```

示例：

```bash
export KF_CLUSTER_NAME="k8s-cluster"
export KF_K8S_VERSION="1.30.14"
export KF_POD_SUBNET="10.244.0.0/16"
export KF_SERVICE_SUBNET="10.96.0.0/16"
export KF_API_SERVER_PORT="6443"
export KF_NODE_HOSTNAME="k8sc1"
export KF_NODE_IP="192.168.123.130"
export KF_NODE_ROLE="control_plane"
export KF_REGISTRY_HOSTNAME="registry"
export KF_REGISTRY_IP="192.168.123.130"
export KF_REGISTRY_PORT="5000"
export KF_K8S_HOME="/data/k8s_install"
export KF_INSTALL_MEDIA="/root/kube-media"
export KF_ARCH="amd64"
export KF_KUBELET_ROOT="/data/k8s_install/kubelet_root"
export KF_ETCD_DATA_DIR="/data/k8s_install/etcd_backup"
```

为兼容现有脚本，v0.1.0 可以同时导出旧变量名：

```bash
export K8S_VERSION="${KF_K8S_VERSION}"
export POD_SUBNET="${KF_POD_SUBNET}"
export SERVICE_SUBNET="${KF_SERVICE_SUBNET}"
export API_SERVER_PORT="${KF_API_SERVER_PORT}"
export REGISTRY_IP="${KF_REGISTRY_IP}"
export REGISTRY_HOSTNAME="${KF_REGISTRY_HOSTNAME}"
export K8S_HOME="${KF_K8S_HOME}"
export K8S_SOFT="${KF_K8S_HOME}"
export ARCH="${KF_ARCH}"
export KUBELET_ROOT="${KF_KUBELET_ROOT}"
export ETCD_DATA_DIR="${KF_ETCD_DATA_DIR}"
```

## 8. Python 编排器职责

Python 编排器取代 `main.sh` 中的这些职责：

1. 解析执行范围，例如 precheck、k8s_base、ecosystem、all。
2. 根据配置生成安装计划。
3. 判断步骤是否启用，例如生态组件是否安装。
4. 判断目标节点范围，例如 all、control_plane、workers、registry、primary_control_plane、other_control_planes。
5. 分发安装介质、脚本和 `runtime.env`。
6. 执行远端脚本并收集 stdout、stderr、退出码。
7. 更新 `jobs`、`job_steps`、`job_step_nodes` 状态。
8. 保存节点级日志文件。
9. 失败时停止后续关键步骤，并给出失败节点和失败步骤。

Bash step 脚本保留这些职责：

1. 执行节点上的具体系统命令。
2. 修改系统配置。
3. 启停服务。
4. 做本步骤内的局部校验。
5. 返回明确退出码。

## 9. 安装计划 Step Plan

v0.1.0 先覆盖核心安装闭环，计划从现有 `main.sh` 和 `doc/steps-reference.md` 提取。

### 9.1 Phase 1: precheck

```text
02-init-config
03-validate-config
web-precheck-ssh
web-precheck-node-env
```

说明：

```text
02-init-config 和 03-validate-config 可先保留为本地兼容校验。
SSH、系统资源、swap、端口等检查由 Python 直接执行远端命令并写入 precheck_results。
```

### 9.2 Phase 2: k8s_base

```text
10-setup-yum-source          local
11-setup-ssh-login           local, optional
11b-setup-hostname           local or all nodes, keep current behavior first
12-setup-k8s-repo            workers + non-primary control planes
13-install-k8s-deps          all k8s nodes
14-replace-kubeadm           primary_control_plane
15-environment-config        all nodes
16-install-containerd        all nodes
17-install-registry          registry
18-init-k8s-cluster          primary_control_plane
19-modify-cert-expiry        primary_control_plane
20-add-control-nodes         other_control_planes, sequential
21-add-worker-nodes          workers
22-install-cni-flannel       primary_control_plane
```

### 9.3 Phase 3: ecosystem

v0.1.0 可以先支持已有配置中最常见的基础组件开关，其他组件保留计划但可暂不在向导中展开高级配置。

```text
30-create-namespace          primary_control_plane
31-install-kubemate-ui       primary_control_plane, if enabled
32-install-nfs               primary_control_plane + workers helper, if enabled
36-install-traefik           primary_control_plane, if enabled
38-install-prometheus        primary_control_plane, if enabled
39-update-coredns            primary_control_plane, if enabled
40-install-metrics-server    primary_control_plane, if enabled
41-setup-kubectl-permission  primary_control_plane, if enabled
```

其余生态步骤可以在 v0.1.0 的后端计划中保留枚举，但前端默认隐藏到高级选项。

## 10. 执行模型

### 10.1 远端脚本执行方式

建议 v0.1.0 采用“分发后执行”的方式，减少复杂注入逻辑：

```text
1. Python 创建 /tmp/kubefoundry/{job_id}/
2. SCP runtime.env 到远端目录
3. SCP 当前 step 脚本到远端目录
4. 远端执行 bash -lc 'source runtime.env && bash step.sh'
5. Python 捕获输出并写入本地日志
```

后续可以选择继续支持现有 `ssh "bash -s" < script` 管道模式，但 Web 编排器优先使用显式文件，便于排查现场。

### 10.2 日志路径

本地日志：

```text
data/jobs/{job_id}/logs/job.log
data/jobs/{job_id}/logs/{step_key}.log
data/jobs/{job_id}/logs/{step_key}/{node_hostname}.log
```

远端临时目录：

```text
/tmp/kubefoundry/{job_id}/
```

### 10.3 实时日志

v0.1.0 建议使用 SSE：

```text
GET /api/jobs/{job_id}/events
```

事件类型：

```text
job.status
step.status
node.status
log.line
precheck.result
```

### 10.4 并发执行模型

部分步骤天然适合在多个节点上并发执行，例如安装依赖、环境配置、安装 containerd、工作节点 join、部分验证脚本。Python 编排器需要支持节点级并发，以缩短整体安装时间。

v0.1.0 建议使用 Python 标准库 `concurrent.futures.ThreadPoolExecutor`，避免引入额外任务队列依赖，并保持 Python 3.7 兼容。

步骤计划中增加并发控制字段：

```text
concurrency:
  mode: serial | parallel
  max_workers: 1 | N
  fail_fast: true | false
```

执行原则：

```text
1. 步骤之间默认串行，保证安装依赖顺序清晰。
2. 同一步骤内部可以按节点并发。
3. 对全节点无强顺序要求的步骤使用 parallel。
4. 对控制面 join、集群初始化、证书修改等强顺序步骤使用 serial。
5. 单个节点失败时，当前步骤标记 failed；是否继续等待其他并发节点由 fail_fast 控制。
6. 每个节点必须独立记录 stdout、stderr、exit_code、started_at、finished_at。
```

适合并发的步骤：

```text
12-setup-k8s-repo
13-install-k8s-deps
15-environment-config
16-install-containerd
21-add-worker-nodes
部分 verify 脚本
```

必须串行或谨慎并发的步骤：

```text
10-setup-yum-source          local serial
14-replace-kubeadm           primary_control_plane serial
17-install-registry          registry serial
18-init-k8s-cluster          primary_control_plane serial
19-modify-cert-expiry        primary_control_plane serial
20-add-control-nodes         other_control_planes serial, sequential
22-install-cni-flannel       primary_control_plane serial
Phase 3 中依赖 Kubernetes API 的组件安装默认 serial
```

示例 Step Plan：

```text
Step(
  key="16-install-containerd",
  name="安装 containerd",
  target_scope="all_nodes",
  script="scripts/steps/phase2_k8s_base/16-install-containerd.sh",
  mode="parallel",
  max_workers=5,
  fail_fast=false
)
```

并发执行时，日志不能混写到一个文件里。推荐同时维护：

```text
data/jobs/{job_id}/logs/16-install-containerd.log
data/jobs/{job_id}/logs/16-install-containerd/k8sc1.log
data/jobs/{job_id}/logs/16-install-containerd/k8sw1.log
```

总日志只记录事件摘要，节点日志记录完整命令输出。前端实时日志可以按“全部日志”和“节点日志”两个视图展示。

## 11. API 草案

```text
GET    /api/clusters
POST   /api/clusters
GET    /api/clusters/{cluster_id}
PUT    /api/clusters/{cluster_id}
DELETE /api/clusters/{cluster_id}

GET    /api/clusters/{cluster_id}/nodes
POST   /api/clusters/{cluster_id}/nodes
PUT    /api/nodes/{node_id}
DELETE /api/nodes/{node_id}

POST   /api/clusters/{cluster_id}/precheck
POST   /api/clusters/{cluster_id}/install

GET    /api/jobs/{job_id}
GET    /api/jobs/{job_id}/steps
GET    /api/jobs/{job_id}/logs
GET    /api/jobs/{job_id}/events

GET    /api/jobs/{job_id}/config-yaml
GET    /api/jobs/{job_id}/config-snapshot
```

## 12. Web 向导页面

v0.1.0 页面建议：

```text
1. 集群基础配置
2. 节点配置
3. SSH 配置
4. 路径和安装介质配置
5. 生态组件选择
6. 环境预检查
7. 配置确认
8. 安装执行
9. 安装结果
```

安装执行页至少展示：

```text
任务状态
当前步骤
步骤列表
节点级状态
实时日志
失败步骤和失败节点
```

## 13. 对现有脚本的改造原则

v0.1.0 只做必要改造：

1. 所有新增或修改文件必须使用 LF 换行。
2. Bash step 脚本支持读取 `/tmp/kubefoundry/runtime.env` 或当前目录下的 `runtime.env`。
3. 新变量统一使用 `KF_` 前缀，兼容旧变量名。
4. step 脚本必须返回明确退出码。
5. step 脚本继续使用 `log_info`、`log_success`、`log_warn`、`log_error`。
6. 复杂的节点选择、步骤跳过、重试、状态保存从 Bash 迁到 Python。

不建议在 v0.1.0 中一次性清理所有旧变量和旧传参方式。应先保证 Python 编排闭环跑通，再逐步瘦身 Shell。

## 14. 验收标准

v0.1.0 完成后，应满足：

1. 可以通过网页创建集群配置。
2. 可以添加控制节点、工作节点和镜像仓库节点。
3. 配置保存到 SQLite。
4. 可以执行预检查并展示节点级结果。
5. 可以创建安装任务。
6. 每个安装任务生成 `config_snapshot.json` 和 `cluster.yaml`。
7. Python 编排器可以按 Step Plan 执行多个步骤。
8. 后端可以记录任务状态、步骤状态、节点级步骤状态。
9. 页面可以查看实时日志。
10. 安装失败时可以定位失败步骤、失败节点和错误日志。

## 15. 后续版本规划

```text
v0.2.0: 完整步骤化任务引擎，支持步骤重试、跳过、恢复。
v0.3.0: 安装后集群管理，支持查看节点、Pod、组件状态和下载 kubeconfig。
v0.4.0: 节点扩容、节点删除、单步骤重新执行。
v0.5.0: 离线包管理、镜像仓库配置、安装介质校验。
```
