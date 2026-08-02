# KubeFoundry v0.3.0 Kubemate 组件安装设计

## 1. 文档信息

| 项目 | 内容 |
| --- | --- |
| 版本 | v0.3.0 |
| 状态 | 初稿，待评审 |
| 日期 | 2026-08-02 |
| 开发分支 | `codex/web-wizard-v0.3.0` |
| 适用范围 | Vue 3 前端、Java 17 后端、H2/Flyway、Bash phase3 组件脚本 |

## 2. 背景

v0.2.1 已完成 Kubernetes 基础框架安装、集群配置与安装模块拆分、安装快照、配置锁定和远程重置闭环。当前 Java 安装计划只编排 `phase2_k8s_base`，`scripts/steps/phase3_ecosystem` 尚未接入 Web 安装流程。

“03 / Kubemate 组件”页面目前只保存 `nfs`、`loki`、`traefik` 三个开关，并明确不参与安装。现有 phase3 脚本也仍保留以下问题：

- 依赖管理节点本地环境或目标节点上的固定介质目录，未按 Java 远程步骤的资源分发模型运行。
- Helm 只在旧 Bash 主入口运行前检查，Java 安装流程不会把 Helm 部署到控制节点。
- 部分脚本包含固定主机名、固定路径、交互式命令、重复执行失败或输出敏感信息等问题。
- `main.sh` 将组件、运维配置、备份和清理任务混合在同一 phase3 流程中，范围大于本版本需求。
- 已由 v0.2.1 安装完成的集群处于配置锁定状态，如果只在原安装计划末尾追加 phase3，将无法直接补装组件。

## 3. 版本目标

v0.3.0 完成以下目标：

1. 将选定的 phase3 组件纳入 Java 安装编排、任务日志、失败处理和验证体系。
2. 在“03 / Kubemate 组件”中配置是否启用 Kubemate 组件及各组件组。
3. 由 KubeFoundry 离线介质向所有控制节点部署与节点架构匹配的 Helm。
4. 支持新集群在 Kubernetes 基础安装完成后继续安装组件。
5. 支持 v0.2.1 已安装集群直接补装尚未安装的组件组，不要求先执行远程重置。
6. 将有强依赖的 `OpenEBS、MinIO、Loki、Alloy` 作为一个不可拆分的原子配置组。
7. 保证安装计划由后端依据配置快照生成，前端不能绕过配置任意拼装 phase3 步骤。
8. 补齐组件资源预检查、幂等执行、状态展示、失败重试和重置清理。

## 4. 非目标

以下内容不属于 v0.3.0：

- Elasticsearch 与 SkyWalking 安装。
- F5 高可用配置。
- etcd 备份、Traefik 定时清理、应用日志定时清理等通用运维任务。
- 普通用户 kubectl 权限管理。
- 组件卸载入口和组件版本升级中心。
- 跨集群复用外部 Helm 仓库或联网下载 Chart。
- Redis 哨兵模式的真实安装；本版本仅保留不可启用的占位组。

上述能力后续应拆分为“可观测性扩展”“集群运维”或独立版本，不继续堆叠在 Kubemate 组件安装中。

## 5. 核心设计原则

### 5.1 组件组是配置和执行原子

页面保存的是组件组，不直接保存单个脚本开关。一个组件组被启用后，其内部步骤全部进入计划；不允许通过安装 API 只选择组内一部分脚本。

组件组失败时整组状态为 `failed`。已经成功的内部步骤依靠幂等逻辑跳过或安全重放，用户重试时仍从完整组计划开始，不维护难以验证的客户端续跑位置。

### 5.2 配置决定期望状态，任务记录实际状态

`03 / Kubemate 组件` 保存“期望安装哪些组”。是否已经安装、正在安装或安装失败，由服务端组件状态和任务记录表达，不能把 `enabled=true` 直接解释为“已安装”。

### 5.3 新集群和存量集群共用同一份组件计划

- 新集群：`install` 任务先执行 Kubernetes 基础计划，再执行组件公共前置步骤和已启用组件组。
- v0.2.1 已安装集群：`component_install` 任务只执行组件公共前置步骤和待安装组件组。

