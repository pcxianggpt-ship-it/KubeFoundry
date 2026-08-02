# KubeFoundry v0.3.0 Kubemate 组件安装开发计划

## 1. 文档信息

| 项目 | 内容 |
| --- | --- |
| 版本 | v0.3.0 |
| 状态 | 待实施 |
| 日期 | 2026-08-02 |
| 设计依据 | [Kubemate组件安装设计.md](./Kubemate组件安装设计.md) |
| 验收依据 | [Kubemate组件安装验收计划.md](./Kubemate组件安装验收计划.md) |

## 2. 开发目标

本计划把 v0.3.0 设计拆成可独立实现、测试和提交的开发任务。最终交付应同时支持：

1. 新集群完成 Kubernetes 基础与已选 Kubemate 组件的一键安装。
2. v0.2.1 已安装集群不重置 Kubernetes 即可补装组件。
3. NFS、Kubemate、Traefik、存储与日志套件、Prometheus 五个组件组可独立选择和安装。
4. OpenEBS、MinIO、Loki、Alloy 作为一个不可拆分的原子组执行。
5. 主控制节点按架构离线部署 Helm，组件安装过程只在主控制节点执行 Helm/kubectl 操作。
6. Redis 哨兵组可见但不可启用，待后续脚本完善。
7. 组件配置、安装快照、执行计划、任务状态和重置结果保持一致。

## 3. 实施约束

- 所有新增文本文件使用 LF。
- 不修改 Flyway V1 至 V8，只新增 V9 及后续迁移。
- Git 提交说明使用中文，每个提交只覆盖一个清晰职责。
- 后端是组件配置、依赖和安装计划的权威来源。
- phase3 脚本不得在内部再次 SSH、遍历节点或修改发布介质原文件。
- 组件脚本必须非交互、幂等、可验证，并正确传播失败退出码。
- 不在日志、事件、快照和 API 中输出密码、Token、私钥或 Secret 内容。
- 远程重置及 NFS 系统文件清理属于高风险操作，合并前必须进行专项安全复核。
- 开发期间不得使用生产集群验证破坏性操作。

## 4. 任务依赖

```text
任务 1 数据迁移与领域模型
  ├── 任务 2 组件配置服务与 API
  │     └── 任务 3 组件配置前端
  └── 任务 4 组件状态、快照与任务类型
        └── 任务 5 安装计划拆分与服务端组装
              └── 任务 6 Helm 与 phase3 资源分发
                    └── 任务 7 phase3 脚本公共规范与测试框架
                          ├── 任务 8 NFS 组
                          ├── 任务 9 Kubemate 组
                          ├── 任务 10 Traefik 组
                          ├── 任务 11 存储与日志套件
                          └── 任务 12 Prometheus 组

任务 3 + 任务 4 + 任务 5 + 任务 8 至任务 12
  └── 任务 13 新集群与存量集群安装闭环
        └── 任务 14 组件重置清理与安全复核
              └── 任务 15 版本、打包、文档与发布验收
```

任务 8 至任务 12 可以在任务 7 完成后按不同文件边界推进，但每组完成后必须先通过独立组测试，不能等到全量联调时才验证。

## 5. 任务 1：数据迁移与领域模型

### 目标

建立组件总开关、组件组配置和独立安装状态，并从 v0.2.1 的 `nfs/loki/traefik` 配置安全迁移。

### 主要文件

- 新增：`web/backend-java/src/main/resources/db/migration/V9__kubemate_component_installation.sql`
- 修改：`web/backend-java/src/main/java/io/kubefoundry/cluster/Cluster.java`
- 修改：`web/backend-java/src/main/java/io/kubefoundry/cluster/ClusterComponent.java`
- 新增：`ClusterComponentState.java` 及 Repository。
- 修改：`web/backend-java/src/test/java/io/kubefoundry/persistence/SchemaMigrationTest.java`
- 新增或修改：组件领域模型单元测试。

### 实施步骤

