# KubeFoundry v0.3.0 Kubemate 组件安装验收计划

## 1. 文档信息

| 项目 | 内容 |
| --- | --- |
| 版本 | v0.3.0 |
| 状态 | 待执行 |
| 日期 | 2026-08-02 |
| 设计依据 | [Kubemate组件安装设计.md](./Kubemate组件安装设计.md) |
| 开发依据 | [Kubemate组件安装开发计划.md](./Kubemate组件安装开发计划.md) |

## 2. 验收目标

本计划验证 v0.3.0 的组件配置、服务端计划、远程安装、状态恢复、失败重试、重置安全和离线发布能力。验收不仅检查页面是否可操作，还必须证明实际集群状态与 KubeFoundry 记录一致。

发布结论只允许为：

- `通过`：全部必选项通过，无未关闭的阻断问题。
- `有条件通过`：仅允许非阻断环境项延期，并有责任人、风险说明和补验日期。
- `不通过`：任一阻断项失败或缺少有效证据。

## 3. 验收范围

### 3.1 必须验收

- 六个组件组配置与 Redis 不可用状态。
- V9 到 V10 升级和 V1 到 V10 新库迁移。
- 服务端组件计划与不可变快照。
- 主控制节点的 amd64/arm64 Helm 离线分发；其他控制节点无需安装 Helm。
- NFS、Kubemate、Traefik、存储与日志套件、Prometheus 五组。
- 新集群全量安装。
- v0.2.1 已安装集群组件补装。
- 多组部分成功、失败重试和应用中断恢复。
- 组件逆序清理与 Kubernetes 远程重置。
- 双架构发布包、LF、凭据和介质完整性。

### 3.2 不验收为可用能力

- Redis 哨兵实际安装。
- Elasticsearch、SkyWalking、F5、etcd 备份和日志清理。
- 组件卸载和版本升级。
- 生产集群上的破坏性操作。

上述能力如果意外出现在可执行计划中，应视为验收失败。

## 4. 环境准备

### 4.1 本地自动化环境

| 项目 | 要求 |
| --- | --- |
| Java | 17 或更高 |
| Maven | 可完成离线或受控依赖构建 |
| Node.js | 18 或更高 |
| npm | 与 lockfile 匹配 |
| Bash | 可运行仓库测试脚本 |
| Git | 支持 LF 和差异检查 |
| 数据库 | H2 临时库，覆盖 V1/V8 升级路径 |

### 4.2 x86_64 专用测试集群

建议最小拓扑：

```text
控制节点 1：control_plane + registry
工作节点 1：worker + managed NFS
工作节点 2：worker
```

要求：

- 所有节点使用专用测试机器，不承载生产工作负载。
- Kubernetes 初始状态由 v0.3.0 全量安装或明确的 v0.2.1 基线产生。
- 管理节点具备完整 `kube-media`，测试期间禁止联网下载 Chart 或镜像。
- 为 NFS、OpenEBS、Loki、MinIO 和 Prometheus 预留足够磁盘。
- 测试前记录节点磁盘、挂载、`/etc/fstab`、`/etc/exports` 和已有 Helm 状态。

### 4.3 ARM64 专用环境

至少准备一个 ARM64 主控制节点，完成：

- 节点架构识别。
- `helm-arm` 资源选择、校验、分发和执行。
- Kubernetes API 访问和 `helm list -A`。
- 已选组件介质的非破坏性预检查。

ARM64 全组件动态安装建议执行，但 v0.3.0 最低发布门禁为上述 Helm 和预检查闭环。若缺少 ARM64 机器，不得宣称双架构动态验收通过。

### 4.4 外部 NFS 环境

准备一台不受 KubeFoundry 管理的外部 NFS 服务，用于验证 external 模式不会修改外部 `/etc/exports` 或系统状态。

## 5. 证据要求

每个动态用例必须保存：

- KubeFoundry 版本、Git 提交号和发布包 SHA-256。
- 集群拓扑、节点架构和角色，不记录密码或私钥。
- 组件配置 API 响应和安装计划摘要。
- 任务 ID、步骤状态、开始结束时间和脱敏日志。
- 必要的 `kubectl`、`helm`、挂载、系统文件差异和健康检查输出。
- 失败用例的注入方式、错误码、修复动作和重试结果。
- 重置前后对比及用户资源未被删除的证明。