两条路径必须调用同一个 `ComponentPlanFactory`，避免全量安装与补装产生不同的顺序、资源或验证规则。

### 5.4 服务端生成权威计划

安装任务只接受风险确认，不接受客户端传入任意 `steps`。服务端在集群级事务锁内读取集群、节点、组件配置和配置版本，完成校验后创建不可变快照并生成计划。

组件配置、实际计划、任务快照和执行日志必须一致。任务开始后修改页面状态不能改变正在运行的计划。

## 6. 组件组定义

### 6.1 组件组清单

| 组键 | 页面名称 | 组内内容 | v0.3.0 状态 | 可独立安装 |
| --- | --- | --- | --- | --- |
| `nfs` | NFS 存储 | NFS 服务配置、Provisioner、Worker 挂载 | 可用 | 是 |
| `kubemate` | Kubemate 管理组件 | Kubemate UI 及所需配置 | 可用 | 是 |
| `traefik` | Traefik 网关 | Traefik、Traefik Mesh、必要的 CoreDNS 配置 | 可用 | 是 |
| `storage_observability` | 存储与日志套件 | OpenEBS、MinIO、Loki、Alloy | 可用 | 是 |
| `prometheus` | Prometheus 监控 | Prometheus 套件、Metrics Server | 可用 | 是 |
| `redis_sentinel` | Redis 哨兵模式 | Redis Sentinel | 暂不可用 | 是，后续实现 |

页面中 Redis 哨兵组必须显示“脚本待完善”，开关禁用。后端同样拒绝 `redis_sentinel.enabled=true`，返回稳定错误码 `COMPONENT_GROUP_UNAVAILABLE`。仓库中现有 `43-install-redis-sentinel.sh` 引用了不完整的相对资源路径，不能视为可交付脚本。

### 6.2 公共前置步骤

只要至少一个可用组件组的有效状态为启用，就加入以下公共步骤：

1. 在所有控制节点离线安装 Helm。
2. 在主控制节点验证 Kubernetes API 健康。
3. 按需创建 `kubemate-system` 等公共命名空间。
4. 在主控制节点设置 `KUBECONFIG=/etc/kubernetes/admin.conf` 并验证 Helm 可访问集群。

Helm 是控制节点工具，不归属于任何单一组件组。重复执行时，如果现有 Helm 版本与介质版本一致则直接通过；版本不一致时必须明确升级，不得静默继续使用未知版本。

### 6.3 依赖图与执行顺序

```text
Kubernetes 集群健康
  └── 所有控制节点安装 Helm
        └── 创建公共命名空间
              ├── NFS 组
              ├── Kubemate 组
              ├── Traefik 组
              ├── 存储与日志套件
              │     └── OpenEBS -> MinIO -> Alloy -> Loki
              ├── Prometheus 组
              └── Redis 哨兵组（v0.3.0 不可执行）
```

除公共前置外，各组件组之间不建立隐式依赖，任何可用组都必须能够单独安装。为减少多个 Helm 操作同时修改集群资源造成的不确定性，v0.3.0 按以下固定顺序串行执行已启用组：

```text
NFS -> Kubemate -> Traefik -> 存储与日志套件 -> Prometheus
```

固定顺序只用于确定性编排，不代表组间依赖。后续只有在验证无共享资源竞争后才考虑组件组并行。

## 7. phase3 脚本映射

