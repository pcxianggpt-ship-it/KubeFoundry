# KubeFoundry v0.3.2 开发计划

## 1. 文档信息

| 项目 | 内容 |
| --- | --- |
| 目标版本 | v0.3.2 |
| 状态 | 开发计划初稿，待评审，尚未开发 |
| 制定日期 | 2026-08-20 |
| 当前工作分支 | `codex/v0.3.2-design` |
| 需求依据 | [优化需求记录.md](./优化需求记录.md) |
| 设计依据 | [KubeFoundry-v0.3.2-优化设计.md](./KubeFoundry-v0.3.2-优化设计.md) |

## 2. 开发目标

本计划把 v0.3.2 的九项需求拆分为可独立实现、测试、复核和提交的任务，最终交付应满足：

1. 安装或组件安装失败后，可创建新的续跑任务并保留原任务记录。
2. 每个安装步骤执行前后均使用统一验证脚本判断目标状态，已满足的步骤安全跳过。
3. 本地 YUM 仓库在 SELinux Enforcing 环境中可从本机和远程节点通过 HTTP 访问。
4. 安装计划与进度按部署单元分组，并保持叶子步骤、节点状态和日志可追踪。
5. Kubemate 页面支持 MinIO PVC、CPU 和内存参数配置，并在安装开始时校验至少 4 个正式工作节点。
6. 完整安装计划的最后一个单元完成 etcd 备份并校验快照。
7. 安装确认页节点清单显示 IP。
8. 安装失败且尚未安装 Helm 时仍能重置，重置会清理 KubeFoundry 受管参数配置。
9. Redis Sentinel 使用冻结的 Bitnami Redis Chart 和完整离线介质完成部署。

## 3. 实施约束

- 先完成需求 3.9，再完成需求 3.4；不得为了后续页面或组件功能绕过这两个优先项。
- 所有新增和修改文本文件必须使用 LF。
- 不修改既有 Flyway 迁移，只新增 V15 及后续迁移；迁移编号开始前先检查主分支是否出现冲突版本。
- 前端不能自行决定续跑步骤、跳过规则、组件依赖或任务终态；权威计划由后端和不可变快照生成。
- 续跑必须创建新任务 ID，原任务、步骤、事件、日志和快照保持只读。
- 只有验证脚本明确返回“目标未满足”时才执行安装；验证异常不得触发有副作用的安装命令。
- Bash 脚本必须非交互、幂等、有超时，不得嵌套 SSH，不得在线下载，不得修改离线介质原文件。
- 密码、Token、私钥、Join 命令、Kubernetes Secret 和完整 kubeconfig 不得进入普通日志、事件、API 或错误消息。
- 重置只清理能够证明由 KubeFoundry 管理的配置，无法确认所有权时安全失败，不覆盖用户修改。
- Redis、MinIO、etcd、安装状态机、数据库迁移、SSH 执行和破坏性重置属于高风险范围，进入实现和合并前均需专项复核。
- Git 提交使用中文说明，一个提交只承担一个清晰职责；提交前复核暂存范围，不包含 `.superpowers/`、`dist/`、本地配置和无关离线介质。

## 4. 开发前决策门禁

### 门禁 A：续跑与验证契约

- [x] 批准“续跑创建新任务，不原地恢复旧任务”。
- [x] 批准验证退出码：`0=已满足`、`10=未满足`、`20=验证异常`、`21=验证超时`。
- [x] 批准前置验证通过使用 `skipped + PREVERIFY_SATISFIED`，不新增数据库终态。
- [x] 批准 v0.3.1 历史任务默认不可续跑，仅 v0.3.2 带完整快照和步骤键的任务可续跑。
- [x] 批准初始化步骤通过独立产物恢复脚本重新生成短时 Join 产物。

门禁 A 已于 2026-08-22 确认通过，任务 2 至任务 6 可在完成任务 1 的其余基线检查后开始编码。

若后续调整门禁 A 已确认的契约，任务 2 至任务 6 应暂停并重新完成评审。

### 门禁 B：配置清理边界

- [ ] 批准 sysctl、modules、limits 等配置迁移到 KubeFoundry 独立 drop-in 文件。
- [ ] 确认 `/etc/hosts`、`fstab`、`exports` 使用成对标记块的所有权规则。
- [ ] 确认对已经被用户修改的文件采用“拒绝覆盖并报告冲突”。
- [ ] 确认 v0.3.1 已安装节点缺少基线备份时允许清理的边界。
- [ ] 明确软件包、firewalld、DNS 和原始 hostname 是否不在 v0.3.2 自动恢复范围内。

门禁 B 未通过时，任务 11 和任务 12 只允许增加只读清单与测试，不执行实际删除或恢复逻辑。

### 门禁 C：Redis 离线准入

- [ ] 冻结 Bitnami Redis Chart 版本和 SHA-256。
- [ ] 核对许可证、已知安全问题、Kubernetes v1.30.14 与 amd64/arm64 兼容性。
- [ ] 冻结 Redis、Sentinel、Exporter 等全部镜像清单及私有仓库名称。
- [ ] 冻结 Pod/Sentinel 数量、StorageClass、PVC 容量和密码生成/保存方式。
- [ ] 确定现有旧 `redis-ha` 目录的归档或移除方式，不与 Bitnami Chart 混用。

门禁 C 未通过时，任务 13 不启用 Redis 组件组。

### 门禁 D：etcd 备份策略

- [ ] 冻结备份目录，确认不位于 etcd 数据目录内。
- [ ] 冻结执行周期、默认保留数量和单次超时。
- [ ] 确认 `etcdctl/etcdutl` 来源、版本和离线可用性。
- [ ] 确认备份失败是否使完整安装任务失败。
- [ ] 冻结 systemd service/timer、脚本和快照文件命名。

