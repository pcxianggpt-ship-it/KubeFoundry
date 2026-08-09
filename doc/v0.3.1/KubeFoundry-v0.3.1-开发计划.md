# KubeFoundry v0.3.1 开发计划

## 1. 文档信息

| 项目 | 内容 |
| --- | --- |
| 目标版本 | v0.3.1 |
| 状态 | 进行中 |
| 启动日期 | 2026-08-09 |
| 开发分支 | `codex/web-wizard-v0.3.1` |
| 需求依据 | [优化需求记录.md](./优化需求记录.md) |
| 设计依据 | [KubeFoundry-v0.3.1-优化设计.md](./KubeFoundry-v0.3.1-优化设计.md) |

## 2. 开发目标

本计划将 v0.3.1 的七项优化拆分为可独立实现、测试、复核和提交的任务，最终交付应满足：

1. CoreDNS 在 Kubernetes 基础安装完成后自动获得软反亲和配置。
2. MinIO Operator 和 Tenant 可使用离线介质完成非交互部署与就绪验证。
3. 服务器节点支持一键测试全部节点，同一集群内主机名和 IPv4 保持唯一。
4. Kubemate 组件不再使用总开关，各组件组直接控制是否进入安装计划。
5. NFS 已正确挂载时跳过重复挂载，冲突或超时时安全失败。
6. 一个 Kubemate 组件组失败后，其他无依赖组件组继续安装，并准确记录部分成功结果。
7. 集群安装详情可按任务 ID 查看、切换和刷新历史安装过程，任务数据互不混合。

## 3. 实施约束

- 所有新增和修改的文本文件使用 LF。
- 不修改 Flyway V1 至 V12，只新增 V13 及后续迁移。
- 前端不能决定安装步骤、失败策略或组件依赖；权威计划由后端根据不可变快照生成。
- 不在日志、事件、快照、API 和测试夹具中保存密码、Token、私钥或 Kubernetes Secret 数据。
- Bash 脚本不得交互、不得内部二次 SSH、不得修改发布介质原文件。
- 组件组仍按固定顺序串行，v0.3.1 不引入 Helm 并发安装。
- NFS 挂载、MinIO 凭据、安装状态机和数据库迁移属于高风险范围，合并前必须专项复核。
- 开发期间不得在生产集群验证 NFS 冲突、MinIO 清理或失败注入。
- 每个 Git 提交使用中文说明，只包含一个清晰职责；提交前复核暂存范围，不包含 `.superpowers/`、`dist/` 或本地配置。

## 4. 开发前决策门禁

以下决策在对应任务编码前必须形成评审结论。

### 门禁 A：MinIO 版本准入

- [ ] 确认离线介质中 Operator、Tenant CRD、MinIO 镜像的确切版本和 SHA-256。
- [ ] 核对许可证、已知安全问题和目标 Kubernetes 版本兼容性。
- [ ] 确认 Tenant API 版本、最小拓扑、StorageClass、PVC 数量与容量规则。
- [ ] 确认上游归档后继续交付该版本的维护责任和退出方案。

未通过门禁 A 时，最终任务 11 不进入实现；其他任务可继续开发，MinIO 自动化不得被标记为完成。

### 门禁 B：任务状态契约

- [ ] 确认新增终态名称使用 `partial_success`。
- [ ] 确认集群基础安装成功但组件部分失败时，集群展示状态与任务状态的映射。
- [ ] 确认旧客户端、SSE 消费者、部署脚本和文档对新增状态的兼容策略。

未通过门禁 B 时，任务 7 不修改数据库或公共 API。

### 门禁 C：节点重复数据迁移

- [ ] 对测试数据库和待升级数据执行主机名、IPv4 重复扫描。
- [ ] 确认草稿节点不参与唯一约束，转正式节点时强制校验。
- [ ] 确认发现正式节点重复时停止升级并人工处理，不自动删除或合并。

未通过门禁 C 时，任务 2 仅实现规范化与只读扫描，不创建唯一索引。

## 5. 任务依赖