| 计划步骤 | 现有脚本来源 | 目标范围 | 处理方式 |
| --- | --- | --- | --- |
| 安装 Helm | 新增脚本 | 所有控制节点 | 按 `amd64/arm64` 分发离线二进制 |
| 创建命名空间 | `30-create-namespace.sh` | 主控制节点 | 改为 `kubectl create --dry-run=client -o yaml \| kubectl apply -f -` |
| 安装 Kubemate | `31-install-kubemate-ui.sh` | 主控制节点 | 远端执行，不修改本地介质文件 |
| 配置 NFS exports | `32-configure-nfs-exports.sh` | 匹配的集群节点 | 拆除脚本内二次 SSH，目标由 Java 解析 |
| 安装 NFS Provisioner | `32-install-nfs.sh` | 主控制节点 | 改为 `helm upgrade --install` |
| 挂载 NFS | `32-mount-nfs-workers.sh` | Worker 节点 | 拆除脚本内循环 SSH，由 Java 并发执行 |
| 安装 Traefik | `36-install-traefik.sh` | 主控制节点 | 使用分发到任务目录的清单 |
| 安装 Traefik Mesh | `37-install-traefik-mesh.sh` | 主控制节点 | 纳入 Traefik 组 |
| 更新 CoreDNS | `39-update-coredns.sh` | 主控制节点 | 删除 `kubectl edit` 交互命令，改为声明式应用 |
| 安装 OpenEBS | `47-install-openebs.sh` | 主控制节点及 Worker 准备步骤 | 目录准备由独立 Worker 步骤完成 |
| 安装 MinIO | `49-install-minio.sh` | 主控制节点 | 禁止打印访问令牌，补齐非交互验证 |
| 安装 Loki | `35-install-loki.sh` | 主控制节点 | 在 OpenEBS、MinIO 就绪后执行 |
| 安装 Alloy | `48-install-alloy.sh` | 主控制节点 | 在 Loki 就绪后执行 |
| 安装 Prometheus | `38-install-prometheus.sh` | 主控制节点及 Worker 准备步骤 | 删除固定 `k8sw1/k8sw2`，按实际 Worker 处理 |
| 安装 Metrics Server | `40-install-metrics-server.sh` | 主控制节点 | 纳入 Prometheus 组 |

`33`、`34`、`41`、`42`、`44`、`45`、`46` 不进入本版本安装计划。其中 Traefik 清理属于运维任务，不因启用 Traefik 自动写入 cron。

## 8. Helm 部署设计

### 8.1 介质与架构

仓库当前包含 `tools/helm-amd` 和 `tools/helm-arm`。v0.3.0 应统一文件命名和资源键，例如：

```text
helm_amd64 -> tools/helm-amd
helm_arm64 -> tools/helm-arm
```

Java 根据每个控制节点的架构选择资源，分发到任务临时目录，校验 SHA-256 后安装到 `/usr/local/bin/helm`。不得从互联网下载，不得把 amd64 二进制分发到 arm64 节点。

### 8.2 幂等和所有权

- `helm version --short` 成功且版本符合要求时跳过复制。
- KubeFoundry 覆盖或新装 Helm 时，在受管目录写入版本和校验和标记。
- 如果节点已存在非 KubeFoundry 管理且版本不兼容的 Helm，预检查失败并提示用户处理，不直接覆盖未知文件。
- 远程重置只清理由 KubeFoundry 标记安装的 Helm；用户原有 Helm 保留。

### 8.3 可用性验证

每个控制节点执行：

```bash
helm version --short
KUBECONFIG=/etc/kubernetes/admin.conf helm list -A
```

任一控制节点失败则公共前置步骤失败，不继续安装组件。

## 9. 配置模型

### 9.1 页面模型

“03 / Kubemate 组件”包含：

- “启用 Kubemate 组件安装”总开关。
- 六个组件组及组内组件说明。
- 每组的期望状态、实际安装状态、可用性和最近任务结果。
- NFS 组启用后展示其专属参数。

总开关关闭时保留子组选项，但所有子组的有效启用状态为关闭。重新打开后恢复保存值。已经安装的组不会因为关闭总开关而被卸载，页面必须明确显示“已安装”。

### 9.2 NFS 配置

NFS 组至少需要以下字段：

| 字段 | 规则 |
| --- | --- |
| NFS 服务器地址 | 必填 IPv4；匹配集群节点时可由 KubeFoundry 管理 exports |
| 共享目录 | 必须为安全的 Linux 绝对路径 |
| Worker 挂载目录 | 必须位于允许的数据目录，默认 `${kubernetes_work_dir}/nfs_root` |
| StorageClass 名称 | 必填，符合 Kubernetes 资源命名规则，默认 `nfs-storage` |
| exports 管理模式 | `managed` 或 `external` |