- [ ] 先增加 V8 到 V9 增量迁移测试和 V1 到 V9 全量迁移测试。
- [ ] 为集群增加 `kubemate_enabled`，默认 false。
- [ ] 为 `cluster_components` 增加受控配置存储字段。
- [ ] 新增 `cluster_component_states`，状态值限制为 `not_installed/installing/installed/failed`。
- [ ] 将旧 `nfs`、`traefik` 原样迁移为组件组。
- [ ] 将旧 `loki=true` 映射为 `storage_observability=true`。
- [ ] 新增 `kubemate`、`prometheus`、`redis_sentinel` 默认关闭记录。
- [ ] 任一旧组启用时回填总开关为 true。
- [ ] 所有实际状态初始化为 `not_installed`，不伪造安装成功记录。
- [ ] 为状态与最后任务建立必要索引和唯一约束。
- [ ] 验证删除集群时组件配置、状态和任务关联行为符合现有生命周期。

### 验收

- V1 和 V8 数据库均能迁移并启动。
- 旧配置选择不丢失，旧 Loki 选择转换为完整原子组。
- 配置和实际状态存储相互独立。
- 数据库没有新增明文凭据字段。

### 建议提交

```text
存储：增加Kubemate组件组与安装状态模型
```

## 6. 任务 2：组件配置服务与 API

### 目标

将现有三项数组 API 升级为六个组件组的强类型聚合配置，并实现锁定、状态和可用性规则。

### 主要文件

- 修改：`ClusterComponentService.java`
- 修改：`ClusterComponentController.java`
- 修改：`ClusterComponentRepository.java`
- 新增：组件组目录、DTO、NFS 配置校验器和稳定异常类型。
- 修改：`ClusterComponentApiTest.java`
- 修改：`ApiContractTest.java`

### 实施步骤

- [ ] 建立固定组目录，集中定义键、中文名称、包含组件、顺序和可用性。
- [ ] 实现总开关和 `groups` 聚合响应。
- [ ] 实现 `nfs`、`kubemate`、`traefik`、`storage_observability`、`prometheus`、`redis_sentinel` 六组。
- [ ] Redis 哨兵标记为 unavailable，前后端绕过均不能启用。
- [ ] 使用强类型 DTO 解析 NFS 配置，拒绝未知和非法字段。
- [ ] 校验 NFS 地址、绝对路径、StorageClass 名称和管理模式。
- [ ] 组件配置变化时递增配置版本并使组件预检查失效。
- [ ] 活动任务期间拒绝组件配置写入。
- [ ] 基础集群未安装时允许编辑所有未运行组。
- [ ] 基础集群已安装时仅允许调整未安装或失败组；已安装和安装中组只读。
- [ ] 返回稳定错误码，不向前端暴露数据库异常。

### 验收

- API 始终返回固定六组及准确状态。
- 未知组、重复组、Redis 启用和非法 NFS 配置均被后端拒绝。
- 已安装组不能通过直接调用 API 关闭或覆盖。
- 修改配置后旧组件预检查不能继续用于安装。

### 建议提交

```text
接口：实现Kubemate组件组配置与校验
```

## 7. 任务 3：组件配置前端

### 目标

重构“03 / Kubemate 组件”，完整呈现总开关、六个组件组、NFS 参数和实际状态。

### 主要文件

- 修改：`web/frontend/src/views/KubemateComponentsView.vue`
- 修改：`web/frontend/src/api/client.js`
- 修改：`web/frontend/src/api/client.contract.test.js`
- 新增：`web/frontend/src/views/KubemateComponentsView.test.js`
- 按需修改：共享状态标签、表单校验和样式文件。

### 实施步骤

- [ ] 用中文名称和组件清单替换英文键展示。
- [ ] 增加“启用 Kubemate 组件安装”总开关。
- [ ] 根据 `not_installed/installing/installed/failed` 展示明确状态。
- [ ] 启用 NFS 后展示服务器、目录、StorageClass 和管理模式字段。
- [ ] Redis 哨兵组禁用并显示“脚本待完善”。
- [ ] 已安装组保持只读，关闭总开关时不能显示为已卸载。
- [ ] 保存失败不进入下一阶段，后端字段错误定位到对应组。
- [ ] 保持锁定集群中可查看组件事实状态。
- [ ] 增加键盘操作、表单标签、错误提示和焦点可访问性测试。

### 验收

- 页面刷新后配置和状态恢复一致。
- 总开关只控制有效启用状态，不覆盖已保存子组值。
- 所有页面文案为中文且不再出现“v0.3.0 才安装”的旧提示。
- 前端测试覆盖总开关、NFS、Redis、已安装和失败状态。