门禁 D 未通过时，任务 14 只允许完成脚本原型和测试，不接入完整安装计划。

### 门禁 E：MinIO 参数默认值

- [ ] 确认默认值为 `10Gi/250m/2/512Mi/4Gi`，或给出替代值。
- [ ] 冻结 Kubernetes Quantity 校验规则和 request 不大于 limit 的规则。
- [x] 冻结安装准入规则：安装开始时按集群配置统计，至少需要 4 个 `is_draft=false` 且包含 `worker` 角色的正式节点；配置编辑和保存阶段不校验数量。
- [x] 明确不设置“至少 4 个 Worker 为 Ready”的专项运行门禁；安装仅执行 Tenant、Pod 和 PVC 通用就绪验证。
- [ ] 确认 v0.3.2 不支持已安装 MinIO 在线扩容或资源调整。

门禁 E 未通过时，任务 10 不冻结公共接口字段。

## 5. 任务依赖

```text
任务 1 基线与决策门禁
  -> 任务 2 任务血缘、步骤元数据与数据库迁移
       -> 任务 3 双重验证执行引擎
            -> 任务 4 验证脚本迁移与产物恢复
                 -> 任务 5 续跑后端服务与接口
                      -> 任务 6 续跑前端闭环

任务 3 + 任务 4
  -> 任务 7 YUM 仓库 HTTP 权限修复

任务 2
  -> 任务 8 安装进度部署单元分组

任务 1
  -> 任务 9 安装确认页显示节点 IP
  -> 任务 10 MinIO 资源参数配置（需门禁 E）

任务 2 + 任务 4 + 门禁 B
  -> 任务 11 安装配置所有权改造
       -> 任务 12 失败安装重置与 Helm 条件清理

任务 3 + 任务 4 + 门禁 C
  -> 任务 13 Redis Sentinel 离线部署

任务 3 + 任务 4 + 任务 12 + 门禁 D
  -> 任务 14 etcd 备份最终单元

任务 2 至任务 14
  -> 任务 15 联合回归、文档、发布包与最终验收
```

任务 2 至任务 6 会集中修改 `InstallStep`、`RemoteStepRunner`、`JobService`、安装快照和公共 API，必须串行实施和复核。任务 7、任务 9在文件边界不冲突时可独立进行；任务 10 与任务 13 都会修改组件目录、组件服务和计划工厂，不得同时修改相同文件。

## 6. 里程碑与工作量参考

以下为单人串行开发的人日参考，不含等待外部评审、真实集群排期、离线镜像制作和缺陷返工时间。

| 里程碑 | 任务 | 参考工作量 | 完成标志 |
| --- | --- | --- | --- |
| M0 决策与基线 | 任务 1、门禁 A～E | 1～3 人日 | 高风险契约冻结，基线测试可复现 |
| M1 失败续跑 | 任务 2～6 | 12～18 人日 | 基础与组件任务均可安全续跑 |
| M2 YUM 修复 | 任务 7 | 2～4 人日 | SELinux Enforcing 下本机和远程 HTTP 200 |
| M3 展示与配置 | 任务 8～10 | 5～8 人日 | 分组、节点 IP、MinIO 参数闭环 |
| M4 重置可靠性 | 任务 11～12 | 6～10 人日 | 无 Helm 失败集群可重置，受管配置无残留 |
| M5 新增单元 | 任务 13～14 | 7～12 人日 | Redis Sentinel 与 etcd 备份真实环境通过 |
| M6 发布验收 | 任务 15 | 3～5 人日 | 全量测试、文档和离线发布包通过 |

总工作量参考为 36～60 人日。约三十项验证脚本的迁移、真实故障注入、Redis 镜像准备和配置基线恢复可能增加工作量。

## 7. 任务 1：基线、接口与风险门禁

### 目标

冻结 v0.3.2 的状态机、数据库迁移、公共接口、验证脚本契约和离线组件版本，建立可复现测试基线。

### 主要文件

- 修改：`doc/v0.3.2/KubeFoundry-v0.3.2-优化设计.md`
- 修改：`doc/v0.3.2/KubeFoundry-v0.3.2-开发计划.md`
- 新增：`doc/v0.3.2/技术决策与风险评审记录.md`
- 检查：Java、Vue、Bash、LF、敏感信息和打包测试入口。

### 实施步骤

- [ ] 完成门禁 A～E，逐项记录批准、调整、延期或移出范围结论。
- [x] 检查当前 Flyway 最大版本：现有迁移最高为 `V14__job_timeline_and_step_reason.sql`，v0.3.2 从 V15 开始新增迁移。
- [ ] 冻结 `source_job_id`、`run_mode`、步骤键和部署单元字段命名。
- [ ] 冻结续跑接口、准入错误码、步骤状态原因码和 SSE 事件字段。
- [ ] 生成所有安装步骤、目标范围、验证脚本、资源和输出产物清单。
- [ ] 标出验证脚本中的嵌套 SSH、交互命令、无超时检查和敏感输出。
- [x] 记录 Maven、Vitest、Bash、LF 和敏感信息检查的基线结果。
- [ ] 确认前端、后端、脚本、Flyway 和离线介质必须同版本发布。

### 2026-08-22 测试基线记录

执行环境：Windows 11 amd64、Java 17.0.19、Maven 3.9.6、Node.js v24.11.0、npm 11.6.1、WSL Bash 5.1.8。