```text
任务 1 基线与契约冻结
  ├── 任务 2 节点唯一性后端与迁移
  │     └── 任务 3 节点前端与批量测试
  ├── 任务 4 移除 Kubemate 总开关
  │     └── 任务 7 组件组失败隔离
  ├── 任务 5 CoreDNS 反亲和
  └── 任务 6 NFS 挂载幂等

任务 4 + 任务 7
  └── 任务 8 组件组状态与前端展示

任务 7 + 任务 8
  └── 任务 9 按任务 ID 展示安装历史

任务 2 至任务 9
  └── 任务 10 非 MinIO 功能集成与回归

任务 1 至任务 10 + 门禁 A
  └── 任务 11 MinIO 自动化、真实环境操作文档与最终验收
```

任务 2、任务 4、任务 5 和任务 6 在文件边界不冲突时可独立推进。任务 7 必须等待状态契约门禁 B。MinIO 固定为最后一个开发任务，只有其他功能完成联合回归且门禁 A 通过后才开始。

## 6. 里程碑与工作量参考

以下为单人串行开发的人日参考，不含等待真实集群、外部评审和 MinIO 版本决策时间。

| 里程碑 | 任务 | 参考工作量 | 完成标志 |
| --- | --- | --- | --- |
| M0 决策与基线 | 任务 1、门禁 B/C，启动门禁 A 调研 | 1～2 人日 | 非 MinIO 契约可执行，MinIO 调研有责任人和结论日期 |
| M1 配置与节点 | 任务 2～4 | 4～6 人日 | 节点唯一、批量测试、独立组开关可用 |
| M2 脚本可靠性 | 任务 5～6 | 3～5 人日 | CoreDNS、NFS 自动化测试通过 |
| M3 组件隔离 | 任务 7～8 | 5～8 人日 | 组失败隔离、部分成功和前端展示闭环 |
| M4 任务历史 | 任务 9 | 3～5 人日 | 多任务 ID 可切换、刷新、实时更新 |
| M5 非 MinIO 集成 | 任务 10 | 2～3 人日 | 其余六项优化联合回归通过 |
| M6 MinIO 最终交付 | 任务 11、门禁 A | 6～10 人日 | 自动部署、操作文档和真实环境验收完成 |

总工作量参考为 23～37 人日。MinIO 上游归档后的兼容性验证、真实环境排队和问题修复可能额外增加时间。

## 7. 任务 1：基线、契约与测试门禁

### 目标

冻结 v0.3.1 的数据库版本、API 变化、任务状态集合、脚本入口和验证命令，避免开发过程中出现相互冲突的实现。

### 主要文件

- 修改：`doc/v0.3.1/KubeFoundry-v0.3.1-优化设计.md`
- 修改：`doc/v0.3.1/KubeFoundry-v0.3.1-开发计划.md`
- 按需修改：`doc/v0.3.0/接口说明.md` 中跨版本兼容说明。
- 检查：Java、Vue、Bash 现有测试入口和 CI 脚本。

### 实施步骤

- [ ] 完成门禁 A、B、C 的评审记录。
- [ ] 冻结 V13/V14 迁移职责和命名，确认不与并行开发迁移冲突。
- [ ] 冻结任务状态集合：`pending/running/success/partial_success/failed/interrupted`。
- [ ] 冻结步骤状态集合：`pending/running/success/failed/skipped/interrupted`。
- [ ] 冻结组件步骤失败策略：`ABORT_JOB/ABORT_GROUP`。
- [ ] 冻结节点重复错误码和任务归属错误码。
- [ ] 记录当前 Maven、Vitest、Bash 测试基线，区分既有失败与新增回归。
- [ ] 确认发布包和部署脚本会同时发布前端、后端和脚本。

### 验收

- 三个门禁均有明确的通过、延期或移出范围结论。
- API、状态和迁移约定不再存在阻塞性歧义。
- 基线测试结果可复现。

### 建议提交

```text
文档：冻结v0.3.1开发契约与风险门禁
```

## 8. 任务 2：节点唯一性后端与数据库迁移

### 目标

规范化节点主机名和 IPv4，并通过应用校验与数据库唯一约束保证同集群正式节点不重复。

### 主要文件

- 新增：`web/backend-java/src/main/resources/db/migration/V13__cluster_node_identity_uniqueness.sql`
- 修改：`web/backend-java/src/main/java/io/kubefoundry/cluster/Node.java`
- 修改：`web/backend-java/src/main/java/io/kubefoundry/cluster/NodeRepository.java`
- 修改：`web/backend-java/src/main/java/io/kubefoundry/cluster/ClusterService.java`
- 修改：全局 API 异常映射。
- 修改：`SchemaMigrationTest.java`
- 修改：`ClusterNodeApiTest.java`
- 新增：节点并发唯一性集成测试。