### 建议提交

```text
前端：重构Kubemate组件组配置页面
```

## 8. 任务 4：组件状态、快照与任务类型

### 目标

扩展安装快照和任务状态机，使组件计划可恢复、可审计且不读取运行中的实时配置。

### 主要文件

- 修改：`InstallationSnapshotPayload.java`
- 修改：`InstallationSnapshotService.java`
- 修改：安装快照实体及 Repository。
- 修改：`JobService.java`、任务完成回调和中断恢复逻辑。
- 修改：`InstallerAdmission.java`
- 新增：组件状态服务。
- 修改：`InstallationSnapshotPayloadTest.java`
- 修改：`InstallerAdmissionIntegrationTest.java`
- 修改：`JobSubmissionTransactionTest.java`

### 实施步骤

- [ ] 快照增加总开关、组件组、规范化配置、计划版本和介质校验和。
- [ ] 验证快照 JSON 不包含凭据、Token 和 Secret 内容。
- [ ] 新增 `job_type=component_install`。
- [ ] 将组件补装纳入集群级活动任务互斥。
- [ ] 在事务锁内完成配置版本检查、快照创建、状态更新和任务提交。
- [ ] 任务接受时把计划内组设为 `installing`。
- [ ] 每组成功后立即设为 `installed`，不等待后续组完成。
- [ ] 当前组失败或应用中断时设为 `failed`，未开始组恢复 `not_installed`。
- [ ] 保证重复回调不会让状态倒退或关联错误任务。
- [ ] 组件任务不改变 Kubernetes 基础安装锁。

### 验收

- 配置变化和任务提交不存在竞态窗口。
- 多组部分成功时每组状态准确。
- 后端重启后不会继续使用实时配置或错误标记全部成功。
- 组件状态只允许由受控状态机变更。

### 建议提交

```text
任务：增加组件安装快照与状态机
```

## 9. 任务 5：安装计划拆分与服务端组装

### 目标

拆分基础与组件计划，建立服务端依赖图和新集群/存量集群共用的组件计划。

### 主要文件

- 重构：`InstallPlanFactory.java`
- 新增：`BaseInstallPlanFactory.java`
- 新增：`ComponentPlanFactory.java`
- 新增：`InstallPlanAssembler.java`
- 修改：`InstallPlan.java`、`InstallStep.java`
- 修改：`InstallService.java`
- 修改：`InstallerController.java`
- 新增：`ComponentInstallService.java`
- 拆分或新增对应计划和服务测试。

### 实施步骤

- [ ] 先将现有 14 个 phase2 步骤无行为变化迁入基础计划工厂。
- [ ] 建立固定组件组顺序和组内依赖定义。
- [ ] 仅根据快照的有效启用组生成组件步骤。
- [ ] 总开关关闭时组件计划为空，不分发 phase3 资源。
- [ ] `storage_observability` 始终生成 OpenEBS、MinIO、Loki、Alloy 全部步骤。
- [ ] 删除或禁用安装 API 的任意 `steps` 选择能力。
- [ ] 将全局 `GET /api/install-plan` 调整为集群级权威计划预览。
- [ ] 新集群安装拼接基础计划和组件计划。
- [ ] 存量集群补装只生成未安装或失败组的组件计划。
- [ ] 缺少目标节点、资源或前置条件时在任务创建前失败。

### 验收

- phase2 步骤顺序和目标解析无回归。
- 任意可用组件组单独启用时计划只包含公共步骤和该组。
- 客户端无法拆分原子组或安装已关闭组。
- 计划预览与任务实际步骤完全一致。

### 建议提交

```text
安装：拆分基础计划并组装组件依赖
```

## 10. 任务 6：Helm 与 phase3 资源分发

### 目标

通过 Java 远程步骤向主控制节点部署正确架构的 Helm，并按已选组分发最小组件资源集；其他控制节点无需安装 Helm。

### 主要文件

- 新增：`scripts/steps/phase3_ecosystem/29-install-helm.sh`
- 修改：`InstallStep.java` 的资源描述能力。
- 修改：`RemoteStepRunner.java`
- 修改：`RuntimeEnvRenderer.java`
- 修改：`ClusterSettingsService.java` 或介质解析服务。
- 修改：`RemoteStepRunnerTest.java`
- 修改：`RuntimeEnvRendererTest.java`
- 新增：Helm 资源选择和校验测试。

