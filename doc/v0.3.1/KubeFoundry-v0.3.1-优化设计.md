# KubeFoundry v0.3.1 优化设计

## 1. 文档信息

| 项目 | 内容 |
| --- | --- |
| 目标版本 | v0.3.1 |
| 状态 | 设计初稿，待评审 |
| 日期 | 2026-08-09 |
| 前置版本 | v0.3.0 |
| 适用范围 | Vue 3 前端、Java 17 后端、H2/Flyway、Bash 安装脚本 |
| 需求来源 | [优化需求记录](./优化需求记录.md) |

## 2. 背景与现状

v0.3.0 已建立 Kubemate 组件目录、组件配置与实际状态分离、组件安装快照、`ComponentPlanFactory`、`component_install` 任务以及 phase3 离线资源分发。v0.3.1 在该基础上处理可靠性、易用性和历史任务可追踪性问题，不重新设计 Kubernetes 基础安装主流程。

当前代码基线如下：

- `NodeTestService.startClusterTest` 与 `POST /api/clusters/{clusterId}/node-test` 已具备集群级节点测试能力，前端尚需提供明确的“测试全部节点”入口和批量状态展示。
- 节点保存仅校验必填项、IPv4 格式和角色，尚未保证同一集群内主机名、IPv4 唯一。
- Kubemate 组件配置仍包含 `kubemate_enabled` 总开关，`ComponentPlanFactory` 同时判断总开关和组件组选项。
- `JobService` 在任一步骤失败后立即终止整个任务，无法满足组件组之间相互独立的要求。
- NFS Worker 脚本仅通过 `mountpoint` 判断是否挂载，未核对实际挂载源和文件系统类型。
- MinIO 脚本已支持非交互应用 Operator 和可选 Tenant 清单，但 Tenant 资源、凭据生成、存储检查与就绪条件尚未形成完整闭环。
- 任务执行页已经按单个 `jobId` 加载步骤和日志，但集群安装概览缺少任务 ID 列表、任务切换和时间信息。
- 仓库中的 `39-update-coredns.sh` 包含 `kubectl edit`、固定等待和无关的 Traefik Mesh 重启，不符合自动化、幂等和职责单一要求，不能直接纳入新计划。

## 3. 设计目标

1. Kubernetes 基础安装完成后，以软反亲和方式提高 CoreDNS 副本跨节点分布能力。
2. 使用离线清单和 Tenant CR 完成 MinIO 无人值守部署，不再依赖 Console 操作。
3. 提供一键测试全部服务器节点，并保证同一集群内主机名和 IPv4 不重复。
4. 删除 Kubemate 安装总开关，由各组件组选项直接决定期望安装内容。
5. NFS 重复部署时能够识别正确挂载并跳过，识别冲突挂载并安全失败。
6. Kubemate 组件组之间隔离失败，某组失败不影响无依赖的其他组继续安装。
7. 集群安装详情能够列出并切换不同任务 ID，完整恢复各任务自己的步骤、节点状态和日志。

## 4. 非目标

- 不引入组件组并行安装；v0.3.1 仍串行执行组件组，以避免多个 Helm 操作竞争 Kubernetes 资源。
- 不提供 Kubemate 组件卸载、版本升级中心或任意单步骤续跑。
- 不把 CoreDNS 归入 Kubemate 组件组，也不在组件补装任务中重复配置 CoreDNS。
- 不实现 MinIO 跨集群、多租户管理、在线 Chart 下载或 Console 自动化操作。
- 不扩展节点地址到 IPv6 唯一性；本版本仅处理当前必填的 IPv4 字段。
- 不合并、删除或修改历史任务记录。

## 5. 总体架构

```text
集群配置
  ├── 节点保存：规范化 -> 前端预判 -> 后端事务校验 -> 数据库唯一约束
  ├── 节点测试：测试全部节点 -> node_test 任务 -> 逐节点独立结果
  └── 组件配置：各组开关直接形成期望状态

安装编排
  ├── Kubernetes 基础步骤（失败则终止）
  ├── CoreDNS 反亲和步骤（Kubernetes 基础步骤）
  ├── 组件公共前置（失败则终止组件阶段）
  └── 组件组串行调度
        ├── 组内失败：跳过本组剩余步骤
        └── 继续下一无依赖组件组

安装详情
  └── 集群任务列表 -> 选择 jobId -> 独立快照/SSE/日志
```

核心原则：

- 配置决定期望状态，任务和组件状态表记录实际状态。
- 基础安装、组件公共前置与组件组使用不同失败边界。
- 前端校验用于即时反馈，后端和数据库约束负责最终一致性。
- 所有脚本必须非交互、幂等、有超时、可验证，且不得输出敏感信息。
- 历史任务以 `jobId` 为不可变边界，不复用其他任务的步骤、事件或日志。

## 6. CoreDNS 副本反亲和性

### 6.1 计划位置

新增 Kubernetes 基础步骤 `23-configure-coredns-affinity`，由主控制节点执行，放在集群初始化、节点加入和核心组件就绪之后、基础安装最终健康检查之前。

该步骤归属 `BaseInstallPlanFactory`，不进入 `ComponentPlanFactory`。组件补装任务不执行该步骤。