### 实施步骤

- [ ] 先编写规范化、重复保存、编辑排除自身和并发写入失败测试。
- [ ] 实现主机名 `trim -> 去末尾点 -> lower-case` 的规范化函数。
- [ ] 实现严格 IPv4 解析和无前导零标准化。
- [ ] 为正式节点维护 `hostname_normalized` 和 `ip_normalized`，草稿节点保持 `NULL`。
- [ ] 创建和更新前查询同集群冲突节点并返回稳定错误码。
- [ ] 使用数据库唯一约束兜底并将约束异常映射为业务错误。
- [ ] 增加正式节点重复数据的迁移前置扫描。
- [ ] V13 只回填非草稿节点；存在冲突时迁移失败，不修改原数据。
- [ ] 验证复制草稿、完成编辑、删除节点和跨集群同值场景。

### 验收

- 同集群正式节点主机名和 IPv4 分别唯一。
- 大小写、尾部点、空格和 IPv4 前导零不能绕过校验。
- 两个并发请求写入相同身份时仅一个成功。
- 草稿复制流程不被数据库约束破坏。
- V1/V9/V12 数据库升级路径均有测试。

### 建议提交

```text
节点：保证集群内主机名和IP唯一
```

## 9. 任务 3：节点前端校验与测试全部节点

### 目标

在服务器节点页面提供一键批量测试和即时重复提示，复用现有集群节点测试任务。

### 主要文件

- 修改：`web/frontend/src/views/NodeConfigView.vue`
- 修改：`web/frontend/src/components/nodes/NodeEditor.vue`
- 修改：`web/frontend/src/components/nodes/NodeTable.vue`
- 修改：`web/frontend/src/components/nodes/NodeTestActivity.vue`
- 修改：`web/frontend/src/api/client.js`
- 修改：`NodeConfigView.test.js`
- 修改：`NodeEditor.test.js`
- 修改：API 契约测试。

### 实施步骤

- [ ] 增加“测试全部节点”按钮并调用 `failed_only=false` 的现有接口。
- [ ] 增加“仅重试失败节点”入口并调用 `failed_only=true`。
- [ ] 无节点、存在草稿、活动节点测试期间正确禁用按钮。
- [ ] 通过任务事件逐节点展示等待、连接、安装密钥、验证、成功和失败。
- [ ] 一个节点失败后其他节点继续更新，批量结束显示汇总。
- [ ] 编辑节点时基于当前列表执行主机名和 IPv4 即时重复校验。
- [ ] 后端重复错误映射到具体表单字段，并显示冲突节点信息。
- [ ] 增加键盘操作、ARIA 标签、焦点和移动端布局测试。

### 验收

- 可一键测试当前集群全部正式节点。
- 单节点失败不阻塞其他节点，失败节点可单独重试。
- 前端即时校验和后端最终校验的规则、文案一致。

### 建议提交

```text
前端：增加全部节点测试与重复校验
```

## 10. 任务 4：移除 Kubemate 组件安装总开关

### 目标

删除总开关的页面和业务语义，各组件组选项直接决定配置、快照和计划。

### 主要文件

- 修改：`ClusterComponentService.java`
- 修改：`InstallationSnapshotPayload.java`
- 修改：`InstallationSnapshotService.java`
- 修改：`ComponentPlanFactory.java`
- 修改：`KubemateComponentsView.vue`
- 修改：`web/frontend/src/api/client.js`
- 修改：组件 API、快照、计划和 Vue 测试。

### 实施步骤

- [ ] 先增加“无总开关、任一组选中即可生成计划”的失败测试。
- [ ] 配置 API 不再要求或返回顶层 `enabled`。
- [ ] 兼容接收旧客户端的 `enabled` 字段，但忽略其业务含义并记录弃用警告。
- [ ] 快照停止写入和读取 `kubemateEnabled`。
- [ ] `ComponentPlanFactory` 只判断各组 `enabled`。
- [ ] 删除前端总开关、关闭提示和子组禁用逻辑。
- [ ] 全部组件组关闭时显示空选择状态且组件计划为空。
- [ ] `clusters.kubemate_enabled` 暂保留为派生兼容列，不参与计划判断。
- [ ] 更新 API 文档和兼容说明。

### 验收