证据目录不得进入 Git，推荐使用：

```text
logs/acceptance/v0.3.0/{日期}/{用例编号}/
```

任何证据中出现密码、Token、Secret 值或私钥均视为安全验收失败，并应立即清理泄露副本。

## 6. 自动化验收门禁

### 6.1 标准命令

```bash
cd web/backend-java && mvn clean test package
cd web/frontend && npm test && npm run build
bash scripts/tests/test_phase3_common.sh
bash scripts/tests/test_phase3_nfs.sh
bash scripts/tests/test_phase3_kubemate.sh
bash scripts/tests/test_phase3_traefik.sh
bash scripts/tests/test_phase3_storage_observability.sh
bash scripts/tests/test_phase3_prometheus.sh
bash scripts/tests/test_java_web_smoke.sh
bash scripts/tests/test_web_package_deploy.sh
bash scripts/tests/test_java_package_runtime.sh
bash scripts/ci/check-lf.sh
bash scripts/ci/check-secrets.sh
git diff --check
```

如果某个计划中的新脚本尚不存在，该项保持未完成，不能以“命令不存在”视为通过。

### 6.2 自动化准入

- [ ] 所有命令退出码为 0。
- [ ] Maven 与 Vitest 没有跳过失败测试。
- [ ] 前端生产构建成功且无组件页面运行时错误。
- [ ] Bash 测试使用假命令验证参数和顺序，不访问真实生产节点。
- [ ] LF 和敏感信息检查没有例外名单绕过。
- [ ] `git diff --check` 无空白错误。

## 7. 数据迁移验收

| 编号 | 场景 | 操作 | 预期结果 |
| --- | --- | --- | --- |
| MIG-01 | 新库迁移 | 从空库执行 Flyway 到 V10 | 所有表、约束、索引创建成功 |
| MIG-02 | V8 无组件选择 | 升级后查询组件 API | 总开关关闭，六组存在，状态均为未安装 |
| MIG-03 | V8 NFS/Traefik | 将旧两组设为 true 后升级 | 同名组保留 true，总开关为 true |
| MIG-04 | V8 Loki | 将旧 Loki 设为 true 后升级 | `storage_observability=true`，旧单 Loki 不再可配置 |
| MIG-05 | 历史安装任务 | 升级含成功 install 任务的库 | 不伪造任何组件已安装状态 |
| MIG-06 | 回滚保护 | 备份数据库后模拟迁移失败 | 原数据库备份可恢复，应用不带半迁移状态启动 |

完成条件：

- [ ] MIG-01 至 MIG-06 全部通过。
- [x] MIG-01 至 MIG-05 已由 V10 迁移测试覆盖并通过。
- [x] `SchemaMigrationTest` 同时覆盖 V1 和 V8 起点。
- [ ] 迁移日志不存在静默数据丢弃。

## 8. 组件配置与 API 验收

| 编号 | 场景 | 预期结果 |
| --- | --- | --- |
| API-01 | 查询默认配置 | 返回总开关、固定六组、中文名称、组件列表、可用性和状态 |
| API-02 | 保存全部可用组 | NFS、Kubemate、Traefik、存储与日志、Prometheus 保存成功 |
| API-03 | 启用 Redis | 返回 `COMPONENT_GROUP_UNAVAILABLE` |
| API-04 | 提交未知组 | 返回 `COMPONENT_GROUP_UNKNOWN` |
| API-05 | 重复组键 | 返回 400，不使用最后一项静默覆盖 |
| API-06 | 非法 NFS 地址或路径 | 返回 `COMPONENT_CONFIG_INVALID` 和具体字段 |
| API-07 | 总开关关闭 | 子组保存值保留，但权威计划不包含组件步骤 |
| API-08 | 活动任务期间写配置 | 返回 `INSTALLER_JOB_ACTIVE` |
| API-09 | 修改已安装组 | 返回冲突，实际状态不变 |
| API-10 | 修改失败或未安装组 | 合法修改成功并使旧预检查失效 |

前端检查：

- [ ] 页面不显示英文组键作为主名称。
- [ ] Redis 开关禁用且原因清楚。
- [ ] NFS 字段只在组启用时参与必填校验。
- [ ] 已安装组显示只读事实状态。
- [ ] 保存失败不跳转，刷新后数据不丢失。

## 9. 安装计划与快照验收