### 实施步骤

- [ ] 统一 `tools/helm-amd` 与 `tools/helm-arm` 的架构映射。
- [ ] 为 Helm 二进制建立 SHA-256 校验。
- [ ] 根据主控制节点架构选择唯一资源。
- [ ] 安装到 `/usr/local/bin/helm` 并记录 KubeFoundry 受管标记。
- [ ] 发现不兼容且非受管 Helm 时预检查失败，不静默覆盖。
- [ ] 验证主控制节点的 `helm version` 和 `helm list -A`。
- [ ] 组件资源分发到 `/tmp/kubefoundry/jobs/{jobId}/resources/{groupKey}`。
- [ ] 只分发实际启用组资源，禁止依赖远端同路径的 `kube-media`。
- [ ] 运行时统一设置 `KUBECONFIG=/etc/kubernetes/admin.conf`。
- [ ] 清理任务临时资源时继续保留任务日志和校验和证据。

### 验收

- amd64 和 arm64 选择不会交叉。
- 主控制节点能离线使用 Helm 访问集群，其他控制节点不被要求安装 Helm。
- 未启用组件的 Chart 和 YAML 不会被发送到远端。
- 资源分发失败能定位本地路径、目标节点和安全错误原因。

### 建议提交

```text
安装：离线部署Helm并分发phase3资源
```

## 11. 任务 7：phase3 脚本公共规范与测试框架

### 目标

建立所有组件脚本共用的非交互、幂等、等待、渲染和测试约束。

### 主要文件

- 新增或修改：`scripts/lib/` 下 phase3 公共函数。
- 新增：`scripts/tests/test_phase3_common.sh`
- 新增：伪造 `kubectl`、`helm` 命令和临时资源夹具。
- 修改：纳入计划的 phase3 脚本头和公共加载逻辑。

### 实施步骤

- [ ] 统一严格模式、日志、失败返回和清理 trap。
- [ ] 提供 `helm upgrade --install` 封装和统一 timeout。
- [ ] 提供 namespace、ConfigMap 和 Kubernetes rollout 幂等函数。
- [ ] 提供任务资源目录和安全模板渲染函数。
- [ ] 禁止对发布介质执行原地修改。
- [ ] 提供 Secret 值脱敏和禁止输出检查。
- [ ] 用伪命令记录参数顺序，验证脚本不执行二次 SSH。
- [ ] 为脚本连续执行两次建立通用幂等测试约定。
- [ ] 将现有 verify 能力接入 Java 步骤或转换为稳定非交互命令。

### 验收

- 每个组件组可以复用同一测试夹具。
- 公共测试能捕获交互命令、固定节点名、错误 Helm 用法和敏感输出。
- 子脚本失败时 Java 能收到非零退出码。

### 建议提交

```text
脚本：建立phase3幂等执行与测试基础
```

## 12. 任务 8：NFS 组件组

### 目标

实现 managed/external 两种 NFS 模式，完成 exports、Provisioner 和 Worker 挂载的 Java 编排。

### 主要文件

- 修改：`32-configure-nfs-exports.sh`
- 修改：`32-install-nfs.sh`
- 修改：`32-mount-nfs-workers.sh`
- 修改：`verify-32-install-nfs.sh`
- 新增：`scripts/tests/test_phase3_nfs.sh`
- 修改：`ComponentPlanFactoryTest.java`
- 修改：组件预检查测试。

### 实施步骤

- [ ] Java 根据 NFS 地址解析 managed 目标节点。
- [ ] 删除配置和挂载脚本内部 SSH 与节点循环。
- [ ] managed 模式使用受管注释维护 `/etc/exports`。
- [ ] external 模式只验证端口和共享可挂载，不修改外部服务。
- [ ] Worker 挂载使用受管注释维护 `/etc/fstab`。
- [ ] Provisioner 使用固定 release 名称、namespace 和 `helm upgrade --install`。
- [ ] 校验共享路径和挂载目录安全边界。
- [ ] 验证 StorageClass、Provisioner Pod、PVC 创建和绑定。
- [ ] 增加重复执行、已存在配置、部分 Worker 失败和重试测试。

### 验收