- 页面不存在“启用 Kubemate 组件安装”控件。
- 单独启用任一可用组可生成且只生成该组计划。
- 全部关闭时不分发 Helm 或 phase3 资源。
- 已安装组不会因配置开关变化被解释为卸载。

### 建议提交

```text
组件：移除Kubemate安装总开关
```

## 11. 任务 5：CoreDNS 软反亲和自动配置

### 目标

新增非交互、幂等的 CoreDNS 反亲和脚本并接入 Kubernetes 基础计划。

### 主要文件

- 新增：`scripts/steps/phase2_k8s_base/19-configure-coredns-affinity.sh`
- 新增：`scripts/verify/phase2_k8s_base/verify-19-configure-coredns-affinity.sh`
- 新增或修改：对应 Bash 测试。
- 修改：`BaseInstallPlanFactory.java`
- 修改：`BaseInstallPlanFactory`、`InstallPlanFactory` 相关测试。
- 停用但不删除：`scripts/steps/phase3_ecosystem/39-update-coredns.sh`。

### 实施步骤

- [ ] 先用伪造 `kubectl` 覆盖无 affinity、已有其他 affinity、已有目标规则三种场景。
- [ ] 检测目标软反亲和规则，存在时直接成功且不触发 rollout。
- [ ] 使用 JSON Patch 只创建缺失父级或追加目标规则，不覆盖已有 affinity。
- [ ] 使用 `preferredDuringSchedulingIgnoredDuringExecution` 和权重 100。
- [ ] 等待 CoreDNS rollout，超时返回失败。
- [ ] 验证 Pod Ready；多节点未分散时记录警告而非强制失败。
- [ ] 将步骤加入基础计划，确保组件补装任务不执行。
- [ ] 删除任何 `kubectl edit`、固定 `sleep` 和 Traefik Mesh 副作用。

### 验收

- 连续执行两次不产生重复规则或无意义滚动更新。
- 单节点集群不因反亲和规则出现 Pending。
- 用户已有 affinity 不被覆盖。
- 基础安装计划顺序和快照测试通过。

### 建议提交

```text
安装：自动配置CoreDNS副本反亲和
```

## 12. 任务 6：NFS 挂载幂等与防卡死

### 目标

精确识别 NFS 挂载状态，正确挂载时跳过，冲突和超时时安全失败。

### 主要文件

- 修改：`scripts/steps/phase3_ecosystem/32-mount-nfs-workers.sh`
- 修改：`scripts/lib/phase3.sh`（如需受管块和超时公共函数）。
- 修改：`scripts/tests/test_phase3_nfs.sh`
- 修改：NFS verify 脚本和使用文档。

### 实施步骤

- [ ] 先增加正确挂载、错误源、错误类型、未挂载、超时和重复执行测试。
- [ ] 使用 `findmnt --mountpoint` 精确查询目标，不把父级文件系统视为目标挂载。
- [ ] 比较实际 source 与期望 `server:share`，仅接受 `nfs/nfs4`。
- [ ] 正确挂载时维护受管 fstab 块并跳过 `mount`。
- [ ] 冲突挂载时输出安全诊断并失败，不调用 `mount` 或 `umount`。
- [ ] 未挂载时原子维护受管 fstab 块，避免陈旧条目和重复条目。
- [ ] 使用 `timeout --foreground` 限制挂载时间，默认 60 秒。
- [ ] 挂载后再次核对 source、fstype 和目标。
- [ ] 验证 managed NFS 服务端自身继续安全跳过自挂载。

### 安全复核门禁

- [ ] 复核所有 `/etc/fstab` 修改只作用于 KubeFoundry 受管块。
- [ ] 复核空路径、根路径、符号链接和命令参数注入。
- [ ] 复核超时后的子进程退出和任务状态回写。

### 验收

- 已正确挂载时不执行重复挂载。
- 冲突挂载不会被覆盖或卸载。
- NFS 无响应时步骤在限定时间内结束。
- 连续执行两次 fstab 和挂载状态均无重复。

### 建议提交

```text
脚本：增强NFS挂载幂等与超时保护
```

## 13. 任务 7：组件组失败隔离执行器

### 目标

重构任务执行失败边界，使组件组内失败不会终止后续无依赖组件组。

### 前置条件

门禁 B 完成，任务 4 完成。

### 主要文件