| 编号 | 场景 | 预期结果 |
| --- | --- | --- |
| PLAN-01 | 总开关关闭 | 计划仅含原有 14 个基础步骤，无 Helm 和 phase3 |
| PLAN-02 | 仅启用 NFS | 公共步骤后只出现 NFS 组 |
| PLAN-03 | 仅启用任一其他可用组 | 只出现公共步骤和该组 |
| PLAN-04 | 启用全部可用组 | 按 NFS、Kubemate、Traefik、存储与日志、Prometheus 固定顺序 |
| PLAN-05 | 存储与日志组 | 顺序严格为 OpenEBS、MinIO、Loki、Alloy，不可拆分 |
| PLAN-06 | 客户端提交 steps | 不能绕过配置增加、删除或拆分组件步骤 |
| PLAN-07 | 计划预览后修改配置 | 旧预检查和计划不能用于启动任务 |
| PLAN-08 | 任务启动后修改数据库配置 | 运行计划仍使用原快照 |
| PLAN-09 | 快照内容 | 包含组、配置、计划版本和校验和，不含凭据 |
| PLAN-10 | 存量补装 | 只计划未安装或失败组，不重放 Kubernetes 基础步骤 |

完成条件：

- [ ] `BaseInstallPlanFactory` 保持 v0.2.1 基础步骤顺序和目标范围。
- [ ] 计划预览 API 与任务实际步骤逐项一致。
- [ ] 每个资源都可追溯到明确介质路径和校验和。

## 10. Helm 与资源分发验收

| 编号 | 场景 | 预期结果 |
| --- | --- | --- |
| HELM-01 | amd64 主控制节点 | 选择 `helm-amd`，校验后安装并可执行 |
| HELM-02 | arm64 主控制节点 | 选择 `helm-arm`，不会发送 amd64 文件 |
| HELM-03 | 三控制节点 | 仅主控制节点完成 Helm 验证，其他控制节点不被修改 |
| HELM-04 | 已有兼容受管 Helm | 幂等跳过或明确升级，任务成功 |
| HELM-05 | 已有不兼容非受管 Helm | 预检查返回 `HELM_CONFLICT`，不覆盖文件 |
| HELM-06 | Helm 介质缺失或损坏 | 任务创建前失败，返回 `HELM_MEDIA_MISSING` 或校验错误 |
| HELM-07 | 总开关关闭 | 不分发 Helm 和 phase3 资源 |
| HELM-08 | 单组选中 | 只分发公共资源和该组资源 |

远端核验：

```bash
helm version --short
KUBECONFIG=/etc/kubernetes/admin.conf helm list -A
```

- [ ] 主控制节点命令成功，其他控制节点不执行 Helm 验证。
- [ ] 任务临时目录不包含未选择组资源。
- [ ] 任务结束后临时介质按规则清理，日志仍可查询。

## 11. phase3 脚本静态与幂等验收

| 编号 | 检查项 | 通过标准 |
| --- | --- | --- |
| SH-01 | 严格模式 | 纳入计划脚本启用错误、未定义变量和管道失败检测 |
| SH-02 | 二次 SSH | 组件脚本不调用 `ssh/scp/exec_script_on_*` |
| SH-03 | 固定节点名 | 不存在 `k8sc1/k8sw1/k8sw2` 运行逻辑 |
| SH-04 | 交互命令 | 不存在 `kubectl edit` 或人工输入等待 |
| SH-05 | Helm 幂等 | 使用 `helm upgrade --install` 或等价受控逻辑 |
| SH-06 | 介质保护 | 不对 `kube-media` 原文件执行 `sed -i` 或覆盖 |
| SH-07 | 敏感输出 | 不打印 MinIO Token、Secret、密码或 kubeconfig 内容 |
| SH-08 | 等待策略 | 使用有超时的 readiness/rollout，不以固定 sleep 作为最终判断 |
| SH-09 | 重复执行 | 每个脚本连续两次执行均成功且无重复配置 |
| SH-10 | 错误传播 | 伪造命令失败时脚本返回非零，Java 步骤标记失败 |

## 12. NFS 组件组验收

### NFS-01 managed 模式

步骤：

1. 选择一个集群 Worker 作为 NFS 服务器。
2. 配置共享目录、挂载目录和 StorageClass。
3. 执行组件预检查和 NFS 单组安装。
4. 创建测试 PVC 和 Pod，完成写入及读取。
5. 再次执行相同安装计划。