- managed 和 external 两种模式均有自动化测试。
- Java 日志中每个节点只有自身操作，不出现脚本二次 SSH。
- 重复安装不增加重复 exports 或 fstab 行。
- 动态 PVC 能完成 Bound 和读写验证。

### 建议提交

```text
组件：实现NFS存储组安装
```

## 13. 任务 9：Kubemate 组件组

### 目标

将 Kubemate UI 改为主控制节点远程、幂等且不修改介质的安装步骤。

### 主要文件

- 修改：`31-install-kubemate-ui.sh`
- 修改：`verify-31-install-kubemate-ui.sh`
- 新增：`scripts/tests/test_phase3_kubemate.sh`
- 修改：`ComponentPlanFactoryTest.java`

### 实施步骤

- [ ] 将 Kubemate YAML 作为步骤资源分发到任务目录。
- [ ] 从 `/etc/kubernetes/admin.conf` 创建或更新所需 ConfigMap。
- [ ] 在任务副本中渲染主控制节点地址，不修改管理端介质。
- [ ] 用声明式 apply 和 readiness timeout 替换固定 sleep 与重复 apply。
- [ ] 检查 NodePort 冲突。
- [ ] 验证 Deployment/Pod Ready、Service 和访问端口。
- [ ] 增加重复执行和 API 暂时不可用的失败测试。

### 验收

- 管理端无需本地 kubectl 即可完成安装。
- 原始介质在安装前后校验和不变。
- Kubemate 工作负载和访问 Service 验证通过。

### 建议提交

```text
组件：接入Kubemate管理组件安装
```

## 14. 任务 10：Traefik 组件组

### 目标

将 Traefik 作为一个可独立安装组；Traefik Mesh 和 CoreDNS 不纳入 v0.3.0。

### 主要文件

- 修改：`36-install-traefik.sh`
- 修改：`verify-36-install-traefik.sh`
- 新增：`scripts/tests/test_phase3_traefik.sh`
- 修改：计划和预检查测试。

### 实施步骤

- [ ] 显式声明并分发 Traefik 清单。
- [ ] 删除重复 apply 和固定目录切换。
- [ ] 预检查 Service 端口和集群资源冲突。
- [ ] 等待 Traefik rollout 完成。
- [ ] 验证 Ingress/Service 通过 Traefik 访问。
- [ ] 明确不接入 `45-setup-traefik-cleanup.sh`。

### 验收

- Traefik 组可在未选择其他组件时独立安装。
- 安装过程无交互命令。
- Traefik 工作负载、Service 和路由可追踪、可验证。

### 建议提交

```text
组件：实现Traefik网关组安装
```

## 15. 任务 11：存储与日志原子组

### 目标

按严格顺序接入 OpenEBS、MinIO、Loki、Alloy，并实现组内就绪门禁、失败停止和安全重试。

### 主要文件

- 修改：`47-install-openebs.sh`
- 修改：`49-install-minio.sh`
- 修改：`35-install-loki.sh`
- 修改：`48-install-alloy.sh`
- 修改：对应 verify 脚本。
- 新增：Worker 数据目录准备脚本。
- 新增：`scripts/tests/test_phase3_storage_observability.sh`
- 修改：计划、状态机和预检查测试。

### 实施步骤

- [ ] 独立步骤在目标 Worker 创建规范化数据目录。
- [ ] OpenEBS 使用 `helm upgrade --install` 并等待 StorageClass 和控制面就绪。
- [ ] MinIO 安装过程完全非交互，明确 Operator 和实际工作负载验收范围。
- [ ] Secret 由安全路径创建，任何日志都不打印 Token 或 Secret 值。
- [ ] Loki 仅在 OpenEBS、MinIO 验证成功后执行。
- [ ] Alloy 仅在 Loki 健康后执行并验证采集链路。
- [ ] 所有 values 中的镜像、路径、StorageClass 和地址由受控渲染产生。
- [ ] 任一步骤失败立即停止该组及后续组。
- [ ] 重试完整组时已成功步骤幂等通过。
- [ ] 验证原子组不能由 API 或前端拆分。

### 验收

- 实际计划顺序严格为 OpenEBS、MinIO、Loki、Alloy。
- 中间任意故障都会产生准确组状态和错误步骤。
- 修复后重试不会重复创建冲突资源。
- 能验证 Loki 写入/查询和 Alloy 上报的最小数据链路。