- 新增：`web/backend-java/src/main/resources/db/migration/V14__job_execution_status.sql`
- 修改：`InstallStep.java`
- 修改：`Job.java`
- 修改：`JobStep.java`
- 修改：`JobService.java`
- 修改：`ComponentInstallationStateService.java`
- 修改：`ComponentPlanFactory.java`
- 修改：任务、并发、事务和中断恢复测试。

### 实施步骤

- [ ] 先构造 A 组失败、B 组成功的执行器测试，确认现有实现会失败。
- [ ] 为计划步骤增加服务端失败策略，不接受客户端传入。
- [ ] V14 增加 `job_steps.status_reason`、`jobs.started_at` 和 `jobs.finished_at`。
- [ ] 支持步骤 `skipped` 和任务 `partial_success`。
- [ ] `ABORT_GROUP` 失败后将本组剩余步骤标记为跳过，并继续下一组。
- [ ] `ABORT_JOB` 用于 Kubernetes 基础步骤和组件公共前置。
- [ ] 分别计算全成功、部分成功、全失败、公共前置失败和中断状态。
- [ ] 每组独立更新 `installed/failed/not_installed`，不覆盖其他组状态。
- [ ] 服务重启恢复时正确处理 running、pending 和 skipped 步骤。
- [ ] 保持节点级执行并发和同集群任务互斥不回归。

### 验收

- 任一组失败后其他无依赖组继续执行。
- 组内后续步骤显示跳过及稳定原因码。
- 任务和每个组件组状态与实际结果一致。
- 公共前置或 Kubernetes 基础失败仍能正确终止。
- 事务提交失败、队列拒绝和服务重启不会留下永久 `installing` 状态。

### 建议提交

```text
任务：隔离Kubemate组件组安装失败
```

## 14. 任务 8：组件组状态与部分成功前端

### 目标

在安装概览和执行页准确展示成功、失败、跳过、部分成功及可重试组。

### 主要文件

- 修改：`InstallOverviewView.vue`
- 修改：`JobExecutionView.vue`
- 修改：`JobStageList.vue`
- 修改：`NodeExecutionTable.vue`
- 修改：任务状态工具和样式。
- 修改：`InstallFlow.test.js`
- 新增或修改：`JobExecutionView` 测试。

### 实施步骤

- [ ] 将 `partial_success` 纳入终态集合和中文状态映射。
- [ ] 将 `skipped` 显示为“已跳过”，不计入成功或失败节点。
- [ ] 按组件组分段展示步骤，并突出首个失败步骤和跳过原因。
- [ ] 安装概览按组显示已安装、安装失败、未安装和可重试。
- [ ] 失败组重试生成新任务，不重新执行已安装组。
- [ ] SSE 终态处理支持 `partial_success`，及时关闭连接并刷新快照。
- [ ] 进度计算区分已完成步骤和成功比例，避免跳过步骤被误算为成功。

### 验收

- 部分成功不会被显示为全部成功或全部失败。
- 用户可明确识别失败组、跳过步骤和其他成功组。
- 重试入口只包含允许重试的组件组。

### 建议提交

```text
前端：展示组件安装部分成功与跳过状态
```

## 15. 任务 9：按任务 ID 查看安装历史

### 目标

为集群安装页面增加任务列表和规范详情路由，确保切换、刷新和实时更新始终绑定同一任务 ID。

### 主要文件

- 修改：`JobController.java`
- 修改：`JobRepository.java`
- 修改：`SpaForwardController.java`
- 修改：`InstallOverviewView.vue`
- 修改：`JobExecutionView.vue`
- 修改：`web/frontend/src/router.js`
- 修改：`web/frontend/src/api/client.js`
- 修改：Java API、SPA 转发、Vue 路由和安装流程测试。

### 实施步骤

- [ ] 任务响应增加创建、开始和结束时间。
- [ ] 任务列表支持按集群和 `install/component_install` 类型过滤并按 ID 倒序。
- [ ] 安装概览增加任务记录表和默认选择规则。
- [ ] 新增 `/cluster-install/:clusterId/jobs/:jobId` 规范路由。
- [ ] 旧 `/jobs/:jobId/execution` 路由兼容重定向。
- [ ] 后端 SPA 转发覆盖新路由，直接访问和 F5 刷新返回前端入口。
- [ ] 后端校验任务属于当前集群。
- [ ] 切换任务前关闭旧 EventSource，清空步骤、日志和筛选。
- [ ] 使用请求序号和 jobId 校验丢弃迟到响应。
- [ ] 终态任务只加载快照，不建立 SSE。
- [ ] 覆盖浏览器前进、后退、刷新、无效任务和跨集群任务测试。