### 6.2 调度策略

使用软反亲和，避免单节点或可调度节点不足时 CoreDNS 永久 Pending：

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: k8s-app
                operator: In
                values:
                  - kube-dns
          topologyKey: kubernetes.io/hostname
```

不得使用 `requiredDuringSchedulingIgnoredDuringExecution`。单节点集群执行同一配置，不需要单独删除或降级规则，因为软策略不会阻止调度。

### 6.3 幂等修改

废弃现有 `39-update-coredns.sh` 的交互式实现，新增职责单一的脚本。脚本按以下顺序执行：

1. 验证 `kube-system/coredns` Deployment 存在。
2. 读取现有 `spec.template.spec.affinity`。
3. 判断是否已存在相同标签选择器和 `kubernetes.io/hostname` 拓扑键的规则。
4. 已存在一条目标规则则保留；存在多条目标规则时按索引倒序删除重复项，不改动其他亲和性规则。
5. 不存在时生成 JSON Patch：缺少父级字段时创建父级，已有规则数组时只追加新规则，不覆盖用户已有亲和性配置。
6. 使用 `kubefoundry.io/coredns-anti-affinity=v2` 标记修复后的规则版本；规则或版本发生变化时触发一次 CoreDNS 滚动重启。
7. 执行 `kubectl rollout status deployment/coredns -n kube-system --timeout=180s`。

脚本不得执行 `kubectl edit`、固定 `sleep` 或重启 Traefik Mesh。

### 6.4 验证

- Deployment 可用副本数等于期望副本数。
- 所有 CoreDNS Pod 为 Ready。
- 多节点且副本数不小于 2 时，记录 Pod 所在节点分布；若受资源、污点或节点数量限制未分散，输出警告但不把软策略本身判为失败。
- 重复执行两次，第二次不得新增重复规则或触发无意义滚动更新。

## 7. MinIO 自动化部署

### 7.1 方案选择

v0.3.1 采用“离线固定版本 Operator 清单 + Tenant CR”方案：

1. 从发布介质应用固定版本的 Operator、CRD 和 RBAC 清单。
2. 等待 Operator Deployment 就绪及 Tenant CRD 可用。
3. 创建或复用 Tenant 凭据 Secret。
4. 渲染并应用固定 API 版本的 Tenant CR。
5. 等待 Tenant 状态、Pod、Service 和 PVC 全部达到预期。

不采用 Console 自动化，也不在目标集群运行需要在线下载的 Kustomize 地址。发布介质必须保存所有清单、镜像引用、版本和 SHA-256。

[MinIO 官方开源 Operator 仓库](https://github.com/minio/operator)已于 2026-03-20 归档，现有发布介质继续使用时必须冻结并记录版本，不得默认跟随未知上游升级。实施前需完成许可证、安全漏洞、目标 Kubernetes 版本与现有 Operator API 的专项评审；评审不通过时，MinIO 自动化从 v0.3.1 发布范围中单独移除，不影响其他优化项实施。

### 7.2 配置模型

`storage_observability` 组增加强类型配置：

| 字段 | 规则 |
| --- | --- |
| `minio_namespace` | 默认 `kubemate-system`，符合 Kubernetes 命名规则 |
| `minio_tenant_name` | 默认 `kubemate-minio`，同一命名空间唯一 |
| `minio_storage_class` | 必填，必须在预检查阶段存在 |
| `minio_servers` | 正整数，满足所选 Operator 版本的最小拓扑要求 |
| `minio_volumes_per_server` | 正整数 |
| `minio_volume_size` | Kubernetes 容量格式，例如 `100Gi` |
| `minio_request_auto_cert` | 默认 `false`；离线内网场景先使用集群内明文服务，TLS 另行评审 |

后端仅接受上述字段，不接受任意 JSON 透传到 Tenant CR。

### 7.3 凭据处理

- MinIO Access Key 和 Secret Key 由管理员写入离线介质 `tenant.env`，文件权限必须为 `0600`，且不得包含 `CHANGE_ME_` 占位符。
- Kustomize 根据 `tenant.env` 创建固定名称的 Kubernetes Secret，重试时继续使用同一配置文件，避免无意轮换凭据。
- 根据运维留痕要求，`tenant.env` 会原文进入控制端和远程任务资源快照；任务事件、页面日志、数据库错误字段和异常摘要仍不得输出凭据值。
- 控制端留痕文件权限为 `0600`、目录为 `0700`；远程任务根目录移除 group/other 的全部权限。
- KubeFoundry 页面不回显 MinIO 管理凭据；如后续需要凭据管理，应作为独立安全需求设计。

### 7.4 就绪门禁

MinIO 步骤成功必须同时满足：

- Operator Deployment rollout 成功。
- Tenant CR 的状态条件为 Ready 或目标 Operator 版本定义的等价成功条件。
- Tenant 工作负载 Pod 全部 Ready。
- 所需 PVC 全部 Bound。
- S3 Service 存在并具有 ClusterIP。
- Loki 使用的 endpoint、bucket Secret 或最小对象存储配置已生成并能被后续步骤引用。

所有等待命令必须有明确超时。任一条件失败时返回非零退出码和脱敏后的资源诊断摘要。

### 7.5 组内顺序

存储与日志组保持严格顺序：

```text
准备 Worker 存储 -> OpenEBS -> MinIO Operator/Tenant -> Loki -> Alloy
```

MinIO 失败只阻塞本组的 Loki 和 Alloy，不阻塞 NFS、Kubemate、Traefik 或 Prometheus 组。

## 8. 服务器节点管理优化

### 8.1 测试全部节点

前端 `NodeConfigView` 增加“测试全部节点”按钮，复用现有接口：

```http
POST /api/clusters/{clusterId}/node-test?failed_only=false
```

交互规则：

- 集群没有节点、存在未完成草稿节点或正在执行节点测试任务时按钮禁用，并显示原因。
- 接口返回 `job_id` 后，页面展示 `NodeTestActivity`，订阅该任务事件并逐节点更新状态。
- 单节点失败不得停止其他节点测试；沿用节点任务 `failFast=false`。
- 测试中禁止再次发起“测试全部节点”或单节点测试，避免同集群重复并发任务。
- 批量结束后展示成功数、失败数和失败节点入口；允许使用现有 `failed_only=true` 重试失败节点。

### 8.2 主机名与 IPv4 规范化

主机名唯一性采用大小写不敏感比较：

```text
trim -> 去除末尾单个点 -> lower-case
```

IPv4 必须为四段十进制格式，各段范围为 0 至 255；保存前转换为无前导零的标准形式，例如 `192.168.001.010` 规范化为 `192.168.1.10`。原始展示字段保存规范化后的值，避免后续 SSH、快照与重复判断使用不同表示。

唯一范围为同一 `cluster_id`。不同集群允许使用相同主机名或 IP。编辑节点时排除当前节点 ID。

### 8.3 三层校验

1. 前端：在当前节点列表中即时检查，分别提示“主机名已被节点 X 使用”或“IP 已被节点 X 使用”。
2. 后端：创建和更新事务中规范化输入，查询同集群冲突记录；返回稳定错误码。
3. 数据库：保存规范化列并建立组合唯一索引，处理并发请求竞态和绕过应用层的写入。

新增字段与约束：

```text
nodes.hostname_normalized  VARCHAR(128) NULL
nodes.ip_normalized        VARCHAR(15)  NULL
UNIQUE(cluster_id, hostname_normalized)
UNIQUE(cluster_id, ip_normalized)
```

草稿复制节点允许暂时保留重复值，其两个规范化列为 `NULL`；草稿完成编辑并转为正式节点前必须通过唯一校验。迁移时只为 `is_draft=false` 的节点回填规范化列。若已有正式节点重复，迁移前置检查必须中止升级并列出冲突集群和节点 ID，禁止自动删除或合并节点。

稳定错误码：

| 错误码 | 含义 |
| --- | --- |
| `NODE_HOSTNAME_DUPLICATE` | 同集群主机名重复 |
| `NODE_IP_DUPLICATE` | 同集群 IPv4 重复 |
| `NODE_IDENTITY_DUPLICATE` | 主机名和 IPv4 同时冲突且冲突对象不同 |

## 9. Kubemate 组件安装开关简化

### 9.1 页面与接口

删除“启用 Kubemate 组件安装”总开关、关闭提示和相关禁用逻辑。组件组卡片中的开关直接表达期望状态。

组件配置请求调整为：

```json
{
  "groups": [
    {
      "key": "nfs",
      "enabled": true,
      "config": {}
    }
  ]
}
```

响应不再返回顶层 `enabled`。当全部可用组件组关闭时，组件计划为空；任一可用组件组开启时，该组直接进入候选计划。

### 9.2 后端兼容策略

- `ComponentPlanFactory.isEnabled` 只读取 `componentGroups[].enabled`，不再判断 `snapshot.kubemateEnabled`。
- 新建安装快照不再写入 `kubemateEnabled`。
- `clusters.kubemate_enabled` 在 v0.3.1 暂作为回滚兼容列保留，但不参与业务判断；保存组件配置时可写入“是否存在任一启用组”的派生值。
- v0.3.1 发布稳定后，在后续破坏性迁移中再删除该列，避免本版本同时承担功能调整和不可逆数据库清理。
- 前后端必须同版本发布。旧客户端提交顶层 `enabled` 时后端忽略该兼容字段但不改变任何组件组选项，并记录一次不含敏感数据的弃用警告。

### 9.3 状态规则

- `not_installed`、`failed`：允许切换开关和编辑配置。
- `installing`、`installed`：保持只读；关闭开关不能被解释为卸载。
- 全部关闭：安装确认页显示“不安装 Kubemate 组件”，不分发 phase3 介质。

## 10. NFS 挂载幂等与防卡死

### 10.1 判断顺序

`32-mount-nfs-workers.sh` 在修改 `/etc/fstab` 和执行 `mount` 前完成精确检查：

```text
expected_source = KF_NFS_SERVER:KF_NFS_SHARE_PATH
target          = KF_NFS_WORKER_MOUNT_PATH