| 检查项 | 结果 | 基线说明 |
| --- | --- | --- |
| Flyway 迁移 | 通过 | 现有 V1～V14 共 14 个迁移可在 H2 测试库完整执行；v0.3.2 预留 V15 及后续版本 |
| Maven 后端测试 | 通过 | 204 个测试，0 失败、0 错误、19 跳过 |
| Vitest 前端测试 | 通过 | 15 个测试文件、52 个用例全部通过 |
| 前端生产构建 | 通过，存在警告 | 构建成功；保留现有 Rollup 注释和大于 500 kB 分块提示作为基线警告 |
| LF 检查 | 通过 | `scripts/ci/check-lf.sh` 退出码为 0 |
| 敏感信息检查 | 通过 | `scripts/ci/check-secrets.sh` 退出码为 0 |
| Bash 回归脚本 | 部分通过 | 9 个入口中 8 个通过；修复 WSL JDK 配置后，`test_java_web_smoke.sh` 已能启动 Java 后端和 Vite，但因代理健康检查未就绪失败 |
| Web 双架构打包部署脚本 | 通过 | x86_64 与 aarch64 测试包均成功生成并完成测试模式部署 |

已知基线事项：

- Maven 测试日志存在 Windows SSH 测试线程关闭警告，但测试终态为成功。
- Flyway 输出 H2 2.2.224 高于当前已验证支持的 2.2.220 警告，但 V1～V14 校验和迁移均成功；依赖升级前应纳入兼容性复核。
- WSL 启动时存在 localhost/NAT 提示，不影响其余 Bash 检查和回归脚本。
- WSL 已配置 `JAVA_HOME=/opt/jdk-17.0.17`，并通过系统 alternatives 让非登录脚本可直接调用 Java 17.0.17；原“缺少命令: java”问题已解决。
- `test_java_web_smoke.sh` 当前剩余问题是 Java 后端和 Vite 均已启动，但代理健康检查未就绪；需要单独排查 WSL localhost/NAT 或代理访问链路，在解决前不得将该入口记为通过。

### 验收

- 五个门禁都有可追踪结论。
- 数据库、API、验证退出码和历史兼容策略不存在阻塞性歧义。
- 基线测试结果和既有失败清单可复现。

### 建议提交

```text
文档：冻结v0.3.2开发契约与风险门禁
```

## 8. 任务 2：任务血缘、步骤元数据与数据库迁移

### 目标

为续跑血缘、稳定步骤键和部署单元元数据提供持久化基础，并保证历史任务仍可查询。

### 主要文件

- 新增：`web/backend-java/src/main/resources/db/migration/V15__job_resume_and_stage_metadata.sql`
- 修改：`job/Job.java`
- 修改：`job/JobStep.java`
- 修改：`job/JobRepository.java`
- 修改：`job/JobService.java`
- 修改：`api/JobController.java`
- 修改：`api/ClusterJobController.java`
- 修改：`installer/InstallStep.java`
- 修改：`SchemaMigrationTest.java`、`JobServiceTest.java`、API 契约测试。

### 实施步骤

- [ ] 先编写 V1/V14 升级到 V15 的迁移测试。
- [ ] 为 `jobs` 增加来源任务外键和 `normal/resume` 运行模式。
- [ ] 为 `job_steps` 增加步骤键、部署单元键/名称/顺序和组内顺序。
- [ ] 使用稳定 `legacy-*` 值迁移旧任务，禁止通过中文名称推断可续跑步骤。
- [ ] 在实体构造器和 `JobDefinition/StepDefinition` 中传递新字段。
- [ ] 在任务和步骤响应中返回新字段，同时保持旧字段兼容。
- [ ] 增加来源任务同集群、不可自引用和不可循环引用校验。
- [ ] 增加索引并验证任务列表、步骤列表和历史任务性能。

### 验收

- 新任务持久化完整血缘和部署单元元数据。
- 历史任务可以展示但不被错误识别为可续跑任务。
- 迁移重复执行、全新数据库和旧数据库升级测试均通过。

### 建议提交

```text
任务：持久化续跑血缘与安装单元元数据
```

## 9. 任务 3：步骤执行前后双重验证引擎

### 目标

改造远程步骤执行，使安装前验证、按需资源上传、安装执行和安装后验证形成统一且可审计的状态机。

### 主要文件

- 修改：`installer/InstallStep.java`
- 修改：`installer/RemoteStepRunner.java`
- 修改：`installer/BaseInstallPlanFactory.java`
- 修改：`installer/ComponentPlanFactory.java`
- 修改：`installer/ComponentMediaService.java`
- 修改：`job/JobService.java`
- 修改：`job/JobStepNode.java`
- 修改：`RuntimeEnvRenderer.java`
- 修改：`RemoteStepRunnerTest.java`、计划工厂和任务服务测试。

### 实施步骤

- [ ] 先覆盖验证退出码 `0/10/20/21/其他` 和前后验证组合测试。
- [ ] 为步骤增加 `INSTALL/VALIDATION/MAINTENANCE` 类型及验证脚本路径。
- [ ] 前置验证只上传 runtime、验证脚本和必要公共库，不解析大体积安装资源。
- [ ] 前置验证为 `0` 时节点标记 `skipped/PREVERIFY_SATISFIED`。
- [ ] 只有退出码 `10` 才解析、校验、上传资源并执行安装脚本。
- [ ] 安装退出码为 0 后再次运行验证脚本；非 0 以 `POSTVERIFY_FAILED` 失败。
- [ ] 验证异常和验证超时分别记录稳定原因，禁止进入安装。
- [ ] 节点混合成功/验证跳过时正确汇总步骤状态。
- [ ] 事件增加安全的 `verification_phase=before/after`，不新增不兼容终态。
- [ ] 验证脚本、安装脚本、资源和输出证据分别保存 SHA-256。