### 验收

- 同一集群至少三个安装任务可按任务 ID 独立查看。
- 切换任务时步骤、节点和日志不串流。
- F5 刷新保持所选任务且不出现 Whitelabel 404。
- 无效或跨集群任务显示安全、明确的错误状态。

### 建议提交

```text
任务：按任务ID展示集群安装历史
```

## 16. 任务 10：非 MinIO 功能集成与回归

### 目标

在 MinIO 开发前完成其余六项优化的联合回归、测试环境验收、发布包验证及中文文档同步，为最后的 MinIO 实施提供稳定基线。

### 主要文件

- 修改：`doc/v0.3.1/` 下设计、开发计划、接口说明、使用手册和阶段验收清单。
- 修改：`README.md`、版本历史和部署说明。
- 按需修改：`package.sh`、`deploy.sh`、发布包测试。
- 修改：Java Web 冒烟测试和前端生产构建测试。

### 实施步骤

- [ ] 运行全部 Maven 测试和打包。
- [ ] 运行全部 Vitest、前端构建和路由刷新测试。
- [ ] 运行 phase2/phase3 Bash 测试、LF 和敏感信息检查。
- [ ] 验证 V1/V9/V12 到最新迁移路径和备份恢复流程。
- [ ] 在专用测试集群验证 CoreDNS 单节点与多节点行为。
- [ ] 验证全节点测试包含单节点失败场景。
- [ ] 验证 NFS 正确挂载、冲突挂载和超时，不使用生产挂载点。
- [ ] 验证除存储与日志组 MinIO 链路外的可用组件组单独安装。
- [ ] 失败注入验证组件组隔离和 `partial_success`。
- [ ] 生成至少三个安装任务并验证任务历史切换与刷新。
- [ ] 更新非 MinIO 功能的部署、使用、接口、阶段验收和已知限制文档。
- [ ] 复核发布包不包含构建缓存、凭据、本地数据库或用户配置。

### 建议验证命令

```bash
cd web/backend-java && mvn clean test package
cd web/frontend && npm test && npm run build
bash scripts/tests/test_phase3_common.sh
bash scripts/tests/test_phase3_nfs.sh
bash scripts/tests/test_java_web_smoke.sh
bash scripts/tests/test_web_package_deploy.sh
bash scripts/ci/check-lf.sh
bash scripts/ci/check-secrets.sh
git diff --check
```

具体脚本名称以仓库最终测试入口为准，不存在的入口应在对应开发任务中补齐，不能在发布时静默跳过。

### 阶段门禁

- [ ] 高风险 NFS、安装状态机和迁移通过专项复核。
- [ ] 自动化测试全部通过，无未解释的基线回归。
- [ ] x86_64 测试集群的非 MinIO 验收通过。
- [ ] ARM64 至少完成介质、计划和脚本静态验证；无真实环境时明确记录延期。
- [ ] 所有文档、版本号、接口响应和 UI 文案一致。

### 建议提交

```text
测试：完成v0.3.1非MinIO功能联合回归
```

## 17. 任务 11：MinIO 自动化、真实环境操作文档与最终验收

### 目标

作为 v0.3.1 最后一个开发任务，完成 MinIO 固定版本准入、离线介质预检查、Operator/Tenant 自动部署、安全复核，并交付可直接用于真实环境测试的中文操作文档。

### 前置条件

- 任务 1 至任务 10 全部完成。
- 门禁 A 已通过并形成可审查结论。
- 非 MinIO 功能联合回归没有阻塞性问题。
- 已准备与生产隔离、允许创建和保留 PVC 的真实测试环境。

### 主要文件

- 修改：`ComponentMediaService.java`
- 修改：组件配置 DTO、预检查服务、安装快照和介质清单。
- 修改：`scripts/steps/phase3_ecosystem/49-install-minio.sh`
- 修改：MinIO Operator、Tenant 模板和离线资源。
- 修改：`scripts/tests/test_phase3_storage_observability.sh`
- 修改：`ComponentPlanFactory.java` 和对应 Java 测试。
- 修改：存储与日志 verify 脚本。
- 新增：`doc/v0.3.1/MinIO真实环境部署与验证操作手册.md`
- 更新：v0.3.1 接口、使用、部署、验收和发布说明。