`managed` 模式要求服务器地址匹配一个已测试成功的集群节点，由 Java 将配置 exports 步骤定向到该节点。`external` 模式不修改外部服务器，只验证 NFS 端口和共享目录可挂载。

### 9.3 API 契约

建议将现有数组响应升级为明确的聚合对象：

```json
{
  "enabled": true,
  "groups": [
    {
      "key": "storage_observability",
      "name": "存储与日志套件",
      "enabled": true,
      "available": true,
      "components": ["openebs", "minio", "loki", "alloy"],
      "status": "not_installed",
      "config": {}
    }
  ]
}
```

接口保持在集群配置模块下：

```text
GET /api/clusters/{clusterId}/components
PUT /api/clusters/{clusterId}/components
```

后端只接受已知组键和强类型配置。未知字段、重复组键、不可用组启用、非法 NFS 参数必须返回 `400`，不能静默忽略。

## 10. 数据库存储与迁移

新增 Flyway `V9`，不修改已有 V1 至 V8。

建议调整如下：

```text
clusters
└── kubemate_enabled

cluster_components
├── cluster_id
├── component_key          # v0.3.0 起表示组件组键
├── enabled                # 期望状态
├── config_json            # 由强类型 DTO 读写，不接受任意结构
└── UNIQUE(cluster_id, component_key)

cluster_component_states
├── cluster_id
├── component_key
├── status                 # not_installed/installing/installed/failed
├── installed_version
├── last_job_id
├── last_error_code
└── UNIQUE(cluster_id, component_key)
```

配置与执行状态分表，避免保存页面配置时覆盖安装事实。

V8 数据迁移规则：

1. 原 `nfs` 和 `traefik` 保留同名组及启用状态。
2. 原 `loki=true` 映射为 `storage_observability=true`，因为 v0.3.0 不允许单独安装 Loki。
3. `kubemate`、`prometheus`、`redis_sentinel` 默认关闭。
4. 任一旧组件为启用时，`kubemate_enabled=true`；否则为 false。
5. 所有迁移组的实际状态初始化为 `not_installed`，不能因旧配置为 true 推断已经安装。
6. 历史安装任务保持原样，不回填虚假的组件安装成功记录。

## 11. 安装快照与计划生成

### 11.1 快照扩展

安装快照新增：

- `kubemateEnabled`。
- 已启用组件组键及固定顺序。
- 每组经过规范化和校验后的配置。
- Helm 版本、架构资源键和校验和。
- 各组件介质的相对路径和校验和。
- 组件计划版本，例如 `componentPlanVersion=1`。

快照不得包含 MinIO 令牌、密码、私钥或 SSH 密文。需要生成的 Kubernetes Secret 在执行时安全创建，只记录 Secret 名称，不在任务事件和标准输出中打印值。

### 11.2 计划工厂拆分

建议拆分当前 `InstallPlanFactory`：

```text
BaseInstallPlanFactory       # 现有 phase2 计划
ComponentPlanFactory         # 公共前置与组件组计划
InstallPlanAssembler         # 新集群全量计划组合
```

`ComponentPlanFactory` 只读取不可变快照，不直接查询实时数据库。`InstallPlanAssembler` 为新集群拼接基础计划和组件计划；存量集群补装直接使用组件计划。

### 11.3 资源分发

phase3 脚本不得假设远端存在 `${APP_DIR}/kube-media`。每个 `InstallStep` 显式声明所需资源，Java 只把已启用组的 Chart、values 和 YAML 分发到任务隔离目录，例如：

```text
/tmp/kubefoundry/jobs/{jobId}/resources/{groupKey}/
```

安装脚本只从该目录读取。任务结束后按现有安全清理规则删除临时资源，安装日志保留。

## 12. 安装流程

### 12.1 新集群全量安装

```text
配置预检查
  -> 创建安装快照
  -> phase2 Kubernetes 基础安装
  -> Kubernetes 健康验证
  -> 组件公共前置
  -> 按配置执行组件组
  -> 全量安装成功并锁定基础配置
```