### 验收

- 已满足步骤不会上传安装介质或执行安装脚本。
- 验证异常不会被误判成目标未安装。
- 安装后验证未通过时步骤不能标记成功。
- 组件组失败隔离和基础安装失败中止行为无回归。

### 建议提交

```text
安装：增加步骤执行前后双重验证
```

## 10. 任务 4：验证脚本迁移与产物恢复

### 目标

让所有安装步骤拥有符合新契约的本地目标验证脚本，并解决跳过集群初始化后 Join 产物缺失问题。

### 主要文件

- 修改：`scripts/verify/phase2_k8s_base/*.sh`
- 修改：`scripts/verify/phase3_ecosystem/*.sh`
- 新增：缺失步骤的 `verify-<step-key>.sh`
- 新增：集群初始化步骤产物恢复脚本。
- 修改：`BaseInstallPlanFactory.java`、`ComponentPlanFactory.java`
- 新增或修改：`scripts/tests/test_verify_contract.sh`
- 修改：各 phase2/phase3 Bash 测试。

### 实施步骤

- [ ] 建立步骤与验证脚本一一对应的清单测试。
- [ ] 移除验证脚本对 `PROJECT_ROOT`、`config.sh` 和嵌套 SSH 的依赖。
- [ ] 所有验证只检查当前目标节点，并读取 `runtime.env` 白名单变量。
- [ ] 统一 `0/10/20/21` 退出码和中文摘要。
- [ ] 为 kubectl、helm、curl、systemctl、yum 和文件系统检查增加超时。
- [ ] 将内联 `verifyCommand` 迁移到脚本，验证结果保持或增强。
- [ ] 为 `18-init-k8s-cluster` 实现受控 Join 产物恢复，禁止输出 Token。
- [ ] 检查全部验证脚本只读、幂等、无 CRLF、无交互命令。
- [ ] 对同一模拟环境连续执行两次，验证结果一致。

### 验收

- `INSTALL` 步骤验证脚本覆盖率为 100%。
- 缺失验证脚本、符号链接、CRLF 或非法退出码会使测试失败。
- 镜像仓库、Kubernetes 初始化、节点加入、NFS、MinIO 等关键步骤均覆盖“已满足/未满足/异常”。
- 初始化步骤被跳过时，下游节点加入仍可获得当前任务产物。

### 建议提交

```text
验证：统一安装步骤验证脚本契约
```

## 11. 任务 5：续跑后端服务与接口

### 目标

从失败、已中断或部分成功任务创建新的续跑任务，严格复用来源快照并执行完整验证驱动计划。

### 主要文件

- 新增：`installer/InstallResumeService.java`
- 修改：`InstallationSnapshotService.java`
- 修改：`InstallationSnapshotPayload.java`
- 修改：`InstallService.java`
- 修改：`ComponentInstallService.java`
- 修改：`InstallerAdmission.java`
- 修改：`ClusterJobController.java`
- 修改：全局异常映射。
- 新增：续跑服务、并发准入、快照一致性和 API 测试。

### 实施步骤

- [ ] 实现来源任务类型、终态、集群归属和快照完整性校验。
- [ ] 拒绝成功任务、历史兼容任务、跨集群任务和活动任务续跑。
- [ ] 校验当前节点身份、SSH 参数、架构和关键路径与来源快照一致。
- [ ] 从来源快照重建同类型计划，不读取当前可变组件配置。
- [ ] 创建新任务并保存 `source_job_id/run_mode=resume`。
- [ ] 将来源介质校验信息复制到新任务快照；前置验证未满足后再校验实际资源。
- [ ] 保证旧任务事件、日志和状态不被新任务回调修改。
- [ ] 处理续跑任务再次失败后继续续跑的血缘链，禁止循环。
- [ ] 返回稳定错误码和脱敏消息。

### 验收

- 基础安装和组件安装均能创建新续跑任务。
- 续跑使用来源快照，新旧任务可独立查看。
- 配置或节点发生不安全变化时拒绝续跑。
- 同一集群只能有一个活动安装类或重置任务。

### 建议提交

```text
任务：支持失败安装创建续跑任务
```

## 12. 任务 6：续跑前端与任务状态展示

### 目标

在失败任务详情提供安全续跑入口，展示来源任务关系、验证阶段和“已验证并跳过”状态。

### 主要文件

- 修改：`web/frontend/src/api/client.js`
- 修改：`web/frontend/src/views/JobExecutionView.vue`
- 修改：`web/frontend/src/views/InstallOverviewView.vue`
- 修改：`web/frontend/src/components/jobs/jobStatus.js`
- 修改：`JobExecutionView`、安装流程和 API 客户端测试。

### 实施步骤

- [ ] 增加续跑 API 客户端和契约测试。
- [ ] 仅对允许状态和任务类型展示“续跑”按钮。
- [ ] 点击后防止重复提交，接受后跳转新任务 ID。
- [ ] 展示来源任务链接和运行模式，允许返回查看原失败任务。
- [ ] 根据 `status_reason` 区分“已验证并跳过”和“因依赖跳过”。
- [ ] 展示执行前验证、安装和执行后验证的安全阶段消息。
- [ ] 续跑失败时保留当前页面和错误信息，不伪造新任务。
- [ ] 覆盖刷新、任务切换、迟到 SSE 和终态重载。

### 验收

- 用户可从失败任务发起续跑并进入新任务详情。
- 原任务历史不变化，来源关系可追踪。
- 验证跳过和依赖阻塞的文案、颜色和进度不同。