### 阶段 1：版本、配置与介质准入

- [ ] 固定 Operator、CRD、Tenant API、MinIO 镜像版本和 SHA-256。
- [ ] 配置模型增加 namespace、tenant name、StorageClass、服务器数、卷数和容量。
- [ ] 预检查 Kubernetes 版本、StorageClass、容量格式、Worker 数量和 PVC 数量。
- [ ] 仅将非敏感配置写入安装快照。
- [ ] 验证发布包不依赖在线 Chart、Kustomize URL 或漂移镜像标签。
- [ ] 缺失、篡改或版本不兼容时在任务创建前失败。

### 阶段 2：Operator 与 Tenant 自动部署

- [ ] 覆盖 Operator 已存在/不存在、Secret 已存在/不存在、Tenant 重复应用测试。
- [ ] 应用固定 Operator、CRD 和 RBAC 清单，等待 CRD 与 Deployment 就绪。
- [ ] 首次安装从安全随机源生成凭据，通过标准输入创建 Secret。
- [ ] 已有 Secret 时复用，不重新生成或回显。
- [ ] 只渲染任务目录内的 Tenant CR，不修改发布介质原文件。
- [ ] 应用 Tenant CR 并等待固定版本定义的成功条件。
- [ ] 验证 Pod Ready、PVC Bound、Service 和 Loki 所需最小对象存储链路。
- [ ] 所有等待设置超时并输出脱敏诊断。
- [ ] MinIO 失败时阻止本组 Loki/Alloy，但不影响其他组件组。

### 阶段 3：真实环境操作文档

最终操作文档必须基于实际完成的代码、接口、资源名称和固定版本编写，禁止提前使用占位命令冒充可执行步骤。文档至少包含：

- [ ] 适用版本、支持的 Kubernetes 版本和已验证拓扑。
- [ ] 服务器、Worker、磁盘、StorageClass、容量、PVC 数量和网络端口检查表。
- [ ] 离线包、镜像、Operator/CRD/Tenant 版本及 SHA-256 核对命令。
- [ ] 测试前数据库、集群资源和持久化数据备份要求。
- [ ] KubeFoundry 页面配置字段、推荐测试值和禁止使用的生产参数。
- [ ] 发起预检查、启动安装、记录任务 ID 和观察任务状态的步骤。
- [ ] 使用 `kubectl` 验证 CRD、Operator、Tenant、Pod、PVC、Service 和事件的命令。
- [ ] 验证 S3 服务和 Loki 最小对象存储链路的方法，不在命令行历史中暴露凭据。
- [ ] 重复执行、失败后重试和服务重启恢复的测试步骤。
- [ ] 常见故障诊断：PVC Pending、Pod Pending、镜像缺失、证书、容量、调度和超时。
- [ ] 日志与验收证据采集清单，明确需要脱敏的字段。
- [ ] 停止测试、保留现场、回滚应用版本和人工清理边界。
- [ ] 醒目标注：未经单独确认不得删除 PVC、PV、Secret 或 MinIO 数据目录。

文档中的地址、节点名、StorageClass 和容量使用明确的示例占位符；不得写入真实密码、Access Key、Secret Key、Token 或私钥。

### 阶段 4：真实环境验收

- [ ] 严格按操作文档在隔离的真实测试环境执行，不临时补充未记录步骤。
- [ ] 完成首次安装并验证 Operator、Tenant、PVC、Pod、Service 和 S3 链路。
- [ ] 完成一次幂等重试，确认 Secret、Tenant 和 PVC 不被重复创建或替换。
- [ ] 完成一个可恢复故障场景，例如介质缺失或临时调度失败；不得以删除数据验证恢复。
- [ ] 验证 MinIO 失败时其他无依赖组件组继续执行。
- [ ] 采集任务 ID、版本、校验和、资源状态和脱敏日志作为验收证据。
- [ ] 根据实际执行修正文档，确保第二位操作者可以独立复现。

### 安全复核门禁

- [ ] 复核随机凭据强度、Secret 创建命令和 shell 回显控制。
- [ ] 复核日志脱敏、异常路径和测试夹具不保存真实凭据。
- [ ] 复核失败与重试不删除 PVC、Secret 或用户数据。
- [ ] 复核操作文档中的命令不会误操作生产命名空间、默认 StorageClass 或已有数据。
- [ ] 复核真实环境测试具有明确目标集群、namespace 和停止条件。

