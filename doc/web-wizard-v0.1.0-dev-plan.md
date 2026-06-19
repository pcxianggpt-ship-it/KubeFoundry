# KubeFoundry Web Wizard v0.1.0 开发计划

## 1. 计划目标

本文档用于指导 `codex/web-wizard-v0.1.0` 分支的 MVP 开发落地。

v0.1.0 的交付目标是：

```text
完成一个 Python 3.7 兼容的网页向导安装 MVP：
用户可以在网页中录入集群配置，后端保存到 SQLite，执行预检查，创建安装任务，并由 Python 编排器通过 SSH/SCP 调用现有 Bash step 脚本完成 Kubernetes 安装流程。
```

开发原则：

1. 先跑通后端闭环，再完善前端体验。
2. 先复用现有 Bash step 脚本，再逐步瘦身脚本变量和传参。
3. 步骤之间默认串行，步骤内部按节点并发。
4. 所有新增文本文件必须使用 LF 换行。
5. Python 代码必须兼容 Python 3.7。

## 2. 版本边界

本计划只覆盖 v0.1.0。

包含：

```text
Python 3.7 后端骨架
SQLite schema
配置模型和任务模型
Web API
预检查任务
安装任务编排器
节点级并发执行
runtime.env 生成
基础 Web 向导页面
实时日志 SSE
```

不包含：

```text
用户登录
RBAC
多租户
集群升级
扩容缩容
完整回滚
离线包管理 UI
高可用后端
分布式任务队列
```

## 3. 里程碑

### M1: 后端工程骨架

目标：建立可启动、可测试、可初始化数据库的 Python 后端。

交付内容：

```text
web/backend/
web/backend/app.py
web/backend/requirements.txt
web/backend/kubefoundry/
web/backend/kubefoundry/api/
web/backend/kubefoundry/store/
web/backend/kubefoundry/config/
web/backend/kubefoundry/installer/
data/
logs/
```

关键任务：

1. 选择 Flask 作为默认 Web 框架。
2. 使用标准库 `sqlite3` 初始化数据库。
3. 提供健康检查接口 `GET /api/health`。
4. 提供数据库初始化命令。
5. 明确 Python 3.7 语法约束。

验收标准：

```text
可以用 python3 web/backend/app.py 启动服务。
GET /api/health 返回 ok。
可以创建 data/kubefoundry.db。
```

### M2: SQLite Schema 和配置模型

目标：把 Web 配置存入 SQLite，并能导出任务级配置快照。

交付内容：

```text
clusters
nodes
ssh_credentials
settings
jobs
job_steps
job_step_nodes
precheck_results
```

关键任务：

1. 实现 schema 初始化和版本记录。
2. 实现集群 CRUD。
3. 实现节点 CRUD。
4. 实现 SSH 凭据引用保存。
5. 实现 ClusterContext 构造。
6. 实现 `cluster.yaml` 导入和导出。

验收标准：

```text
可以通过 API 创建集群。
可以添加 control_plane、worker、registry 节点。
可以从 SQLite 生成 ClusterContext。
可以导出 data/jobs/{job_id}/cluster.yaml。
```

### M3: 预检查闭环

目标：完成第一个真实任务闭环。

流程：

```text
Web/API 创建预检查任务
  -> Python 读取 ClusterContext
  -> 并发检查节点
  -> 写入 precheck_results
  -> 写入 jobs/job_steps/job_step_nodes
  -> 前端或 API 展示结果
```

预检查项：

```text
SSH 连通性
用户权限
操作系统版本
CPU
内存
磁盘
swap
hostname
关键端口占用
```

验收标准：

```text
POST /api/clusters/{cluster_id}/precheck 可以创建任务。
GET /api/jobs/{job_id} 可以查看任务状态。
GET /api/jobs/{job_id}/steps 可以查看步骤状态。
预检查结果可以按节点展示。
失败项包含明确 message 和 detail。
```

### M4: 安装编排器 MVP