### 建议提交

```text
组件：实现存储与日志原子套件
```

## 16. 任务 12：Prometheus 组件组

### 目标

接入 Prometheus 套件与 Metrics Server，移除固定节点名称并按实际集群拓扑准备存储和标签。

### 主要文件

- 修改：`38-install-prometheus.sh`
- 修改：`40-install-metrics-server.sh`
- 修改：对应 verify 脚本。
- 新增：Worker 准备脚本。
- 新增：`scripts/tests/test_phase3_prometheus.sh`
- 修改：计划和预检查测试。

### 实施步骤

- [ ] Java 将 Worker 准备步骤定向到实际 Worker 节点。
- [ ] 删除固定 `k8sw1/k8sw2` 和错误的远端 kubectl 调用。
- [ ] 按规范化组件数据目录创建存储路径。
- [ ] 声明式创建 CRD、Operator、Prometheus、Exporter 和 Alertmanager。
- [ ] 将 Metrics Server 纳入同组并避免重复安装资源。
- [ ] 等待 CRD Established、Deployment/StatefulSet Ready。
- [ ] 验证 Prometheus targets、Node Exporter、kube-state-metrics 和 `kubectl top nodes`。
- [ ] 增加单 Worker、多 Worker、重复安装和就绪超时测试。

### 验收

- 任意合法 Worker 主机名均能安装，不依赖固定命名。
- Prometheus 和 Metrics Server 可独立于其他组件组运行。
- 监控目标和节点指标均可查询。

### 建议提交

```text
组件：实现Prometheus监控组安装
```

## 17. 任务 13：新集群与存量集群安装闭环

### 目标

在前后端形成全量安装、组件补装、计划确认、任务执行、失败重试的完整工作流。

### 主要文件

- 修改：`InstallConfirmView.vue`
- 修改：`InstallOverviewView.vue` 或对应安装概览页面。
- 修改：`JobExecutionView.vue`
- 修改：`JobStageList.vue`
- 修改：前端路由和 API 客户端。
- 修改：`InstallFlow.test.js`
- 新增：组件补装流程测试。
- 修改：Java API 契约和集成测试。

### 实施步骤

- [ ] 安装概览区分 Kubernetes 基础状态和各组件组状态。
- [ ] 新集群安装确认展示基础步骤与已选组件组。
- [ ] 存量集群提供组件预检查与“安装待安装组件”入口。
- [ ] 安装确认展示 Helm 目标节点、版本和非敏感组配置。
- [ ] 任务执行页按基础、公共前置和组件组分段。
- [ ] 正确显示已成功组、失败组和未执行组。
- [ ] 失败后引导用户修正配置、重新预检查和重试。
- [ ] 页面刷新和服务重启后恢复相同任务状态。
- [ ] 活动任务期间所有冲突按钮和后端接口均拒绝重复提交。

### 验收

- 新集群和 v0.2.1 存量集群均有完整可恢复流程。
- 页面显示计划与任务实际步骤一致。
- 部分成功不会在页面上误报整批组件全部失败或全部成功。

### 建议提交

```text
前端：完成组件全量安装与补装闭环
```

## 18. 任务 14：组件重置清理与安全复核

### 目标

在 Kubernetes 重置前逆序清理受管组件、NFS 系统配置和 KubeFoundry 安装的 Helm，并保护用户资源。

### 主要文件

- 修改：`ResetPlanFactory.java`
- 修改：`ClusterResetService.java`
- 新增：`scripts/steps/reset/` 下组件清理脚本。
- 新增或修改：`scripts/verify/reset/` 验证脚本。
- 修改：`ClusterResetServiceTest.java`
- 修改：`ResetPlanFactoryTest.java`
- 新增：组件清理安全测试。

### 实施步骤

- [ ] 从最近安装快照和组件状态生成逆序清理计划。
- [ ] 依赖逆序清理 Alloy、Loki、MinIO、OpenEBS。
- [ ] 清理 Prometheus、Traefik、Kubemate 和 NFS 受管资源。
- [ ] `/etc/fstab`、`/etc/exports` 只删除带受管标记的行。
- [ ] external NFS 模式不触碰外部服务器。
- [ ] 仅删除明确归属于任务快照的目录和 Kubernetes 资源。
- [ ] Helm 只在受管标记和校验和匹配时删除。
- [ ] 任一组件清理失败时保持集群锁，不进入成功解锁状态。
- [ ] 全部重置成功后将组件状态恢复为 `not_installed`。
- [ ] 对空路径、根目录、符号链接、越界和重复执行进行破坏性安全测试。