总开关关闭或没有可用组启用时，不分发 Helm 和 phase3 介质，安装在 Kubernetes 健康验证后结束。

### 12.2 v0.2.1 存量集群补装

集群状态为 `installed` 时允许进入组件页面，但基础信息、节点和 Kubernetes 工作目录仍保持锁定。用户可启用尚未安装的可用组件组并发起组件预检查与安装。

```text
组件配置
  -> 组件预检查
  -> 创建组件安装快照
  -> 验证现有 Kubernetes 集群健康
  -> 组件公共前置
  -> 安装待安装组
  -> 更新各组状态
```

已安装组不能直接关闭或覆盖安装；卸载和版本升级不属于本版本。失败组允许在修正配置并重新预检查后重试。

### 12.3 任务类型和互斥

新增 `job_type=component_install`。`precheck`、`install`、`component_install`、`reset` 继续使用同一个集群级活动任务互斥锁。

组件组状态转换：

| 当前状态 | 事件 | 新状态 |
| --- | --- | --- |
| `not_installed/failed` | 组件任务接受 | `installing` |
| `installing` | 组内全部步骤成功 | `installed` |
| `installing` | 任一步骤失败或任务中断 | `failed` |
| `installed` | 集群远程重置成功 | `not_installed` |

一个任务包含多个组时，逐组更新状态。前一组成功、后一组失败时，成功组保持 `installed`，失败组为 `failed`，尚未执行组回到 `not_installed`。

## 13. 预检查设计

配置预检查和组件补装预检查复用同一套组级检查器。只检查有效启用的组件组，不应因未选择组件的介质缺失而阻塞安装。

公共检查：

1. 主控制节点 Kubernetes API 可访问且核心节点 Ready。
2. 所有控制节点架构已识别，并存在对应 Helm 二进制和校验和。
3. 主控制节点 `/etc/kubernetes/admin.conf` 存在且权限可用。
4. 目标节点任务目录可创建、空间充足。
5. 已启用组的全部离线资源存在且为普通文件或目录。
6. 组件组键、可用性、配置和依赖图合法。

组级检查示例：

- NFS：地址、导出目录、挂载目录、StorageClass 名称、2049 端口和管理模式。
- Traefik：清单完整、端口冲突、CoreDNS 目标配置可声明式更新。
- 存储与日志：Worker 数量、数据目录空间、StorageClass、Chart 和 values 完整性。
- Prometheus：至少一个 Worker、动态节点标签目标、监控数据目录空间。
- Kubemate：清单完整、NodePort 冲突、主控制节点地址可解析。

组件配置变化后，最近一次组件预检查立即失效。启动任务时再次校验预检查绑定的配置版本和介质校验和。

## 14. Bash 脚本改造要求

所有纳入计划的 phase3 脚本必须满足：

- 使用 `set -o errexit -o nounset -o pipefail`，函数和脚本正确返回非零退出码。
- 使用统一 `log_info/log_success/log_warn/log_error`，不打印 Secret、Token 或完整凭据。
- 使用 `helm upgrade --install`、`kubectl apply` 或等价幂等命令。
- 禁止 `kubectl edit`、交互式输入和依赖人工二次执行。
- 禁止固定 `k8sc1`、`k8sw1`、`k8sw2`，节点信息来自运行时环境和步骤目标。
- 禁止在脚本内部再次发起 SSH 或遍历节点；Java 负责任务目标解析和并发。
- 禁止对发布介质原文件执行 `sed -i`，需要替换的清单复制到任务目录后再渲染。
- 所有 Chart、values 和清单使用分发后的绝对路径。
- 使用有超时的 rollout/readiness 检查，不能用固定 `sleep` 代替最终验证。
- Helm release、命名空间、ConfigMap 和 StorageClass 使用明确名称与 namespace。
- 失败日志包含组件组、步骤、目标节点、资源名称和安全的错误摘要。

## 15. 前端交互

### 15.1 组件配置页

组件页按组展示，不再直接显示英文键。每组展示中文名称、包含内容、期望状态和实际状态。