### 建议提交

```text
前端：增加安装任务续跑入口
```

## 13. 任务 7：YUM 仓库 HTTP 权限修复

### 目标

使用最小权限 ACL 和正确 SELinux 标签修复仓库元数据 HTTP 403，并把 HTTP 200 纳入步骤前后验证。

### 主要文件

- 修改：`scripts/steps/phase2_k8s_base/10-setup-yum-source.sh`
- 修改：`scripts/steps/phase2_k8s_base/12-setup-k8s-repo.sh`
- 修改：对应两个验证脚本。
- 修改：离线 YUM 包清单，确保包含 ACL/SELinux 工具。
- 新增：YUM 权限和验证脚本自动化测试。

### 实施步骤

- [ ] 先构造父目录缺少搜索权限导致 403 的失败测试。
- [ ] 校验仓库元数据存在并确认 httpd 实际运行账户。
- [ ] 仅为 httpd 账户设置父目录遍历和仓库只读 ACL。
- [ ] 登记并恢复 `httpd_sys_content_t`，保持 SELinux Enforcing。
- [ ] 本机请求元数据返回 200 后才完成服务端步骤。
- [ ] 客户端步骤仅启用目标仓库执行 `yum makecache`。
- [ ] 验证脚本覆盖文件、ACL、SELinux、HTTP 和 YUM 缓存。
- [ ] 验证不使用 `777`、不关闭 SELinux、不改变非仓库内容所有权。

### 验收

- 仓库节点本机和至少一个远程节点访问元数据均返回 200。
- 所有节点 `yum makecache` 成功，httpd 日志无路径搜索权限错误。
- 重复运行步骤不会累积无效 ACL 或破坏现有权限。

### 建议提交

```text
安装：修复YUM仓库HTTP访问权限
```

## 14. 任务 8：安装计划和进度按部署单元分组

### 目标

使用持久化部署单元元数据把三十多项叶子步骤组织为清晰分组，保持历史任务和日志定位能力。

### 主要文件

- 修改：`BaseInstallPlanFactory.java`
- 修改：`ComponentPlanFactory.java`
- 修改：`InstallPlanAssembler.java`
- 修改：`InstallerController.java`
- 修改：`JobController.java`
- 修改：`web/frontend/src/components/jobs/JobStageList.vue`
- 修改：`web/frontend/src/views/JobExecutionView.vue`
- 新增：部署单元折叠组件及相关测试。

### 实施步骤

- [ ] 为所有步骤填写固定 `stage_key/name/order` 和组内顺序。
- [ ] 安装计划预览返回部署单元元数据。
- [ ] 任务创建时持久化元数据，历史任务不依赖当前计划重算。
- [ ] 前端按 `stage_key` 分组，部署单元内保留叶子步骤和节点详情。
- [ ] 当前执行或首个失败单元自动展开，其余默认折叠。
- [ ] 正确汇总成功、失败、执行中、等待、已验证跳过和依赖阻塞。
- [ ] 整体进度继续按叶子步骤计算。
- [ ] NFS 三个步骤归入同一“部署 NFS 组件”单元。

### 验收

- 页面不再平铺三十多项任务。
- 所有叶子步骤、节点、状态、日志和错误仍可定位。
- 历史任务、组件补装、续跑和重置页面不发生错误分组。

### 建议提交

```text
前端：按部署单元展示安装进度
```

## 15. 任务 9：安装确认页显示节点 IP

### 目标

在安装前逐项展示主机名、IPv4、角色和免密验证状态，方便核对安装范围。

### 主要文件

- 修改：`web/frontend/src/views/InstallConfirmView.vue`
- 修改：`web/frontend/src/styles.css`
- 修改：`InstallFlow.test.js` 或新增确认页测试。

### 实施步骤

- [ ] 节点清单增加 IPv4 列或明确字段。
- [ ] 桌面端对齐展示，窄屏换行但不隐藏 IP。
- [ ] 空 IP 或非法 IP 显示错误并禁止开始安装。
- [ ] 保留镜像仓库摘要中的主机名和 IP。
- [ ] 增加多角色、长主机名和移动端布局测试。

### 验收

- 每个安装目标节点均明确显示 IP。
- 无合法 IP 时不能进入安装任务。

### 建议提交

```text
前端：在安装确认页展示节点IP
```

## 16. 任务 10：MinIO PVC、CPU 和内存配置

### 目标

在 Kubemate 组件页配置 MinIO 资源参数，并通过快照、运行环境、清单渲染和后置验证形成闭环。

### 主要文件

- 修改：`cluster/ClusterComponentService.java`
- 修改：`installer/InstallationSnapshotPayload.java`
- 修改：`installer/RuntimeSettings.java`
- 修改：`installer/RuntimeEnvRenderer.java`
- 修改：`scripts/steps/phase3_ecosystem/49-install-minio.sh`
- 修改：`scripts/verify/phase3_ecosystem/verify-49-install-minio.sh`
- 修改：`web/frontend/src/views/KubemateComponentsView.vue`
- 修改：Java、Vue、Bash 和 API 契约测试。

### 实施步骤