预期：

- exports 只增加一条带 KubeFoundry 标记的记录。
- Worker fstab 每台只增加一条受管记录。
- Provisioner Pod Ready，StorageClass 存在，PVC 为 Bound。
- 第二次执行成功，无重复行或重复 Helm release。

### NFS-02 external 模式

步骤：配置外部 NFS 地址并安装，安装前后比较外部服务器系统配置。

预期：

- KubeFoundry 只验证连通性和挂载。
- 外部 `/etc/exports` 和服务状态无变化。
- PVC 读写验证通过。

### NFS-03 失败与重试

关闭 NFS 服务或提供不可挂载共享，确认预检查或安装失败；恢复服务后重新预检查并重试。

预期：错误定位准确，修复后成功，系统配置无重复残留。

## 13. Kubemate 组件组验收

| 编号 | 场景 | 预期结果 |
| --- | --- | --- |
| KUBE-01 | 单独安装 | 仅公共步骤和 Kubemate 组执行 |
| KUBE-02 | 介质校验 | 安装前后原始 Kubemate YAML 校验和一致 |
| KUBE-03 | 工作负载 | Deployment/Pod Ready，Service 和 NodePort 存在 |
| KUBE-04 | 配置 | ConfigMap 来自主控制节点 kubeconfig，但日志不输出其内容 |
| KUBE-05 | 重复安装 | 不产生重复资源，任务成功 |
| KUBE-06 | 端口冲突 | 预检查失败并明确报告冲突端口 |

## 14. Traefik 组件组验收

| 编号 | 场景 | 预期结果 |
| --- | --- | --- |
| TRAE-01 | 单独安装 | 仅 Traefik 受管安装完成 |
| TRAE-02 | 工作负载 | Traefik Ready |
| TRAE-03 | 路由 | 测试 Ingress/Service 可通过 Traefik 访问 |
| TRAE-04 | DNS | 集群内测试 Pod 解析服务域名成功 |
| TRAE-05 | 重复安装 | Traefik 资源和 Helm release 无重复 |
| TRAE-06 | 范围排除 | 不安装 Traefik Mesh、不修改 CoreDNS、不创建 Traefik cleanup cron |

## 15. 存储与日志套件验收

### 15.1 正常安装

| 编号 | 检查项 | 预期结果 |
| --- | --- | --- |
| OBS-01 | 原子计划 | 不能单独勾选 OpenEBS、MinIO、Loki 或 Alloy |
| OBS-02 | OpenEBS | Pod Ready，StorageClass 可用，测试 PVC Bound |
| OBS-03 | MinIO | 设计规定的 Operator 和工作负载 Ready |
| OBS-04 | Loki | 工作负载 Ready，可写入并查询测试日志 |
| OBS-05 | Alloy | Agent Ready，测试日志可在 Loki 查询到 |
| OBS-06 | 顺序 | 任务事件严格符合 OpenEBS、MinIO、Loki、Alloy |
| OBS-07 | 敏感信息 | 日志和事件不包含 MinIO Token 或 Secret 值 |

### 15.2 失败门禁

分别在 OpenEBS、MinIO、Loki 阶段注入可恢复失败：

- [ ] 当前步骤失败后，依赖它的后续步骤没有启动。
- [ ] 组状态为 `failed`，错误步骤和目标明确。
- [ ] 已成功资源保持可识别状态。
- [ ] 修复后重试完整组成功，资源不冲突。
- [ ] 最终组状态为 `installed`。

## 16. Prometheus 组件组验收

| 编号 | 场景 | 预期结果 |
| --- | --- | --- |
| PROM-01 | 非固定节点名 | 使用随机合法 Worker 主机名仍能正确准备标签和目录 |
| PROM-02 | 单 Worker | Prometheus 套件成功安装 |
| PROM-03 | 多 Worker | 目标解析准确，无固定只取前两个节点的错误 |
| PROM-04 | 工作负载 | Operator、Prometheus、Exporter、Alertmanager Ready |
| PROM-05 | Targets | Node Exporter 和 kube-state-metrics 目标为 Up |
| PROM-06 | Metrics Server | `kubectl top nodes` 返回指标 |
| PROM-07 | 重复安装 | CRD 和 Helm/Kubernetes 资源无冲突 |