- `未安装`：允许启用或关闭。
- `安装中`：只读，显示任务入口。
- `已安装`：只读，不提供关闭开关。
- `安装失败`：允许修正组配置并重新预检查。
- `暂不可用`：禁用开关并说明原因。

总开关关闭时，未安装组的子开关禁用但保留值。若存在已安装组，总开关不得被解释为卸载操作。

### 15.2 安装确认页

安装确认新增：

- 将安装的组件组及组内组件。
- 将跳过的组件组。
- Helm 目标控制节点和版本。
- NFS、数据目录、StorageClass 等关键非敏感参数。
- 新集群全量安装或存量集群组件补装的任务类型。

### 15.3 任务执行页

步骤按以下层级展示：

```text
Kubernetes 基础安装
组件公共前置
NFS
Kubemate
Traefik
存储与日志套件
Prometheus
```

未选择的组不生成空步骤。组失败时页面应明确区分“该组失败”“后续组未执行”和“此前组已安装”。

## 16. 重置与清理

远程重置在执行 kubeadm reset 前，根据最近一次安装快照和组件状态按依赖逆序清理 KubeFoundry 管理的组件：

```text
OpenEBS -> MinIO -> Alloy -> Loki
Prometheus
Traefik
Kubemate
NFS Provisioner -> Worker 挂载 -> 受管 exports 行
公共命名空间
```

清理必须遵守：

- 只删除带 KubeFoundry 标记或明确记录在快照中的资源。
- NFS `/etc/fstab` 和 `/etc/exports` 只删除带受管注释的行，不覆盖用户其他配置。
- 外部 NFS 模式不修改外部服务器。
- 组件清理失败时重置任务失败并保持配置锁，不能继续宣称集群已清理。
- Helm 只在确认由 KubeFoundry 安装且不再被其他任务使用时删除。
- 全部重置成功后，所有组件组状态回到 `not_installed`。

组件清理涉及远端系统文件和持久数据，实现前必须进行专项安全复核。

## 17. 错误码与可观测性

新增稳定错误码：

| 错误码 | 含义 |
| --- | --- |
| `COMPONENT_GROUP_UNKNOWN` | 未知组件组 |
| `COMPONENT_GROUP_UNAVAILABLE` | 当前版本不可安装该组 |
| `COMPONENT_CONFIG_INVALID` | 组件配置不合法 |
| `COMPONENT_PRECHECK_STALE` | 组件配置或介质变化导致预检查失效 |
| `COMPONENT_ALREADY_INSTALLED` | 请求重复安装已安装组 |
| `COMPONENT_DEPENDENCY_FAILED` | 组内前置组件未成功 |
| `HELM_MEDIA_MISSING` | 缺少目标架构 Helm 介质 |
| `HELM_CONFLICT` | 节点已有不兼容且非受管 Helm |

事件流至少记录任务类型、组件组、步骤、目标节点、开始和结束时间、退出码、资源版本及校验和。日志继续执行凭据脱敏，MinIO Token 等值不得进入事件、标准输出或数据库错误摘要。

## 18. 测试与验收

### 18.1 后端

- V8 到 V9 迁移正确保留 `nfs/traefik/loki` 的用户选择。
- 组件 API 覆盖总开关、六个组、未知键、不可用 Redis 和 NFS 强类型校验。
- 计划工厂仅包含有效启用组，并保证固定顺序和组内依赖。
- 新集群全量计划与存量集群补装计划复用相同组件步骤。
- 客户端不能通过 `steps` 参数绕过组件配置或拆分原子组。
- 安装快照包含组件配置和介质校验和，不包含凭据。
- 多组部分成功时状态转换正确，重启中断后运行组变为 `failed`。
- 集群级互斥覆盖预检查、全量安装、组件补装和重置。

### 18.2 Bash