- [ ] Kubemate 页面允许编辑并保存 MinIO 配置，不根据 Worker 数量禁用组件开关。
- [ ] 创建安装或组件补装任务时，按安装快照中的集群配置统计正式 Worker；节点不足时返回 `MINIO_WORKER_COUNT_INSUFFICIENT`，且不创建任务、不执行步骤。
- [ ] 错误详情只返回 `required_workers=4` 和 `actual_workers`，不返回节点凭据或内部异常。
- [ ] 已启用后 Worker 数量减少时保留配置，但下次安装或组件补装准入失败。
- [ ] 确认安装准入只复核正式 Worker 数量，不增加 Ready Worker 数量判断。
- [ ] 保留 MinIO Tenant、Pod 和 PVC 的通用安装后就绪验证及超时诊断。
- [ ] 增加五个强类型配置字段和默认值。
- [ ] 实现 CPU、内存、存储 Quantity 解析及 request/limit 比较。
- [ ] 拒绝未知字段、零值、负值、类型错误和 request 大于 limit。
- [ ] 前端增加字段级即时校验和单位示例。
- [ ] 配置保存后进入不可变安装快照。
- [ ] 使用白名单 `KF_MINIO_*` 环境变量传入远端。
- [ ] 在任务工作目录复制清单并用 `yq` 精确渲染，不修改介质原文件。
- [ ] 后置验证比对 Tenant、PVC 和 Pod resources 的实际值。
- [ ] 确认 API、日志和渲染证据不包含 MinIO 凭据。

### 验收

- MinIO 配置可正常编辑和保存，不因 Worker 数量被提前阻止。
- 安装开始时，0～3 个正式 Worker 被准入校验拒绝；恰好 4 个正式 Worker 时可进入安装。
- Ready Worker 少于 4 个时不因数量专项门禁提前拒绝；实际 Tenant、Pod 和 PVC 仍须通过通用就绪验证。
- 合法参数可保存、加载、冻结并应用。
- 非法参数前后端均拒绝，后端规则为最终权威。
- 已安装 MinIO 配置保持只读。
- 实际 Tenant、PVC 和 Pod resources 与页面配置一致。

### 建议提交

```text
组件：支持配置MinIO存储与资源参数
```

## 17. 任务 11：安装配置所有权改造

### 目标

把安装脚本对共享系统文件的直接修改迁移为可证明所有权的独立文件、标记块或受保护基线备份，为安全重置提供依据。

### 主要文件

- 修改：`scripts/steps/phase2_k8s_base/10-setup-yum-source.sh`
- 修改：`11b-setup-hostname.sh`
- 修改：`12-setup-k8s-repo.sh`
- 修改：`15-environment-config.sh`
- 修改：`16-install-containerd.sh`
- 修改：`18-init-k8s-cluster.sh`
- 修改：NFS 与 etcd 相关安装脚本。
- 新增：受管配置清单/基线备份公共 Bash 函数。
- 修改：对应验证和 Bash 测试。

### 实施步骤

- [ ] 完成所有写入 `/etc`、systemd、crontab、hostname 和服务状态的清单。
- [ ] sysctl、modules、limits 改为 KubeFoundry 独立 drop-in 文件。
- [ ] hosts、fstab、exports 使用唯一成对标记块并验证完整性。
- [ ] YUM repo 和 containerd Registry 配置增加稳定所有权标记。
- [ ] 必须替换的文件在安装前创建 `0700/0600` 基线备份和 SHA-256 清单。
- [ ] 记录安装后 SHA-256，供重置时检测用户后续修改。
- [ ] 安装脚本重复执行不得增加重复行或覆盖用户未受管配置。
- [ ] 快照和日志中只记录安全路径、校验和和状态，不记录 Secret。

### 验收

- KubeFoundry 新增配置均能被稳定识别。
- 重复安装不会产生重复配置。
- 用户配置与受管配置边界清晰，基线备份权限正确。

### 建议提交

```text
安装：标记并记录KubeFoundry受管配置
```

## 18. 任务 12：失败安装重置与 Helm 条件清理

### 目标

允许使用失败安装快照重置集群，根据实际成功步骤决定是否清理 Helm 组件，并清除所有受管配置。

### 主要文件

- 修改：`installer/ClusterResetService.java`
- 修改：`installer/ResetPlanFactory.java`
- 修改：`scripts/steps/reset/reset-kubemate-components.sh`
- 修改：`scripts/steps/reset/reset-kubernetes-node.sh`
- 修改：`scripts/verify/reset/verify-reset-kubernetes-node.sh`
- 修改：`ResetConfirmView.vue`
- 修改：重置服务、计划、API、Bash 和前端测试。

### 实施步骤

- [ ] 准入允许最近安装任务为成功、失败或中断，仍要求快照和破坏性确认。
- [ ] 活动安装、续跑、组件安装或重置存在时拒绝提交。
- [ ] 根据来源任务成功步骤和组件状态生成组件清理计划。
- [ ] 未成功安装 Helm 时不创建 Helm 清理任务。
- [ ] 无受管 release 证据且 Helm 缺失时安全跳过组件清理。
- [ ] 有受管 release 证据但 Helm 缺失时明确失败，不伪报清理成功。
- [ ] 删除受管 drop-in、标记块、Repo、Registry 配置、etcd unit 和 NFS 配置。
- [ ] 基线文件被用户修改时停止对应恢复并报告冲突。
- [ ] 重置后验证所有受管参数无残留，且用户未受管内容仍存在。
- [ ] 前端说明实际清理范围和可能的配置冲突。

### 验收

- 第二阶段失败且从未安装 Helm 的集群可以完成重置。
- 已安装受管 Helm release 的集群仍按所有权安全清理。
- KubeFoundry 受管参数配置无残留，用户配置不被误删。
- 重复重置保持幂等。

### 建议提交

```text
重置：支持失败安装并清理受管配置
```

## 19. 任务 13：Redis Sentinel 离线部署

### 目标

使用冻结的 Bitnami Redis Chart、私有仓库镜像和受管 Secret，在断网环境完成 Redis Sentinel 部署与验证。