目标：Python 编排器替代 `main.sh` 的主流程控制。

关键任务：

1. 实现 Step Plan。
2. 实现目标节点解析。
3. 实现步骤条件判断。
4. 实现步骤间串行。
5. 实现步骤内节点并发。
6. 实现失败处理。
7. 实现节点级日志文件。

第一批接入步骤：

```text
13-install-k8s-deps
15-environment-config
16-install-containerd
```

优先从这些步骤开始，是因为它们适合节点级并发，能验证并发执行、日志拆分和节点状态更新。

验收标准：

```text
可以创建 install job。
Python 可以按 Step Plan 执行选定步骤。
同一步骤可以在多个节点并发执行。
每个节点有独立日志和退出码。
任一节点失败后任务状态可追踪。
```

### M5: runtime.env 和脚本兼容

目标：把复杂变量管理从 Shell 主流程迁移到 Python。

关键任务：

1. Python 为每个节点生成 `runtime.env`。
2. 同时导出 `KF_` 新变量和现有旧变量。
3. 远端执行脚本前自动 `source runtime.env`。
4. 必要时微调 Bash step 脚本，使其优先读取环境变量。

验收标准：

```text
远端节点可以看到 KF_CLUSTER_NAME、KF_K8S_VERSION、KF_NODE_IP 等变量。
现有脚本依赖的 K8S_VERSION、REGISTRY_IP、K8S_HOME 等旧变量仍可用。
不要求远端节点安装 yq。
```

### M6: 实时日志 SSE

目标：让安装过程能被 Web 页面实时观察。

关键任务：

1. 实现 `GET /api/jobs/{job_id}/events`。
2. 推送 job、step、node、log 事件。
3. 总日志记录摘要。
4. 节点日志记录完整输出。

验收标准：

```text
前端或 curl 可以持续接收 SSE 事件。
日志按任务、步骤、节点拆分。
任务失败时可以定位失败步骤和失败节点。
```

### M7: 前端向导 MVP

目标：提供能完成基本操作的网页界面。

页面：

```text
集群基础配置
节点配置
SSH 配置
路径配置
生态组件选择
预检查
配置确认
安装执行
安装结果
```

优先级：

```text
P0: 集群配置、节点配置、预检查、安装执行、日志查看
P1: 路径配置、生态组件选择、配置 YAML 预览
P2: 导入导出 cluster.yaml、历史任务列表
```

验收标准：

```text
可以通过页面创建集群。
可以通过页面添加节点。
可以触发预检查。
可以触发安装任务。
可以查看步骤状态和实时日志。
```

### M8: 文档和验证

目标：让用户能部署、启动和验证 v0.1.0。

交付内容：

```text
doc/web-wizard-v0.1.0-usage.md
后端启动说明
前端启动说明
SQLite 初始化说明
预检查示例
安装任务示例
常见问题
```

验收标准：

```text
新用户按文档可以启动后端。
可以完成一次预检查演示。
可以解释失败日志在哪里查看。
```

## 4. 开发顺序

建议顺序：

```text
M1 后端工程骨架
  -> M2 SQLite Schema 和配置模型
  -> M3 预检查闭环
  -> M5 runtime.env 和脚本兼容
  -> M4 安装编排器 MVP
  -> M6 实时日志 SSE
  -> M7 前端向导 MVP
  -> M8 文档和验证
```

说明：

```text
runtime.env 可以在安装编排器完整接入前先实现，因为它会影响后续所有脚本执行。
前端可以在 M3 后开始并行开发，但第一轮后端 API 应先稳定。
```

## 5. Step Plan 初始清单

v0.1.0 后端先实现核心 K8S 底座步骤。