- amd64、arm64 控制节点分别获得正确 Helm 二进制。
- 所有脚本至少连续执行两次，第二次成功且不会创建重复资源或重复系统配置行。
- 使用伪造的 `kubectl/helm/ssh` 命令验证参数、顺序、超时和错误传播。
- 脚本内不存在二次 SSH、固定节点名、`kubectl edit`、明文 Token 输出和介质原地修改。
- NFS managed/external 两种模式和安全路径校验通过。
- OpenEBS、MinIO、Loki、Alloy 的组内失败可阻止后续步骤并可重试。

### 18.3 前端

- 刷新后总开关、组选择、NFS 配置和实际状态恢复正确。
- Redis 哨兵组不可启用。
- 已安装组不会因关闭总开关显示为未安装或被提交卸载。
- 安装确认页与后端返回的实际计划一致。
- 任务页正确展示组成功、组失败和后续未执行状态。

### 18.4 集成与真实环境

- 新集群完成 phase2 与至少一个组件组的一键安装。
- v0.2.1 已安装集群无需重置即可成功补装组件。
- 每个可用组件组分别进行一次单独安装验收。
- 存储与日志套件完成完整组安装及就绪验证。
- 组件安装失败、修复、重试闭环通过。
- 安装组件后的远程重置能清理受管资源且不误删用户资源。
- x86_64 和 ARM64 分别完成 Helm 分发与非破坏性预检查；缺少真实 ARM64 环境时必须明确保留未验收项。

## 19. 实施阶段建议

### M1：配置与迁移

完成 V9、组件组 API、NFS 配置、总开关、前端配置页和契约测试。

### M2：公共执行能力

完成安装快照扩展、计划工厂拆分、按架构分发 Helm、phase3 资源分发和公共预检查。

### M3：独立组件组

依次完成 NFS、Kubemate、Traefik、Prometheus，并逐组完成脚本幂等改造和验证。

### M4：存储与日志套件

按 `OpenEBS -> MinIO -> Alloy -> Loki` 完成原子组、就绪门禁、失败重试和敏感信息保护。

### M5：补装、重置与发布验收

完成存量集群 `component_install`、组件状态机、逆序清理、双架构静态检查和真实集群验收。

## 20. 风险与控制

| 风险 | 影响 | 控制措施 |
| --- | --- | --- |
| 旧 phase3 脚本依赖固定路径 | Java 远程执行找不到介质 | 每步声明资源，分发到任务隔离目录 |
| 组件配置和任务计划不一致 | 安装了未选择组件 | 事务内快照，服务端生成计划 |
| 存储与日志组部分成功 | 状态难以判断 | 原子组状态、严格顺序、幂等重试 |
| 现有 Helm 被覆盖 | 破坏用户环境 | 版本冲突预检查、受管标记、禁止静默覆盖 |
| MinIO Token 进入日志 | 凭据泄露 | 禁止打印 Secret，日志脱敏测试 |
| NFS 清理误改系统文件 | 挂载或共享异常 | 受管标记行、路径白名单、专项安全复核 |
| 存量集群无法使用新功能 | 必须重装 Kubernetes | 独立 `component_install` 补装路径 |
| Redis 脚本不完整却可选择 | 安装必然失败 | 前后端共同标记 unavailable |
| ARM64 Helm 未验证 | ARM 节点安装失败 | 架构资源测试和 ARM64 验收门禁 |

## 21. 完成定义

同时满足以下条件，v0.3.0 才视为完成：

- 六个组件组在页面和 API 中可见，Redis 哨兵明确不可用，其余五组可安装。
- 新集群能够按配置完成 Kubernetes 基础与组件一键安装。
- v0.2.1 已安装集群能够直接补装未安装组件组。
- Helm 在所有控制节点按架构离线部署并验证可用。
- `OpenEBS、MinIO、Loki、Alloy` 只能作为一个组配置和执行。
- 所有纳入计划的 phase3 脚本满足幂等、非交互、无二次 SSH、无敏感信息输出要求。
- 配置、快照、计划、任务步骤和最终组件状态一致。
- 安装失败可安全重试，远程重置可清理受管组件且不误删用户资源。
- Java、Vue、Bash、迁移、LF 和敏感信息检查全部通过。
- 中文部署、使用、接口和验收文档与实际行为同步。