### 主要文件

- 修改：`cluster/KubemateComponentCatalog.java`
- 修改：`cluster/ClusterComponentService.java`
- 修改：`installer/ComponentPlanFactory.java`
- 修改：`installer/ComponentMediaService.java`
- 重写：`scripts/steps/phase3_ecosystem/43-install-redis-sentinel.sh`
- 重写：`scripts/verify/phase3_ecosystem/verify-43-install-redis-sentinel.sh`
- 新增/整理：`kube-media/03.setup_file/v1.30.14/helmapp/redis/`
- 修改：组件计划、介质、脚本、前端和发布包测试。

### 实施步骤

- [ ] 完成门禁 C 并记录 Chart、镜像和文件 SHA-256。
- [ ] 清理目录结构，确保运行时只选择 Bitnami Redis Chart。
- [ ] 编写离线 `values-sentinel.yaml`，启用 replication 和 Sentinel。
- [ ] 所有镜像改写为私有 Registry 地址并在安装前检查存在。
- [ ] 将 Redis 组件组标记为可用并加入固定安装计划。
- [ ] 使用 `helm upgrade --install --atomic --wait --timeout`。
- [ ] 创建或复用 KubeFoundry 受管 Secret，密码不进入日志或命令证据。
- [ ] 验证 release、Pod Ready、Sentinel quorum/master、复制链路和 PVC Bound。
- [ ] 完成最小读写和受控故障切换验收。
- [ ] 将 Redis release 加入重置所有权清理清单。

### 验收

- 目标节点完全断网时可从离线介质完成安装。
- Sentinel 可识别 master，并在受控故障下完成切换。
- 所有 PVC Bound，所有期望 Pod Ready。
- 日志、API、任务快照摘要和测试输出不泄露 Redis 密码。

### 建议提交

```text
组件：支持离线部署Redis哨兵模式
```

## 20. 任务 14：etcd 备份最终单元

### 目标

在完整安装计划最后配置非交互 etcd 备份、立即生成并验证一次快照，同时支持定时执行和重置清理。

### 主要文件

- 重写：`scripts/steps/phase3_ecosystem/44-setup-etcd-backup.sh`
- 重写：`scripts/verify/phase3_ecosystem/verify-44-setup-etcd-backup.sh`
- 修改：`InstallPlanAssembler.java` 或最终计划装配服务。
- 修改：`ComponentMediaService.java` 或基础资源映射。
- 修改：`ResetPlanFactory.java` 和重置脚本。
- 新增：systemd service/timer 模板和备份执行脚本。
- 新增：etcd 备份 Bash、计划顺序和发布包测试。

### 实施步骤

- [ ] 完成门禁 D，冻结路径、周期、保留数量和工具来源。
- [ ] 移除 `crontab -e` 和固定人工操作。
- [ ] 安装带 KubeFoundry 标记的备份脚本、service 和 timer。
- [ ] 使用当前 etcd 证书生成临时快照，验证完整后原子改名。
- [ ] 仅清理符合受管命名和保留策略的旧快照。
- [ ] 安装时立即执行一次并验证新鲜度、大小和快照状态。
- [ ] 把该步骤以 `MAINTENANCE` 类型放在全部启用组件之后。
- [ ] 续跑到达最后单元时再次执行，不因旧快照存在永久跳过。
- [ ] 重置时停止、禁用并删除受管 service/timer/脚本，不误删快照，除非门禁明确要求。

### 验收

- 计划顺序测试确认 etcd 备份始终为最后一个单元。
- 安装完成时至少存在一个通过完整性检查的快照。
- timer 已启用且 service 最近一次执行成功。
- 重置后受管 unit 和脚本无残留。

### 建议提交

```text
备份：增加安装末尾etcd备份单元
```

## 21. 任务 15：联合回归、文档与发布验收

### 目标

完成跨模块回归、真实环境验收、接口和运维文档同步，并产出可验证的 v0.3.2 离线发布包。

### 主要文件

- 新增：`doc/v0.3.2/接口说明.md`
- 更新：`doc/v0.3.2/验收计划.md`
- 新增：`doc/v0.3.2/最终验收清单.md`
- 更新：`doc/v0.3.2/KubeFoundry-v0.3.2-优化设计.md`
- 更新：部署手册、使用手册、README、package/deploy 脚本。
- 更新：Java、Vue、Bash、CI、烟雾和发布包测试。

### 实施步骤

- [ ] 更新公共接口、状态、错误码、配置字段和兼容策略。
- [ ] 执行 Maven 全量测试和数据库迁移测试。
- [ ] 执行 Vitest、前端构建和生产包隔离测试。
- [ ] 执行全部 Bash 单元/静态测试、LF 和敏感信息检查。
- [ ] 在隔离真实集群执行正常安装、阶段失败、续跑、重置和再次安装。
- [ ] 在 SELinux Enforcing 环境验收 YUM 仓库。
- [ ] 验收 MinIO 参数、Redis Sentinel 故障切换和 etcd 快照完整性。
- [ ] 检查任务日志、事件、快照和发布包不存在凭据。
- [ ] 构建 x86_64 发布包；ARM64 无真实环境时明确保留未验收项。
- [ ] 完成最终验收清单，关闭或记录所有遗留风险。

### 验收命令