findmnt 精确查询 target
  ├── 未挂载：维护受管 fstab 块 -> 限时 mount -> 再次验证
  ├── source 相同且 fstype 为 nfs/nfs4：维护受管 fstab 块 -> 跳过 mount
  └── source 或 fstype 不同：报错退出，不卸载、不覆盖、不重复 mount
```

必须使用精确挂载点查询，不能把目标目录的父级文件系统误判为目标已经挂载。推荐使用：

```bash
findmnt --noheadings --raw --mountpoint "${target}" --output SOURCE,FSTYPE
```

### 10.2 挂载执行

- `mount` 使用可配置超时，默认 60 秒：`timeout --foreground "${KF_NFS_MOUNT_TIMEOUT:-60}" ...`。
- 超时、非零退出码或挂载后验证失败均返回失败，不进行无限重试。
- `nfs` 与 `nfs4` 均视为 NFS 类型；挂载源必须与期望的 `server:share` 一致。
- 发现冲突挂载时只输出目标、实际源、实际类型和期望源，不自动执行 `umount`。
- 受管 `/etc/fstab` 块按标记原子替换，已有旧参数时更新为当前期望值，不能因标记存在就保留陈旧配置。
- 写入 `/etc/fstab` 后先执行语法与目标唯一性检查，再执行挂载。

### 10.3 测试场景

- 未挂载：成功挂载并写入唯一受管条目。
- 已按预期挂载：不调用 `mount`，脚本成功。
- 已挂载其他 NFS 源：脚本失败，不调用 `mount/umount`。
- 已挂载非 NFS 文件系统：脚本失败，不调用 `mount/umount`。
- `mount` 超时：脚本在限定时间内失败。
- 连续执行两次：第二次不重复挂载、不重复写入 fstab。

## 11. Kubemate 组件组安装隔离

### 11.1 失败域

安装步骤划分为三类失败域：

| 类型 | `component_group_key` | 失败行为 |
| --- | --- | --- |
| Kubernetes 基础步骤 | 空 | 立即终止整个安装任务 |
| 组件公共前置 | 空，`phase=component_common` | 终止组件阶段，所有未开始组件组标记跳过 |
| 组件组步骤 | 具体组键 | 终止本组剩余步骤，继续下一无依赖组 |

该失败域同时用于首次安装 `install` 和组件补装 `component_install`。v0.3.1 的 NFS、Kubemate、Traefik、存储与日志、Prometheus 五组之间没有依赖关系。组内步骤保持严格顺序，组内前一步失败时，后续步骤标记为 `skipped`，原因码为 `COMPONENT_GROUP_PREVIOUS_STEP_FAILED`。

组件组仍按固定顺序串行：

```text
NFS -> Kubemate -> Traefik -> 存储与日志 -> Prometheus
```

该顺序用于保证执行确定性，不代表组间依赖。

### 11.2 执行器调整

`JobService` 不再对所有任务采用统一的“首个失败即退出”。新增服务端生成的步骤失败策略：

```text
ABORT_JOB       # 基础步骤、公共前置
ABORT_GROUP     # 组件组步骤
CONTINUE        # 仅供未来无状态验证步骤使用，v0.3.1 不开放给客户端
```

策略属于权威安装计划，不由前端请求传入。执行算法：

1. 按 `step_order` 串行取步骤。
2. 当前组件组已失败时，将该组后续步骤标记为 `skipped`。
3. 执行步骤；节点级并发行为保持现状。
4. 步骤失败且策略为 `ABORT_GROUP` 时，记录该组失败并继续寻找下一组件组。
5. 策略为 `ABORT_JOB` 时，终止任务并将所有未开始步骤标记为 `skipped`，原因码为 `JOB_ABORTED`，不得保留永久 `pending` 状态。
6. 全部可执行步骤结束后，根据组结果计算任务最终状态。

### 11.3 状态模型

任务新增终态 `partial_success`：

| 条件 | 任务状态 |
| --- | --- |
| 所有执行组成功 | `success` |
| 至少一个组成功，至少一个组失败或因依赖跳过 | `partial_success` |
| 基础步骤或公共前置失败 | `failed` |
| 所有选中组件组均失败 | `failed` |
| 服务重启或任务被中断 | `interrupted` |

组件组状态保持：

- 组内全部步骤成功：`installed`。
- 任一步骤失败：`failed`，记录 `last_job_id` 和错误码。
- 因公共前置失败未开始：恢复为 `not_installed`，任务步骤显示 `skipped`。

### 11.4 组件清单首次应用与重试

- 公共命名空间步骤只使用随任务分发的 `phase3.sh`，不依赖远端仓库中的 `PROJECT_ROOT`，并通过声明式命令重复创建。
- 对包含 CRD 的通用组件文件或目录，先拆分并应用 `CustomResourceDefinition` 文档，逐个等待 `Established`，再应用完整组件清单，避免自定义资源首次安装时抢跑。
- KubeFoundry 管理的通用组件资源使用 `--server-side --field-manager=kubefoundry --force-conflicts` 收敛字段所有权；Kubemate 管理组件不使用该通用应用函数，而是执行专用三步流程。
- Kubemate 管理组件介质按 `kubemate/` 目录分发到任务资源目录：先通过 `/etc/kubernetes/admin.conf` 直接创建 `kubemate-etc` ConfigMap，再将任务副本 `kubemate-resources.yml` 中 `kubemate-appx` Deployment 的 `hostAliases` IP 替换为主控制节点 IP，最后执行 `kubectl apply -f <任务 Kubemate 资源目录>`。不得使用 `--dry-run=client`、服务端应用或字段管理器生成 `kubemate-etc`。
- Kubemate 目录部署必须先单独应用 `kubemate-crds.yml` 并逐个等待 CRD `Established`，然后才能应用 `kubemate-resources.yml`，避免首次安装时 KMUser/KMRole 抢在 API discovery 刷新前创建。
- phase3 组件脚本不使用 `dry-run` 生成资源；命名空间先查询、缺失时直接创建，组件专用 ConfigMap 按对应安装脚本直接创建。
- OpenEBS、Loki、Alloy 使用离线目录内已经打包的 `.tgz` Chart，在主控制节点执行 Helm，不要求介质目录根部存在 `Chart.yaml`；其中 OpenEBS 按 `helm install openebs --namespace kubemate-system <openebs-4.2.0.tgz> -f <openebs-values.yaml>` 安装。NFS 介质本身是已解压 Chart 目录，继续使用目录安装。
- MinIO 安装必须同时部署 Operator 和 `minio-dev.yaml` 对象存储工作负载，将介质中的固定节点名、数据目录和镜像版本渲染为现场 Worker、`/data/minio-root` 和已验收版本，并等待 `kubemate-minio-hl` Service 就绪；不能只凭 Operator Pod 误报 MinIO 安装成功。
- Loki 在调用 Helm 前检查 `kubemate-minio-hl` 及全部私有仓库镜像，缺失时立即列出镜像并失败，不进入十分钟 Helm 等待；read/write/backend 副本数按 Ready Worker 数量收敛到 1～3，并同步调整复制因子和 MinIO endpoint。
- Prometheus 在应用其他资源前先清理 `additional-scrape-configs.Secret.yaml` 中旧集群生成的 `managedFields/resourceVersion/uid/creationTimestamp`，再优先创建该 Secret；部署和验证命名空间统一为 `kubemate-system`。
- 其他组件组失败不改变本组状态。

`job_steps.status` 支持 `pending/running/success/failed/skipped/interrupted`，并增加 `status_reason` 保存稳定原因码。任务执行页将 `partial_success` 显示为“部分成功”，将 `skipped` 显示为“已跳过”，不能显示成成功或失败。

### 11.5 重试

组件补装重试只选择状态为 `not_installed` 或 `failed` 且当前仍启用的组件组。已安装组不重复执行。一次重试仍生成新的任务 ID 和不可变快照，不修改原失败任务。

### 11.6 失败恢复与配置解锁

- 服务启动时将遗留的 `pending/running` 初次安装任务收敛为 `interrupted`，并将集群状态收敛为 `install_failed`，避免旧任务永久阻塞重置准入。
- 初次安装失败后继续保持 `installation_locked=true`，防止用户在远端 Kubernetes 资源尚未清理时修改节点身份；只要不存在活动安装任务，页面即允许进入远程重置。
- 重置成功只恢复草稿状态并解除配置锁定，不主动把未修改节点的最近一次成功测试置为 `stale`；重置后编辑任一节点配置时，仍按节点配置版本机制自动失效节点测试，要求重新测试。
- 重置成功后设置 `status=draft`、`installation_locked=false`，节点测试状态变为 `stale`，基础配置、节点和组件配置恢复可编辑。

## 12. 集群安装详情按任务 ID 展示

### 12.1 页面结构

集群安装概览增加“安装任务记录”区域：

| 字段 | 说明 |
| --- | --- |
| 任务 ID | 主标识，可点击进入详情 |
| 任务类型 | 集群安装或组件补装 |
| 状态 | 等待中、执行中、成功、部分成功、失败、已中断 |
| 创建时间 | 任务入库时间 |
| 开始时间 | 执行器开始处理时间 |
| 结束时间 | 进入终态时间 |
| 操作 | 查看详情 |

默认选择规则：

1. 有 `running/pending` 任务时选择 ID 最大的活动任务。
2. 否则选择最近创建的安装或组件补装任务。
3. 没有任务时展示空状态和发起安装入口。

### 12.2 路由

新增规范路由：

```text
/cluster-install/:clusterId/jobs/:jobId
```

旧路由 `/jobs/:jobId/execution` 保留兼容，加载任务后重定向到包含 `clusterId` 的规范路由。后端 SPA 转发控制器同步覆盖新路由，确保直接访问和 F5 刷新不会返回 Whitelabel 404。

路由中的 `jobId` 是当前选择的唯一来源。切换任务时使用 `router.push` 更新 URL，浏览器前进、后退和刷新均可恢复选择。

### 12.3 API

扩展现有任务接口：

```http
GET /api/jobs?cluster_id={clusterId}&job_type=install,component_install
GET /api/jobs/{jobId}
GET /api/jobs/{jobId}/steps
GET /api/jobs/{jobId}/logs
GET /api/jobs/{jobId}/events
```

任务响应增加：

```json
{
  "id": 123,
  "cluster_id": 8,
  "job_type": "component_install",
  "status": "partial_success",
  "created_at": "2026-08-09T19:00:00",
  "started_at": "2026-08-09T19:00:01",
  "finished_at": "2026-08-09T19:08:32"
}
```

`jobs` 表新增 `started_at`、`finished_at`。任务进入 `running` 时只写一次 `started_at`，首次进入终态时写 `finished_at`；历史数据允许为空。

### 12.4 防止任务数据串流

- 切换任务前关闭旧 `EventSource`，清空当前步骤、日志和筛选状态。
- 每次加载生成请求序号；迟到的旧请求响应与当前 `jobId` 不一致时丢弃。
- SSE 事件只应用于事件连接绑定的 `jobId`，不得仅凭步骤或节点 ID 更新页面。
- 后端加载详情后校验 `job.cluster_id` 与路由 `clusterId` 一致；不一致返回 404，前端提示“任务不属于当前集群”。
- 终态任务只加载快照，不建立 SSE 连接。
- 日志列表继续以 `jobId` 查询；切换任务时不保留其他任务的内存日志。

## 13. 数据库迁移

当前最新迁移为 V12。建议按以下顺序新增：

### V13：节点唯一身份

```text
nodes.hostname_normalized
nodes.ip_normalized
uk_nodes_cluster_hostname_normalized
uk_nodes_cluster_ip_normalized
```

迁移前执行只读重复检查。正式节点存在冲突时必须停止升级并给出处理清单；草稿节点规范化列保持 `NULL`，不参与唯一约束。

### V14：任务执行状态扩展

```text
jobs.started_at
jobs.finished_at
job_steps.status_reason
```

现有任务无需推断开始时间；历史终态任务可将 `finished_at` 保持为空。应用层必须兼容空值。

不得修改 V1 至 V12，不得通过迁移自动删除重复节点。

## 14. API 错误与可观测性

新增或沿用稳定错误码：

| 错误码 | 场景 |
| --- | --- |
| `NODE_HOSTNAME_DUPLICATE` | 主机名冲突 |
| `NODE_IP_DUPLICATE` | IPv4 冲突 |
| `NODE_TEST_ALREADY_RUNNING` | 同集群节点测试重复提交 |
| `COMPONENT_GROUP_PREVIOUS_STEP_FAILED` | 组内前序步骤失败，当前步骤跳过 |
| `COMPONENT_COMMON_PREREQUISITE_FAILED` | 组件公共前置失败 |
| `MINIO_OPERATOR_NOT_READY` | Operator 超时未就绪 |
| `MINIO_TENANT_NOT_READY` | Tenant、Pod、PVC 或 Service 未就绪 |
| `NFS_MOUNT_CONFLICT` | 目标已有不同挂载源或类型 |
| `NFS_MOUNT_TIMEOUT` | 挂载命令超时 |
| `JOB_CLUSTER_MISMATCH` | 任务不属于路由中的集群 |

事件和日志至少包含 `job_id`、步骤 ID、组件组键、节点 ID、状态、原因码和安全错误摘要。所有 MinIO Secret、SSH 密码、私钥和令牌继续使用现有脱敏规则，禁止进入任务事件和数据库错误字段。

### 14.1 任务执行文件永久留痕

每个任务按“步骤/节点”保存互不覆盖的执行证据，执行成功和失败均保留：

```text
data/jobs/<jobId>/evidence/<stepKey>/<hostname>/
├── runtime.env
├── step.sh 或 command.sh
├── phase3.sh
├── resources/                 # 实际分发的 YAML、Chart、配置和凭据
├── execution.log
├── result.properties
└── checksums.sha256
```

- `checksums.sha256` 对脚本、配置、资源、日志和结果文件逐文件计算 SHA-256。
- `result.properties` 保存任务、步骤、节点、成功状态、退出码、完成时间和日志路径。
- 根据运维留痕要求，`tenant.env`、kubeconfig 等凭据文件允许在证据资源中原文保存；任务事件、页面日志和数据库错误字段仍不得输出凭据内容。
- 控制端证据目录在支持 POSIX 权限时设置为目录 `0700`、文件 `0600`。
- 远程执行文件按 `/tmp/kubefoundry/jobs/<jobId>/steps/<stepKey>/<hostname>/` 保存，组件资源按 `/tmp/kubefoundry/jobs/<jobId>/resources/<groupKey>/<stepKey>/` 保存，权限移除 group/other 访问。
- KubeFoundry 不在步骤结束、任务结束或固定周期内清理上述控制端和远程文件，也不配置自动留存周期。
- 远程目录位于 `/tmp`，KubeFoundry 不主动清理，但操作系统重启、`systemd-tmpfiles` 或管理员操作仍可能删除；正式审计证据以控制端 `data/jobs/.../evidence` 为准。

## 15. 前端改造

### 15.1 节点配置页

- 增加“测试全部节点”和“仅重试失败节点”。
- 编辑器显示主机名/IP 重复的字段级错误，并阻止提交。
- 后端返回唯一性错误后，把错误定位到对应输入框，而非只显示全局消息。
- 批量测试活动区按节点展示等待、执行阶段、成功和失败。

### 15.2 Kubemate 组件页

- 删除总开关及相关说明。
- 组件组选项卡始终可见，根据组实际状态决定是否可编辑。
- 全部关闭时显示“当前未选择任何 Kubemate 组件”。
- 存储与日志组展示 MinIO 强类型配置及离线版本风险提示。

### 15.3 安装详情页

- 安装概览展示任务历史列表。
- 任务执行页增加任务选择器，并以路由参数保持选择。
- 支持 `partial_success`、组级失败和步骤 `skipped` 的视觉状态。
- 切换任务时关闭旧实时连接，避免日志串流。

## 16. 后端改造边界

| 模块 | 主要改动 |
| --- | --- |
| `ClusterService` | 节点规范化、冲突查询、唯一约束异常映射 |
| `NodeRepository` | 按集群查询规范化主机名/IP，排除当前节点 |
| `NodeTestService` | 稳定的重复任务错误码，保持逐节点非 fail-fast |
| `ClusterComponentService` | 移除总开关业务语义，增加 MinIO 强类型配置 |
| `InstallationSnapshotPayload` | 移除总开关判断，保存 MinIO 非敏感配置和版本 |
| `BaseInstallPlanFactory` | 加入 CoreDNS 反亲和步骤 |
| `ComponentPlanFactory` | 只按组件组选项生成计划，声明组级失败策略 |
| `JobService` | 支持 `ABORT_GROUP`、`skipped`、`partial_success` 和任务时间 |
| `ComponentInstallationStateService` | 按组件组独立完成状态转换 |
| `JobController` | 任务类型过滤、时间字段、集群归属校验 |
| `SpaForwardController` | 覆盖新的集群任务详情路由 |

## 17. Bash 改造边界

- 新增 `19-configure-coredns-affinity.sh`，不复用旧 `39-update-coredns.sh`。
- 强化 `32-mount-nfs-workers.sh` 的精确挂载检查、冲突处理、超时与后置验证。
- 完善 `49-install-minio.sh`，强制 Operator、Tenant、Secret、PVC、Pod 和 Service 就绪闭环。
- 所有新增或修改脚本使用统一日志函数、检查退出码、保持 LF，不执行内部 SSH，不修改发布介质原文件。
- 新增 Bash 测试通过伪造的 `kubectl/findmnt/mount/timeout` 验证分支与命令调用次数。

## 18. 测试设计

### 18.1 Java 后端

- 节点创建和编辑分别覆盖主机名冲突、IP 冲突、大小写、空格、IPv4 前导零和排除自身。
- 两个并发请求写入相同主机名或 IP 时，仅一个成功。
- 草稿复制允许存在，转为正式节点前必须解决冲突。
- 集群级测试选择全部节点；单节点失败不影响其他节点结果。
- 组件总开关不再影响计划；任一组启用即可生成该组步骤。
- 组件组 A 失败后，A 的后续步骤跳过，B 继续执行并成功。
- 公共前置失败后全部组件组步骤跳过，任务为 `failed`。
- 混合成功/失败结果计算为 `partial_success`，组件状态分别正确。
- 任务列表按 ID 倒序、按集群和类型过滤，时间字段转换正确。
- 访问其他集群的任务详情返回 404 或稳定业务错误。

### 18.2 Vue 前端

- “测试全部节点”按钮状态、批量进度和失败重试。
- 节点重复字段即时提示及后端冲突错误回填。
- Kubemate 总开关不再渲染，组开关独立保存。
- 任务列表展示多个任务 ID，并按默认规则选择。
- 切换任务时步骤、日志、筛选与 SSE 全部切换，不混入迟到响应。
- F5 刷新任务详情路由可恢复同一任务。
- `partial_success` 和 `skipped` 文案、颜色与进度计算正确。

### 18.3 Bash

- CoreDNS 无 affinity、已有其他 affinity、已有目标规则三种场景。
- CoreDNS 单节点与多节点集群均可完成 rollout 验证。
- NFS 未挂载、正确挂载、错误源、错误类型、超时和重复执行。
- MinIO Operator 已存在/不存在、Secret 已存在/不存在、Tenant 重复应用。
- MinIO PVC Pending、Pod 未 Ready、Service 缺失均能超时失败并输出安全摘要。
- 日志中不存在 MinIO 凭据、SSH 密码或 Token。

### 18.4 集成验收

1. 新集群完成 Kubernetes 安装并验证 CoreDNS 软反亲和配置。
2. 一键测试全部节点，构造一个失败节点时其他节点继续完成。
3. 同集群并发新增重复节点，仅允许一个请求成功。
4. 分别单独启用五个可用组件组并安装成功。
5. 人为破坏 NFS 组，验证后续 Kubemate、Traefik 或 Prometheus 组仍执行。
6. 人为破坏 MinIO，验证存储与日志组后续步骤跳过、其他组不受影响。
7. 重试失败组产生新任务 ID，旧任务记录保持不变。
8. 同一集群至少存在三个安装任务，可切换查看且刷新后保持任务 ID。
9. NFS 已正确挂载时重复执行脚本，确认未再次调用 `mount`。
10. x86_64 与 ARM64 发布介质分别完成静态检查；缺少真实 ARM64 环境时保留明确未验收项。

## 19. 实施顺序

### M1：节点与配置交互

- 节点规范化、唯一约束迁移、前后端冲突提示。
- 测试全部节点入口与批量结果展示。
- 移除 Kubemate 总开关，调整配置契约与快照。

### M2：脚本可靠性

- CoreDNS 反亲和脚本与基础计划接入。
- NFS 精确挂载检测、超时与测试。

### M3：组件组隔离

- 步骤失败策略、`skipped` 和 `partial_success`。
- 组件组状态独立收敛与重试。
- 任务事件和前端状态展示。

### M4：任务历史详情

- 任务时间字段、列表过滤与规范路由。
- 任务 ID 选择、SSE 切换隔离和刷新恢复。
- 除 MinIO 外的功能联合回归、部署文档和阶段验收清单同步。

### M5：MinIO 最终交付

- 在其他优化完成联合回归后，执行 MinIO Operator/Tenant 固定版本准入评审。
- 完成脚本、离线介质、凭据保护、就绪门禁和存储与日志最小链路。
- 交付 `MinIO真实环境部署与验证操作手册.md`，并由另一位操作者在隔离的真实测试环境按文档复现。
- 完成全部 v0.3.1 功能、发布包和最终验收。

## 20. 风险与控制

| 风险 | 影响 | 控制措施 |
| --- | --- | --- |
| MinIO 开源 Operator 上游已归档 | 安全修复和 Kubernetes 兼容性不可持续 | 冻结离线版本、专项评审、发布门禁、保留移出版本范围的选项 |
| 组件失败后继续执行掩盖整体异常 | 用户误以为全部成功 | 引入 `partial_success`，按组汇总并突出失败组 |
| 节点唯一迁移遇到历史重复 | 应用无法启动 | 升级前只读扫描、备份、人工处理，不自动删除 |
| NFS 检查误判父级挂载 | 重复挂载或覆盖现有挂载 | 使用精确 mountpoint 查询并核对 source/fstype |
| CoreDNS Patch 覆盖用户 affinity | 调度策略被破坏 | 只追加目标规则，保留现有字段，重复规则检测 |
| 切换任务时旧请求迟到 | 页面显示其他任务日志 | 请求序号、jobId 校验、切换前关闭 SSE 和清空状态 |
| 新增任务终态影响旧前端 | 状态显示未知或持续加载 | 前后端同版本发布，统一终态集合，契约测试覆盖 |
| 组件组继续执行产生共享资源竞争 | 后续组出现连锁失败 | 仍按固定顺序串行，仅放宽失败边界，不并行 Helm |
| 永久明文留痕泄露凭据 | 获得运行账户或 root 权限的人员可读取 MinIO、kubeconfig 等敏感内容 | 控制端目录 `0700/0600`、远程目录移除 group/other 权限，限制主机登录与备份访问权限 |

## 21. 发布与回滚

- 数据库升级前备份 H2 数据文件并执行节点重复检查。
- 前端、后端和脚本作为同一发布包部署，禁止只升级其中一层。
- V13/V14 执行后回滚应用版本前，应确认旧版本可忽略新增列和新增状态；旧前端不认识 `partial_success`，因此不得单独回滚前端。
- CoreDNS Patch 回滚只移除带 KubeFoundry 明确特征的目标反亲和规则，不删除用户其他 affinity。
- NFS 冲突处理不执行自动卸载，因此失败后可由管理员确认现场再处理。
- MinIO 部署失败时保留已创建资源供诊断；自动清理必须另行设计，不能在失败处理里删除 PVC 或 Secret。

## 22. 设计待评审项

1. 当前离线 MinIO Operator 的确切版本、许可证状态、已知漏洞和支持的 Kubernetes 版本是否允许进入 v0.3.1。
2. MinIO Tenant 的生产最小拓扑、容量和 StorageClass 默认值是否由产品固定，还是要求用户显式填写。
3. `partial_success` 是否同步映射为新的集群展示状态，或仅作为任务状态并由组件组状态表达安装结果。
4. 节点历史重复数据的升级处理流程和运维提示形式。
5. 是否在 v0.3.1 保留旧 `/jobs/{jobId}/execution` 路由一个版本后再删除。

## 23. 完成定义

- 七项优化均有代码、自动化测试、中文接口说明和验收记录。
- CoreDNS 反亲和配置幂等且不影响单节点调度。
- MinIO 在无 Console、无在线下载条件下完成 Operator 与 Tenant 部署并通过就绪检查。
- MinIO 作为最后一个开发任务完成，并交付经过真实测试环境复现的中文操作手册。
- 全部节点可一键测试，同集群正式节点主机名和 IPv4 在并发写入下仍唯一。
- Kubemate 总开关从页面和业务判断中移除，各组件组独立控制。
- NFS 正确挂载可安全跳过，冲突挂载和超时可控失败。
- 单个组件组失败不会阻塞其他无依赖组件组，任务和组状态准确反映部分成功。
- 集群安装详情可按任务 ID 查看历史过程，刷新和切换不会混合数据。
- 每个步骤和节点永久保留资源、脚本、日志、执行结果及 SHA-256；远程 `/tmp` 执行目录不由 KubeFoundry 清理。
- Java、Vue、Bash、数据库迁移、LF、脱敏和发布包验证全部通过。