## 17. 新集群全量安装验收

### FULL-01 不安装组件

总开关关闭，执行新集群安装。

预期：phase2 和集群健康验证成功；无 Helm 分发、phase3 步骤、组件命名空间或组件状态误报。

### FULL-02 单组件组

分别使用独立测试基线启用五个可用组中的一个。

预期：每组不依赖其他未选组即可成功，证明组件组边界真实有效。

### FULL-03 全部可用组

启用五个可用组并执行一次全量安装。

预期：

- 基础步骤先完成，组件公共步骤只执行一次。
- 五组按固定顺序执行。
- 全部组状态为 `installed`。
- 安装确认页、任务页和集群实际资源一致。
- 集群基础配置按现有规则锁定。

## 18. v0.2.1 存量集群补装验收

### UPG-01 基线准备

使用 v0.2.1 发布包安装 Kubernetes 基础集群并保留成功任务、数据库和远端状态，然后升级管理端到 v0.3.0。

预期：基础集群仍显示 installed，组件状态为未安装，历史日志可查询。

### UPG-02 组件补装

在不执行 Kubernetes reset 的情况下启用一个或多个组件组，完成组件预检查和安装。

预期：

- `job_type=component_install`。
- 不执行任何 phase2 步骤。
- Kubernetes 节点和现有工作负载不被重建。
- 所选组件安装成功并更新组状态。
- 基础配置继续保持锁定。

### UPG-03 后续追加组件

在已有已安装组件组的基础上启用另一个未安装组。

预期：计划不重装已安装组，只安装新增组；已安装组配置不可修改。

## 19. 状态、中断与并发验收

| 编号 | 场景 | 预期结果 |
| --- | --- | --- |
| STATE-01 | 多组中后一组失败 | 前序成功组 installed，失败组 failed，未开始组 not_installed |
| STATE-02 | 修复并重试 | 只计划 failed/not_installed 组，最终状态正确 |
| STATE-03 | 运行时关闭管理服务 | 活动组恢复为 failed/interrupted 语义，不自动继续远端命令 |
| STATE-04 | 重复提交组件安装 | 第二个请求返回活动任务冲突 |
| STATE-05 | 安装与重置并发 | 后提交请求被集群级互斥拒绝 |
| STATE-06 | 运行中编辑组件 | 前后端均拒绝，快照不变化 |
| STATE-07 | SSE 重连 | 页面恢复步骤和组状态，不重复显示事件 |

## 20. 重置与安全验收

### 20.1 前置要求

- 仅在专用测试集群执行。
- 重置前完整备份 H2 数据库和节点关键系统文件。
- 专项安全复核已签字完成。
- 准备非 KubeFoundry 管理的 Helm 文件、exports 行、fstab 行和测试 Kubernetes 资源。

### 20.2 用例

| 编号 | 场景 | 预期结果 |
| --- | --- | --- |
| RESET-01 | 全组件重置 | 按依赖逆序清理后执行 Kubernetes reset |
| RESET-02 | 受管 NFS 配置 | 仅删除带标记 exports/fstab 行 |
| RESET-03 | external NFS | 外部服务器没有任何配置变化 |
| RESET-04 | 非受管 Helm | 用户已有 Helm 保留 |
| RESET-05 | 受管 Helm | 校验和和标记匹配时按设计清理 |
| RESET-06 | Traefik 清理 | 只清理 KubeFoundry 管理的 Traefik 资源 |
| RESET-07 | 组件清理失败 | 重置任务失败，集群保持锁定 |
| RESET-08 | 修复后重试 | 已清理资源幂等跳过，最终重置成功 |
| RESET-09 | 状态回写 | 全部组件组回到 not_installed |
| RESET-10 | 路径攻击 | 空路径、根目录、越界和符号链接均被拒绝 |

### 20.3 安全通过标准

- [ ] 没有删除用户 Kubernetes 资源、系统配置行或非受管 Helm。
- [ ] 没有使用未校验通配符和空变量执行删除。
- [ ] 清理失败时未解锁集群。
- [ ] 重置日志没有凭据和 Secret。
- [ ] 重复重置不会因资源不存在而失败。

## 21. 发布包与离线验收