### 安全评审门禁

- [ ] 专项复核所有远端删除和系统文件编辑。
- [ ] 专项复核组件清理与 kubeadm reset 的顺序。
- [ ] 专项复核任务中断、重复重置和状态回写。
- [ ] 先在临时目录和假 SSH 环境通过测试，再使用专用测试集群。
- [ ] 未完成专项复核不得合并或执行真实重置验收。

### 验收

- 重置后受管组件、挂载和系统配置被清理。
- 用户已有 Helm、非受管 exports/fstab 行和外部 NFS 不受影响。
- 清理失败绝不解锁集群。

### 建议提交

```text
重置：安全清理Kubemate受管组件
```

## 19. 任务 15：版本、打包、文档与发布验收

### 目标

将版本统一升级为 0.3.0，确保发布包包含执行代码和双架构 Helm，完成自动化及真实环境验收。

### 主要文件

- 修改：`web/backend-java/pom.xml`
- 修改：`web/frontend/package.json`、`package-lock.json`
- 修改：`package.sh`、`deploy.sh`
- 修改：`README.md`
- 修改：`scripts/tests/test_java_web_smoke.sh`
- 修改：发布包和运行时相关测试。
- 更新：`doc/v0.3.0/` 中文部署、使用、接口和验收文档。

### 实施步骤

- [ ] 将后端、前端、健康接口、包名和部署文案统一升级为 0.3.0。
- [ ] 发布包包含所有纳入计划的 phase3 脚本和验证脚本。
- [ ] 发布包或部署目录能解析 amd64、arm64 Helm 介质及校验和。
- [ ] 更新包内容、篡改检测、符号链接和缺失资源测试。
- [ ] 扩展 Java Web 冒烟测试覆盖组件 API 与计划预览。
- [ ] 运行 Maven、Vitest、构建、Bash 测试、LF 和敏感信息检查。
- [ ] 按验收计划完成 x86_64 动态验收。
- [ ] ARM64 至少完成 Helm 分发与非破坏性预检查。
- [ ] 更新部署手册、使用手册、API 文档和最终验收清单。
- [ ] 复核 Git 暂存范围、生成物和用户本地配置不进入提交。

### 建议验证命令

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
bash scripts/ci/check-lf.sh
bash scripts/ci/check-secrets.sh
git diff --check
```

### 验收

- 所有版本号、包名、健康接口和文档均为 0.3.0。
- 自动化门禁全部通过。
- 发布包在不联网条件下可完成组件预检查和安装。
- 真实环境结果满足验收计划的发布准入标准。

### 建议提交

```text
发布：完成v0.3.0组件安装验收
```

## 20. 里程碑

| 里程碑 | 包含任务 | 完成标志 |
| --- | --- | --- |
| M1 配置模型 | 任务 1 至任务 3 | 六组配置、迁移和页面可用 |
| M2 编排基础 | 任务 4 至任务 7 | 快照、状态机、计划、Helm 和资源分发可用 |
| M3 组件实现 | 任务 8 至任务 12 | 五个可用组件组分别通过自动化测试 |
| M4 安装闭环 | 任务 13 | 新集群与存量集群流程完整 |
| M5 安全与发布 | 任务 14 至任务 15 | 重置安全复核、双架构与发布验收完成 |

## 21. 完成定义

开发计划只有在以下条件全部满足后才能关闭：

- 任务 1 至任务 15 的代码、测试和文档全部完成。
- 每个组件组具有独立自动化测试和真实环境验收记录。
- 高风险重置和 NFS 系统配置通过专项安全复核。
- 新集群全量安装、v0.2.1 存量补装、失败重试和远程重置闭环通过。
- Redis 哨兵在脚本完成前始终无法被启用。
- 所有文本文件为 LF，Git 不包含构建产物、凭据或用户本地配置。
- 最终验收结果记录在 v0.3.0 中文验收清单中。