### 最终验收

- 无浏览器、Console 和在线下载即可完成 Operator/Tenant 部署。
- 重复执行复用 Secret、Tenant 和 PVC，不产生冲突资源。
- PVC、Pod、Service、S3 和 Loki 最小对象存储链路验证通过。
- 故障、重试和部分成功状态符合任务 7 至任务 10 的状态模型。
- 敏感信息不进入日志、事件、快照、API、Git 或验收附件。
- `MinIO真实环境部署与验证操作手册.md` 已由另一位操作者按文档复现并完成签字确认。
- 全部 v0.3.1 自动化测试、发布包检查和最终文档检查通过。

### 建议提交

```text
组件：完成MinIO自动部署与真实环境操作手册
```

## 18. 统一测试矩阵

| 范围 | 必测场景 | 自动化层级 |
| --- | --- | --- |
| 节点唯一性 | 新增、编辑、自身排除、大小写、IP 规范化、并发 | Java 单元/集成、Vue |
| 全节点测试 | 全成功、部分失败、重复提交、失败重试 | Java 服务/API、Vue |
| 组件开关 | 单组、全关、已安装组、旧请求兼容 | Java API/计划、Vue |
| CoreDNS | 无规则、已有规则、重复执行、单节点 | Bash、计划测试、真实集群 |
| NFS | 未挂载、正确挂载、冲突源、冲突类型、超时 | Bash、真实测试节点 |
| MinIO | 首装、重试、Secret 复用、PVC Pending、就绪超时 | Bash、Java 预检查、真实集群 |
| 组失败隔离 | 首组失败、中间组失败、公共前置失败、全失败 | Java 集成、Vue |
| 任务历史 | 多任务、切换、迟到响应、SSE、刷新、跨集群 | Java API、Vue 路由/视图 |
| 安全 | 凭据脱敏、路径边界、系统文件受管块 | Java、Bash、专项复核 |
| 发布包 | 离线资源、双架构、篡改、缺失资源 | Bash 冒烟/打包测试 |

## 19. 提交顺序建议

建议按以下顺序形成可审查提交，每次提交均应包含对应测试：

1. `文档：冻结v0.3.1开发契约与风险门禁`
2. `节点：保证集群内主机名和IP唯一`
3. `前端：增加全部节点测试与重复校验`
4. `组件：移除Kubemate安装总开关`
5. `安装：自动配置CoreDNS副本反亲和`
6. `脚本：增强NFS挂载幂等与超时保护`
7. `任务：隔离Kubemate组件组安装失败`
8. `前端：展示组件安装部分成功与跳过状态`
9. `任务：按任务ID展示集群安装历史`
10. `测试：完成v0.3.1非MinIO功能联合回归`
11. `组件：完成MinIO自动部署与真实环境操作手册`

不得把数据库迁移、状态机重构、NFS 系统文件修改和 MinIO 凭据处理压缩到同一个提交中。

## 20. 进度维护规则

- 开始任务时将对应首个步骤标为进行中，任务验收完成后再整体勾选。
- 代码完成但缺少真实环境或专项复核时，任务不得标为完成。
- 新发现的范围必须先回写设计和本计划，再进入实现。
- 延期项记录原因、影响、替代验证和后续版本，不得直接删除。
- 每个里程碑结束后更新需求记录状态和验收证据链接。

## 21. 完成定义

只有同时满足以下条件，v0.3.1 开发计划才可关闭：

- 任务 1 至任务 11 均完成代码、自动化测试和文档同步，MinIO 作为最后一个任务完成。
- 七项优化全部达到设计文档中的验收方向。
- 数据库迁移不丢失节点、任务、组件配置和历史日志。
- CoreDNS、NFS、MinIO 脚本连续执行两次均满足幂等要求。
- 组件组失败隔离、部分成功、重试和中断恢复状态一致。
- 多任务 ID 查看、刷新和 SSE 切换无数据串流。
- 高风险改动完成专项复核，真实环境验收不使用生产集群。
- Java、Vue、Bash、打包、LF、敏感信息和 Git 范围检查全部通过。
- 中文设计、开发计划、接口、使用、部署和验收文档与实现一致。
- 已交付并复现 `MinIO真实环境部署与验证操作手册.md`。
- 发布说明明确 MinIO 固定版本、上游归档风险和 ARM64 实际验收范围。