| 编号 | 场景 | 预期结果 |
| --- | --- | --- |
| PKG-01 | 版本一致性 | Maven、npm、健康接口、包名、VERSION、systemd 文案均为 0.3.0 |
| PKG-02 | x86_64 包 | 构建、校验、部署和启动成功 |
| PKG-03 | aarch64 包 | 构建、校验、部署和启动成功 |
| PKG-04 | phase3 内容 | 所有纳入计划的脚本和 verify 文件存在 |
| PKG-05 | Helm 介质 | 两种架构映射和校验和可解析 |
| PKG-06 | 缺失资源 | 删除任一必需资源后预检查明确失败 |
| PKG-07 | 篡改检测 | 修改 JAR、前端或 Helm 后校验失败 |
| PKG-08 | 符号链接 | 越界符号链接包被部署脚本拒绝 |
| PKG-09 | 纯离线 | 断网环境不发起 Helm 仓库或外部下载请求 |
| PKG-10 | 升级保留 | 部署 v0.3.0 保留 `data/logs/kube-media` 和历史任务 |

## 22. 回归验收

- [ ] 节点多角色、Registry 派生和拓扑预检查无回归。
- [ ] phase2 14 个基础步骤顺序、资源、目标和验证无回归。
- [ ] 安装成功锁定、安装失败和远程重置状态机无回归。
- [ ] SSH 主机指纹、凭据加密和日志脱敏无回归。
- [ ] 集群配置、节点测试、安装确认、SSE 和日志查询无回归。
- [ ] Registry 与控制节点或 Worker 同机场景无回归。
- [ ] v0.2.1 数据库升级后历史集群和任务可正常查看。

## 23. 缺陷分级与发布门禁

| 等级 | 定义 | 发布处理 |
| --- | --- | --- |
| P0 | 数据误删、凭据泄露、生产风险或无法恢复 | 立即停止验收，必须修复并全量重测 |
| P1 | 主流程失败、状态错误、依赖绕过、组件不可用 | 必须修复并重测，不得发布 |
| P2 | 非主路径功能错误且有明确绕行 | 原则上修复；延期必须书面批准 |
| P3 | 不影响功能的显示或文档问题 | 可记录后续修复，不影响技术结论 |

发布门禁：

- P0、P1 未关闭数量必须为 0。
- P2 延期项必须有责任人、风险评估和目标版本。
- 自动化验收不得有失败或跳过的必选项。
- x86_64 动态全量安装、存量补装和远程重置必须通过。
- ARM64 Helm 分发与非破坏性预检查必须通过，或明确标记未完成且不得宣称双架构动态通过。
- 安全复核未完成时不得执行或通过远程重置验收。

## 24. 最终验收清单

### 自动化

- [ ] 后端全量测试通过。
- [ ] 前端全量测试和生产构建通过。
- [ ] phase3 六类 Bash 测试通过。
- [ ] Java Web、发布包和运行时冒烟通过。
- [ ] LF、敏感信息和 Git 差异检查通过。

### 功能

- [ ] 六个组件组配置准确，Redis 不可用。
- [ ] 五个可用组均通过独立安装。
- [ ] 存储与日志组依赖、失败停止和重试通过。
- [ ] 新集群全量安装通过。
- [ ] v0.2.1 存量集群补装通过。
- [ ] 多组部分成功和任务中断恢复通过。

### 平台与安全

- [ ] x86_64 Helm 和全量组件动态验收通过。
- [ ] ARM64 Helm 和非破坏性预检查通过。
- [ ] 组件逆序清理和远程重置通过专项安全复核。
- [ ] 用户资源、外部 NFS 和非受管 Helm 保留。
- [ ] 日志、事件、API 和快照无凭据泄露。

### 发布

- [ ] 所有版本号统一为 0.3.0。
- [ ] 双架构发布包构建、校验和部署通过。
- [ ] 中文设计、开发、API、部署、使用和验收文档同步。
- [ ] 最终验收结果、遗留项和发布结论已签署记录。

## 25. 验收结果模板

```text
验收版本：v0.3.0
Git 提交：
发布包 SHA-256：
验收日期：
验收环境：

自动化结果：通过 / 不通过
x86_64 动态结果：通过 / 不通过
ARM64 动态结果：通过 / 未完成 / 不通过
安全复核结果：通过 / 不通过

P0 遗留：
P1 遗留：
P2 延期：
已知限制：Redis 哨兵模式暂不可用

最终结论：通过 / 有条件通过 / 不通过
负责人：
复核人：
```