```bash
mvn -f web/backend-java/pom.xml test
npm --prefix web/frontend test
npm --prefix web/frontend run build
bash scripts/ci/check-lf.sh
bash scripts/ci/check-secrets.sh
bash scripts/tests/test_phase2_coredns_affinity.sh
bash scripts/tests/test_phase3_common.sh
bash scripts/tests/test_phase3_nfs.sh
bash scripts/tests/test_phase3_storage_observability.sh
bash scripts/tests/test_phase3_prometheus.sh
bash scripts/tests/test_phase3_traefik.sh
bash scripts/tests/test_reset_component_cleanup.sh
bash scripts/tests/test_java_web_smoke.sh
bash scripts/tests/test_web_package_deploy.sh
```

新增的验证契约、续跑、YUM、Redis 和 etcd 测试必须加入统一测试入口，不能只依赖人工执行。

### 建议提交

```text
发布：完成v0.3.2联合回归与验收文档
```

## 22. 分阶段验收门禁

### M1 门禁：失败续跑

- [ ] 数据库迁移和历史兼容测试通过。
- [ ] 每个安装步骤有符合契约的验证脚本。
- [ ] 镜像仓库已存在时确认不上传或执行安装资源。
- [ ] Kubernetes API 不可达时确认不会重复初始化。
- [ ] Join 产物恢复不泄露 Token。
- [ ] 新旧任务状态、日志和事件完全隔离。

### M2 门禁：YUM

- [ ] SELinux Enforcing。
- [ ] 仓库节点本机 HTTP 200。
- [ ] 至少一个远程节点 HTTP 200 和 `yum makecache` 成功。
- [ ] 未使用 `777`、关闭 SELinux 或扩大非仓库内容访问。

### M3 门禁：展示与配置

- [ ] 部署单元与所有叶子步骤映射完整。
- [ ] NFS 相关步骤归入同一部署单元。
- [ ] 安装确认页所有节点显示 IP。
- [ ] MinIO 实际资源与配置一致。
- [ ] MinIO 在 0～3 个正式 Worker 时无法开始安装，4 个及以上时可以进入安装。
- [ ] MinIO 启用后 Worker 数量降低时，下次安装或组件补装准入拒绝继续。

### M4 门禁：重置

- [ ] 第二阶段失败、无 Helm 场景重置成功。
- [ ] 有受管 Helm release 场景按所有权清理。
- [ ] 用户修改冲突不会被覆盖。
- [ ] 受管参数无残留，重复重置幂等。

### M5 门禁：新增单元

- [ ] Redis 完全离线安装、quorum 和故障切换通过。
- [ ] Redis 密码无泄露。
- [ ] etcd 备份为计划最后一步。
- [ ] etcd 快照完整性和 timer 通过。

### M6 门禁：发布

- [ ] Java、Vue、Bash、LF、敏感信息和打包测试全部通过。
- [ ] 中文接口、部署、使用和验收文档同步。
- [ ] 发布包从空白环境完成安装、失败续跑、重置和再次安装。

## 23. 协作与复核安排

- 主模型负责需求边界、设计整合、公共接口、统一验收和最终提交范围。
- Terra 适合承担常规 Java/Vue 实现、测试、联调和发布包验证。
- Luna 仅承担文件清单、机械性验证脚本迁移、测试执行、静态检查、文档初稿和 Git 范围核对，不单独决定状态机、安全或重置方案。
- Sol 应专项复核门禁 A、数据库迁移、SSH 验证执行、Join 产物、Secret、配置所有权、破坏性重置、Redis 凭据和 etcd 备份。
- 不同执行者不得同时修改 `InstallStep`、`RemoteStepRunner`、`JobService`、`ClusterComponentService`、`ComponentPlanFactory` 或同一个 Bash 文件。
- 每个里程碑由主模型复核实现、运行统一测试并确认文档同步后，才能进入下一里程碑。

## 24. 提交策略

建议按任务提交，不把全部 v0.3.2 合并成单个大提交。推荐提交序列：

```text
文档：冻结v0.3.2开发契约与风险门禁
任务：持久化续跑血缘与安装单元元数据
安装：增加步骤执行前后双重验证
验证：统一安装步骤验证脚本契约
任务：支持失败安装创建续跑任务
前端：增加安装任务续跑入口
安装：修复YUM仓库HTTP访问权限
前端：按部署单元展示安装进度
前端：在安装确认页展示节点IP
组件：支持配置MinIO存储与资源参数
安装：标记并记录KubeFoundry受管配置
重置：支持失败安装并清理受管配置
组件：支持离线部署Redis哨兵模式
备份：增加安装末尾etcd备份单元
发布：完成v0.3.2联合回归与验收文档
```

提交前必须使用 `git diff --cached` 核对范围；数据库迁移、SSH、重置、Redis、MinIO、etcd 和用户已有改动由主模型复核后才能提交。

## 25. 完成定义

- 任务 1 至任务 15 全部完成并通过对应里程碑门禁。
- 九项需求均有代码、自动化测试、中文接口说明和验收记录。
- 续跑状态机、数据库迁移、SSH 执行、配置清理、Redis 和 etcd 已完成高风险专项复核。
- 所有安装步骤前后验证覆盖率为 100%，验证异常不会触发安装。
- 本机与远程 YUM 仓库 HTTP 200，且保持 SELinux Enforcing。
- 分组进度、节点 IP 和 MinIO 参数在前端、API、快照和实际集群状态间一致。
- MinIO 安装开始时至少 4 个正式 Worker 的准入规则不可绕过，配置保存不受该数量限制，且不得误加 Ready Worker 数量门禁。
- 无 Helm 的失败安装可重置，KubeFoundry 受管参数无残留，用户配置不被覆盖。
- Redis Sentinel 离线故障切换和 etcd 快照恢复性验证通过。
- 全部新增文本为 LF，无敏感信息泄露，发布包可在干净环境复现完整流程。