```text
10-setup-yum-source          local                  serial
11-setup-ssh-login           local                  serial, optional
11b-setup-hostname           all_nodes              parallel
12-setup-k8s-repo            non_primary_nodes      parallel
13-install-k8s-deps          all_k8s_nodes          parallel
14-replace-kubeadm           primary_control_plane  serial
15-environment-config        all_nodes              parallel
16-install-containerd        all_nodes              parallel
17-install-registry          registry               serial
18-init-k8s-cluster          primary_control_plane  serial
19-modify-cert-expiry        primary_control_plane  serial
20-add-control-nodes         other_control_planes   serial
21-add-worker-nodes          workers                parallel
22-install-cni-flannel       primary_control_plane  serial
```

生态组件在 v0.1.0 中作为第二批接入：

```text
30-create-namespace
31-install-kubemate-ui
32-install-nfs
36-install-traefik
38-install-prometheus
39-update-coredns
40-install-metrics-server
41-setup-kubectl-permission
```

## 6. 并发策略

节点级并发使用 Python 标准库：

```text
concurrent.futures.ThreadPoolExecutor
```

默认参数：

```text
max_workers = min(5, node_count)
fail_fast = false
```

原因：

```text
安装 containerd、安装依赖等步骤耗时较长，并发能显著缩短安装时间。
fail_fast=false 可以让同一步骤的其他节点继续执行，便于一次性收集全部失败节点。
```

需要谨慎：

```text
控制面 join 默认串行。
Kubernetes API 资源安装默认串行。
依赖共享文件或共享 join 命令的步骤，需要先确认产物已经生成。
```

## 7. 风险和应对

### 7.1 Python 3.7 依赖风险

风险：

```text
新版本 FastAPI、Pydantic、SQLAlchemy 等生态组件可能不支持 Python 3.7。
```

应对：

```text
v0.1.0 默认使用 Flask、sqlite3、PyYAML。
requirements.txt 锁定兼容 Python 3.7 的版本。
代码不使用 Python 3.8+ 语法。
```

### 7.2 Windows 换行风险

风险：

```text
Windows 环境可能因 autocrlf 把 LF 转成 CRLF。
```

应对：

```text
新增文件必须检查 LF。
后续建议增加 .gitattributes 固定 sh、yaml、md、py 文件为 LF。
```

### 7.3 Bash 脚本变量散落

风险：

```text
现有脚本依赖 yq、config_get、传参和注入变量，直接迁移容易破坏兼容性。
```

应对：

```text
v0.1.0 同时导出 KF_ 新变量和旧变量。
先接少量步骤验证，再逐步扩大覆盖面。
```

### 7.4 并发日志混杂

风险：

```text
多节点并发输出会导致日志混在一起，难以定位失败。
```

应对：

```text
每个节点独立日志文件。
总日志只记录步骤和节点事件摘要。
前端支持按节点筛选日志。
```

### 7.5 远端环境差异

风险：

```text
麒麟、统信、openEuler、CentOS 等系统命令和包名可能不同。
```

应对：

```text
预检查阶段识别 OS 和 arch。
Step Plan 中保留 os_family 条件。
安装脚本内继续保留必要的系统分支判断。
```

## 8. 提交建议

建议按里程碑拆分提交：

```text
docs: add web wizard v0.1.0 development plan
feat(web-backend): add flask service skeleton
feat(web-backend): add sqlite schema initialization
feat(web-backend): add cluster and node APIs
feat(installer): add cluster context and yaml snapshot
feat(installer): add precheck job runner
feat(installer): add runtime env generation
feat(installer): add threaded step runner
feat(web-backend): add job event stream
feat(web-frontend): add wizard shell
docs: add web wizard usage guide
```

## 9. 第一轮开发任务清单

第一轮建议只做到后端预检查闭环：

```text
1. 创建 web/backend 骨架。
2. 增加 requirements.txt。
3. 实现 Flask app 和 health API。
4. 实现 SQLite schema。
5. 实现集群和节点 CRUD。
6. 实现 ClusterContext。
7. 实现预检查 job。
8. 实现节点级并发 SSH 检查。
9. 写入 precheck_results。
10. 提供 job 查询 API。
```

完成第一轮后，再接安装编排器。

