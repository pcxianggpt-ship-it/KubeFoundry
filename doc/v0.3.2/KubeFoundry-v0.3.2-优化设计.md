# KubeFoundry v0.3.2 优化设计

## 1. 文档信息

| 项目 | 内容 |
| --- | --- |
| 目标版本 | v0.3.2 |
| 状态 | 设计初稿，待评审 |
| 日期 | 2026-08-20 |
| 前置版本 | v0.3.1 |
| 适用范围 | Vue 3 前端、Java 17 后端、H2/Flyway、Bash 安装与验证脚本、离线介质 |
| 需求来源 | [优化需求记录](./优化需求记录.md) |

## 2. 设计范围与优先级

v0.3.2 包含以下九项需求：

1. 安装任务失败重跑与续跑，并在步骤执行前后运行验证脚本。
2. 修复本地 YUM 仓库 HTTP 403。
3. 安装计划和安装进度按部署单元分组。
4. 为 MinIO 增加 PVC、CPU 和内存配置，并在安装开始时校验至少配置 4 个正式工作节点。
5. 在全部安装任务末尾增加 etcd 备份单元。
6. 安装范围确认页的节点清单显示 IP。
7. 重置流程不依赖尚未安装的 Helm。
8. 重置时清理 KubeFoundry 写入的参数配置。
9. 使用离线 Helm Chart 完成 Redis Sentinel 模式部署。

实施优先级保持需求记录中的约定：先实现失败续跑，再修复 YUM 仓库权限，之后按依赖关系实施其他需求。

## 3. 当前基线

- `InstallStep` 已包含安装脚本、资源、输出产物和内联 `verifyCommand`，但验证命令只在安装脚本成功后执行。
- `RemoteStepRunner` 当前把安装脚本和后置验证拼成一条远端命令，无法在上传安装介质前独立判断步骤是否已完成。
- `JobService` 已支持 `skipped` 和 `status_reason`，但 `skipped` 仅用于任务中止或组件组前置失败。
- 应用重启时，未完成安装任务会被标记为 `interrupted`，不会自动恢复。
- `scripts/verify/` 已覆盖大部分步骤，但部分脚本仍通过 `PROJECT_ROOT`、`config.sh` 和嵌套 SSH 执行，不符合当前 Java 远端逐节点运行模型。
- `10-setup-yum-source.sh` 解压仓库并启动 httpd，但未设置完整的目录遍历权限和 SELinux 内容标签。
- 安装确认页已加载节点 IP，但节点清单只展示主机名和角色。
- `ClusterResetService` 只允许重置安装成功并锁定的集群，且组件清理脚本强制要求 Helm 存在。
- Redis 目录中现有介质是旧 `redis-ha` Chart，不是需求指定的 Bitnami Redis Chart；Redis 组件组目前标记为不可用。
- etcd 备份脚本仍包含 `crontab -e` 等交互命令，尚未进入 Java 安装计划。

## 4. 总体设计

```text
普通安装或续跑任务
  -> 读取不可变安装快照
  -> 生成带部署单元元数据的安装计划
  -> 对每个步骤、每个目标节点执行前置验证
       -> 已满足：恢复必要产物 -> 标记“已验证并跳过”
       -> 未满足：校验并上传安装资源 -> 执行安装 -> 执行后置验证
       -> 验证异常：安全失败，不把异常误判成“尚未安装”
  -> 汇总部署单元状态
  -> 最后执行 etcd 备份单元
```

核心原则：

- 续跑创建新任务，不修改原任务的步骤、日志、事件和终态。
- 远端实际状态优先于旧任务状态；旧任务只用于选择续跑来源和审计。
- 验证脚本必须只读、幂等、有超时，并能区分“目标未满足”和“验证自身异常”。
- 前置验证在安装资源校验和上传之前执行；已完成步骤不因缺少无用介质而失败。
- 安装快照、步骤键、部署单元和来源任务必须持久化，页面不得按中文名称猜测分组或续跑关系。
- 重置只清理能够证明由 KubeFoundry 管理的内容，不删除无法确认所有权的用户配置。

## 5. 安装任务失败重跑与续跑

### 5.1 用户入口与任务关系

失败、已中断或部分成功的 `install`、`component_install` 任务提供“续跑”入口。续跑请求创建一个新的任务 ID，并记录来源任务 ID：

```http
POST /api/clusters/{clusterId}/jobs/{sourceJobId}/resume
```

成功返回 `202 Accepted`：

```json
{
  "job_id": 126,
  "status": "pending",
  "source_job_id": 123,
  "run_mode": "resume"
}
```

约束：

- 来源任务必须属于路径中的集群，且类型为 `install` 或 `component_install`。
- 来源任务状态只允许 `failed`、`interrupted` 或 `partial_success`。
- 同一集群存在活动安装、组件安装、续跑或重置任务时返回冲突，不并发修改集群。
- 续跑复用来源任务的不可变安装快照、节点清单、组件配置和介质校验信息，不使用页面当前尚未保存或已经变化的配置。
- 节点身份、SSH 连接参数或关键路径与来源快照不一致时拒绝续跑，要求重新预检或人工确认。
- 来源任务和新任务永久保留，通过 `source_job_id` 形成审计链，不允许循环引用。

v0.3.2 完整快照额外保存以下非敏感执行基线：

- Pod/Service 网段、Registry 地址和端口、Kubemate 开关等集群安装参数。
- 每个节点解析后的 `paths/env/advanced` 运行参数。
- 节点主机指纹和认证信息 SHA-256 指纹；不保存明文密码、密文、IV、Token 或私钥。
- 介质相对路径和 SHA-256。续跑创建时只绑定来源校验和，不提前读取大文件；步骤确需安装时再校验实际介质。

缺少上述字段或 `componentPlanVersion` 不是 `v0.3.2` 的历史快照只允许查看，不开放续跑。

数据库迁移新增：

```text
jobs.source_job_id BIGINT NULL -> jobs.id
jobs.run_mode VARCHAR(16) NOT NULL DEFAULT 'normal'
job_steps.step_key VARCHAR(128) NOT NULL
job_steps.stage_key VARCHAR(128) NOT NULL
job_steps.stage_name VARCHAR(128) NOT NULL
job_steps.stage_order INTEGER NOT NULL
job_steps.step_order_in_stage INTEGER NOT NULL
```

历史任务迁移时，无法可靠推断的 `step_key/stage_key` 使用稳定的 `legacy-*` 值，页面仍可展示，但历史任务不开放续跑。

### 5.2 步骤模型

`InstallStep` 由单一后置 `verifyCommand` 调整为显式执行模型：

| 字段 | 含义 |
| --- | --- |
| `stepKind` | `INSTALL`、`VALIDATION` 或 `MAINTENANCE` |
| `verifyScript` | 在目标节点运行的验证脚本；`INSTALL` 步骤必填 |
| `skipPreparationScript` | 前置验证通过后恢复下游必需产物的可选脚本 |
| `stageKey/stageName/stageOrder` | 安装进度部署单元元数据 |
| `outputs` | 当前步骤为后续步骤生成的任务产物 |

`VALIDATION` 步骤本身就是验证动作，不再套一层前置验证。`MAINTENANCE` 用于最终 etcd 备份等不能因“已经执行过”而永久跳过的动作。

### 5.3 验证脚本契约

统一使用以下退出码：

| 退出码 | 含义 | 编排行为 |
| --- | --- | --- |
| `0` | 目标状态已满足 | 跳过安装，状态原因为 `PREVERIFY_SATISFIED` |
| `10` | 目标状态未满足 | 继续执行安装脚本 |
| `20` | 验证环境或依赖异常 | 当前节点失败，不执行安装 |
| `21` | 验证超时 | 当前节点失败，不执行安装 |
| 其他 | 未分类验证异常 | 当前节点失败，不执行安装 |

验证未满足和验证异常必须分开，避免 SSH 异常、权限不足或 Kubernetes API 不可达时误执行 `kubeadm init`、Helm 安装等有副作用操作。

验证脚本规则：

- 文件名为 `scripts/verify/<phase>/verify-<step-key>.sh`。
- 在当前目标节点运行，不再嵌套 SSH 到其他节点。
- 只读取 `runtime.env` 中的白名单变量，不依赖控制端 `PROJECT_ROOT` 或原始 `cluster.yaml`。
- 不修改系统、刷新 Token、创建资源或写入用户配置。
- 输出中文检查摘要，不输出密码、Token、Secret、kubeconfig 内容或完整敏感命令。
- 所有网络、systemd、kubectl、helm 等检查都设置超时。
- 同一环境连续运行两次应得到相同结论。

计划构建时进行完整性校验：每个 `INSTALL` 步骤必须存在普通文件形式的验证脚本。缺失、符号链接、CRLF 或不可识别退出码均阻止发布包验收。

### 5.4 单节点执行状态机

```text
pending
  -> verifying
       -> 0  -> skipped(PREVERIFY_SATISFIED)
       -> 10 -> running -> verifying_after
                            -> 0  -> success
                            -> 非0 -> failed(POSTVERIFY_FAILED)
       -> 20/21/其他 -> failed(PREVERIFY_ERROR)
```

数据库仍使用兼容状态 `pending/running/success/failed/skipped`；`verifying` 和 `verifying_after` 通过事件阶段和节点消息展示，不新增数据库终态。前置验证通过的节点保存：

```text
status=skipped
message=执行前验证通过，安装操作已跳过
exit_code=0
```

步骤级状态按节点汇总：

- 全部节点为 `skipped(PREVERIFY_SATISFIED)`：步骤 `skipped`，原因相同。
- `success` 与前置验证跳过混合：步骤 `success`，并显示跳过节点数。
- 任一节点安装或验证失败：按现有 `failFast` 和组件组失败边界处理。
- 因前置依赖失败的 `skipped` 与验证通过的 `skipped` 必须通过 `status_reason` 区分。

### 5.5 资源与产物恢复

前置验证顺序必须早于大体积安装介质解析、SHA-256 校验和上传。验证返回 `10` 后才校验该步骤资源；资源缺失时以 `STEP_RESOURCE_UNAVAILABLE` 失败。

步骤 `18-init-k8s-cluster` 是特殊产物步骤：它会生成控制节点和 Worker 加入命令。续跑时若集群初始化验证已经通过，新任务中却没有旧任务的临时产物。为此新增只负责恢复产物的 `skipPreparationScript`：

- 在主控制节点重新生成短时有效的 Worker Join Token。
- 重新上传证书并生成控制节点 Join 命令。
- 将产物写入当前新任务的受控远端目录，再由现有输出收集机制下载。
- 不把 Token 写入普通日志、事件或错误消息；产物目录权限保持 `0700/0600`。

除明确声明 `outputs` 的步骤外，不允许在前置验证通过后运行恢复脚本。

### 5.6 任务恢复边界

- v0.3.2 不在 Java 进程重启后自动继续旧线程；旧任务仍先转为 `interrupted`，用户确认后创建续跑任务。
- 续跑不允许客户端选择任意起始步骤，防止绕过依赖；所有步骤都进入计划并由验证结果决定跳过。
- 成功任务不提供续跑入口；重新安装必须通过独立的重装/升级需求设计。
- 重置任务暂不使用安装续跑接口，保持独立的破坏性确认流程。

## 6. 本地 YUM 仓库 HTTP 访问权限修复

### 6.1 安装处理

`10-setup-yum-source.sh` 在解压完成后执行以下非交互操作：

1. 校验 `/var/www/html/repo/repodata/repomd.xml` 存在且为普通文件。
2. 确认 httpd 运行账户；RHEL 系默认账户为 `apache`，实际账户无法确认时安全失败。
3. 优先使用 POSIX ACL，仅向 httpd 账户授予 `/var/www`、`/var/www/html` 的目录遍历权限，以及仓库目录的只读和遍历权限。
4. ACL 工具不可用时不直接放宽整个 `/var/www`，而是输出明确依赖错误；离线 YUM 介质需包含 `acl` 包。
5. 使用 `semanage fcontext` 为仓库路径登记 `httpd_sys_content_t`，再执行 `restorecon -RF`；SELinux 工具不可用时至少执行 `restorecon` 并验证实际标签。
6. 启动 httpd 后，使用 `curl --fail --silent --show-error --max-time 10` 请求本机仓库元数据。

不得通过关闭 SELinux、把目录递归设为 `777` 或改变非仓库内容所有权来修复 403。

### 6.2 验证要求

`verify-10-setup-yum-source.sh` 改为目标节点本地验证，并返回统一验证退出码：

- httpd 为 active 且 enabled。
- 仓库元数据文件存在。
- 从 httpd 运行账户视角可遍历父目录并读取元数据。
- `http://127.0.0.1/repo/repodata/repomd.xml` 返回 HTTP 200。
- `yum --disablerepo='*' --enablerepo='k8s-yum' makecache` 成功。

`verify-12-setup-k8s-repo.sh` 在每个非主 Kubernetes 节点本地验证：

- `/etc/yum.repos.d/k8s-http.repo` 是 KubeFoundry 管理的配置。
- 请求 `http://<主控制节点>/repo/repodata/repomd.xml` 返回 200。
- 仅启用目标仓库执行 `yum makecache` 成功。

验收至少覆盖仓库节点本机和一个远程节点，并确认 httpd error log 不再出现路径搜索权限错误。

## 7. 安装进度部署单元分组

### 7.1 分组定义

安装步骤通过计划元数据显式归组，不按步骤编号或中文名称推断。建议初始部署单元如下：

| `stage_key` | 名称 | 包含内容 |
| --- | --- | --- |
| `host_preparation` | 主机与软件源准备 | YUM、主机名、Repo、依赖、环境、containerd |
| `registry` | 部署镜像仓库 | Registry 安装与验证 |
| `kubernetes` | 部署 Kubernetes 集群 | 初始化、证书、节点加入、CNI、CoreDNS、健康检查 |
| `component_prerequisite` | Kubemate 公共准备 | Helm、命名空间 |
| `nfs` | 部署 NFS 组件 | exports、Provisioner、Worker 挂载 |
| `kubemate` | 部署 Kubemate 管理组件 | Kubemate UI |
| `traefik` | 部署 Traefik 网关 | Traefik |
| `storage_observability` | 部署存储与日志套件 | Worker 目录、OpenEBS、MinIO、Loki、Alloy |
| `prometheus` | 部署 Prometheus 监控 | Worker 目录、Prometheus |
| `redis_sentinel` | 部署 Redis Sentinel | Redis Sentinel Helm 部署 |
| `etcd_backup` | 配置并验证 etcd 备份 | 最终备份单元 |

未启用的组件组不进入计划，也不展示空部署单元。

### 7.2 API 与状态计算

安装计划和任务步骤响应增加 `step_key`、`stage_key`、`stage_name`、`stage_order` 和 `step_order_in_stage`。任务步骤元数据在任务创建时持久化，历史页面不依赖当前版本计划重新计算。

部署单元状态由前端按服务端返回的稳定字段汇总：

- 任一步骤 `failed/interrupted`：单元失败。
- 否则任一步骤 `running`：单元执行中。
- 否则任一步骤 `pending`：单元等待执行。
- 全部为验证通过跳过：单元显示“已验证并跳过”。
- 成功与验证跳过混合：单元成功，并显示已跳过数量。
- 全部因依赖失败跳过：单元显示“已阻塞”。

页面默认只展开当前执行或首个失败单元；已完成单元折叠，用户可查看内部步骤和节点日志。整体进度仍按叶子步骤计算，避免分组后改变完成百分比。

## 8. MinIO 资源参数配置

`storage_observability` 组增加以下强类型字段，默认值与当前离线 Tenant 清单一致：

| 字段 | 默认值 | 校验 |
| --- | --- | --- |
| `minio_pvc_size` | `10Gi` | 正 Kubernetes 存储容量，不允许 `0` |
| `minio_cpu_request` | `250m` | 正 Kubernetes CPU Quantity |
| `minio_cpu_limit` | `2` | 不小于 request |
| `minio_memory_request` | `512Mi` | 正 Kubernetes Memory Quantity |
| `minio_memory_limit` | `4Gi` | 不小于 request |

后端使用强类型校验并拒绝未知字段，不把任意 JSON 或 Shell 片段透传给脚本。前端在 MinIO 子配置区提供 PVC、CPU request/limit、内存 request/limit 输入框，展示单位示例和字段级错误；后端仍执行最终校验。

### 8.1 工作节点数量门禁

MinIO 使用当前四节点 Tenant 拓扑，因此安装条件固定为工作节点数大于等于 4。这里的“工作节点”是当前集群配置内 `is_draft=false` 且角色包含 `worker` 的正式节点，不把仅有 `control_plane` 或 `registry` 角色的节点计入数量。

采用安装开始时的统一准入校验：

1. Kubemate 组件页面负责 MinIO 参数编辑和保存，不根据 Worker 数量禁用组件开关，也不因 Worker 数量阻止保存。
2. 创建安装或组件补装任务时，按本次安装快照中的集群配置统计正式 Worker 数量；MinIO 已启用且数量不足 4 个时，不创建执行任务，不运行任何安装步骤。
3. 准入失败返回 `409 MINIO_WORKER_COUNT_INSUFFICIENT`，`details` 包含 `required_workers=4` 和 `actual_workers=N`。

不增加“至少 4 个 Worker 为 Ready”或“至少 4 个 Worker 可调度”的专项预检。安装过程继续使用现有通用就绪验证检查 MinIO Tenant、Pod 和 PVC；若实际集群资源或节点状态导致工作负载无法就绪，则由 MinIO 安装步骤按通用超时和诊断规则失败，而不是由 Worker Ready 数量门禁提前拒绝。

当前组件模型中 MinIO 固定属于 `storage_observability` 组，因此开启该组即视为启用 MinIO。若后续拆分独立 MinIO 开关，同一门禁应迁移到 MinIO 开关，不得继续无条件限制组内其他组件。

已启用 MinIO 后如果删除或修改节点导致 Worker 少于 4 个，不自动关闭或丢弃已有配置；下次开始安装或组件补装时拒绝继续，直到集群配置恢复至少 4 个正式 Worker。

### 8.2 参数传递与渲染

配置随安装快照冻结，并通过白名单环境变量传入远端：

```text
KF_MINIO_PVC_SIZE
KF_MINIO_CPU_REQUEST
KF_MINIO_CPU_LIMIT
KF_MINIO_MEMORY_REQUEST
KF_MINIO_MEMORY_LIMIT
```

安装脚本在任务工作目录复制 Tenant 模板后使用 `yq` 精确更新对应字段，不修改离线介质原文件，不使用未转义的 `sed` 拼接 YAML。渲染后的清单进入任务留痕但不得包含 MinIO 凭据。后置验证按快照期望值核对 Tenant CR、PVC 请求和 Pod resources，避免仅检查 Pod Running 就误判配置已生效。

已安装 MinIO 的资源调整不在 v0.3.2 范围；组件状态为 `installed/installing` 时继续只读。

## 9. etcd 备份最终单元

### 9.1 计划位置

`etcd_backup` 是完整安装计划的最后一个部署单元，在所有启用组件组结束后执行。即使没有启用 Kubemate 组件，也应在 Kubernetes 健康检查之后执行。

该单元属于 `MAINTENANCE`，每次普通安装或续跑到达末尾时都执行一次，不因旧备份存在而直接跳过。

### 9.2 非交互实现

废弃现有脚本中的 `crontab -e`。新脚本完成：

1. 在主控制节点安装 KubeFoundry 管理的 etcd 备份脚本。
2. 创建带明确 KubeFoundry 标记的 systemd service 和 timer，使用原子写入和固定权限。
3. 立即执行一次备份，而不是等待下一次定时触发。
4. 使用当前静态 Pod etcd 证书执行 `etcdctl snapshot save`。
5. 对生成快照执行完整性检查，成功后再原子移动到最终文件名。
6. 按保留数量清理旧的、且名称符合 KubeFoundry 规则的备份文件。

默认路径和保留数量在进入开发前由配置评审冻结；不得把备份写入 etcd 数据目录本身。验证必须检查 service/timer、最近一次执行结果、快照新鲜度和快照完整性。

## 10. 安装确认页显示节点 IP

`InstallConfirmView` 的节点清单改为展示：

```text
主机名 | IPv4 | 节点角色 | 免密验证状态
```

IP 为空或格式非法时不得进入安装确认状态；后端安装准入仍以节点实体和安装快照为准。桌面端使用列式布局，窄屏允许换行但不得隐藏 IP。镜像仓库摘要继续展示主机名与 IP，不替代节点清单中的逐项显示。

## 11. 重置流程优化

### 11.1 支持安装失败后的重置

重置准入从“仅安装成功并锁定”调整为：

- 集群存在可用的安装快照。
- 最近安装任务为 `success`、`failed` 或 `interrupted`。
- 当前不存在活动安装、组件安装、续跑或重置任务。
- 用户完成现有破坏性确认。
- 当前节点身份与安装快照一致。

安装第二阶段失败时，仍可利用任务提交时保存的快照执行清理。

### 11.2 Helm 非强制前置

组件清理是否加入重置计划，不再仅依据“组件配置已启用”，而是依据来源安装任务中已成功进入的组件步骤和组件实际状态。

- 从未成功执行 Helm 安装步骤：不创建 Helm 清理任务。
- Helm 已安装但没有受管组件：跳过 Helm release 清理。
- 存在已验证的受管 Helm release：执行当前带所有权校验的卸载逻辑。
- `helm` 缺失且没有证据表明受管 Helm release 已创建：记录安全跳过，不阻断节点重置。
- 有受管 release 证据但 `helm` 缺失：明确失败，不能假装组件已清理；后续可提供受控临时 Helm 工具，但不在线下载。

因此，第二阶段失败且尚未安装 Helm 的集群会直接进入节点级清理，不再把“需要 Helm”作为第一个任务。

### 11.3 清理 KubeFoundry 参数配置

建立“所有权优先”的清理清单：

| 类型 | v0.3.2 安装方式 | 重置方式 |
| --- | --- | --- |
| `/etc/hosts`、`/etc/fstab`、`/etc/exports` | 唯一成对标记块 | 验证标记完整后仅删除标记块 |
| YUM repo 文件 | 独立文件并带 KubeFoundry 头标记 | 校验标记后删除，刷新缓存 |
| sysctl 参数 | `/etc/sysctl.d/99-kubefoundry-k8s.conf` | 删除独立文件并执行 `sysctl --system` |
| 内核模块 | `/etc/modules-load.d/kubefoundry-k8s.conf` | 删除独立文件；不强制卸载仍被使用的模块 |
| limits 参数 | `/etc/security/limits.d/99-kubefoundry.conf` | 删除独立文件 |
| kubelet 参数 | KubeFoundry 标记块或独立 drop-in | 删除受管内容 |
| containerd Registry 配置 | 仅写入目标 Registry 的受管目录 | 删除与快照 Registry 精确匹配的目录 |
| etcd 备份 unit、timer 和脚本 | 固定名称并带 KubeFoundry 标记 | 停止、禁用并删除受管文件 |
| NFS 配置 | 现有受管标记块 | 先卸载，再删除标记块 |

现有 `15-environment-config.sh` 直接修改 `/etc/sysctl.conf`、共享 `99-sysctl.conf`、`limits.conf` 和 `resolv.conf`，无法可靠区分用户原值。v0.3.2 实施时必须改为独立 drop-in 或标记块；不得在重置时按参数名称盲删用户配置。

对于无法迁移成独立文件且必须替换的配置，安装前在每个节点创建受权限保护的基线备份和清单，记录原文件 SHA-256、安装后 SHA-256 和备份路径。重置时仅在当前文件仍匹配受管版本时恢复原文件；检测到用户后续修改则安全失败并给出冲突文件，不覆盖用户改动。

重置验证脚本补充上述配置无残留检查。软件包卸载、恢复防火墙原状态、恢复用户 DNS 和删除非 KubeFoundry 容器不属于本需求，除非安装基线能够证明其原始状态并在后续评审中明确纳入。

## 12. Redis Sentinel 离线部署

### 12.1 Chart 与介质

使用需求指定的 [Bitnami Redis Helm Chart](https://artifacthub.io/packages/helm/bitnami/redis)，采用：

```yaml
architecture: replication
sentinel:
  enabled: true
```

实施时冻结 Chart 版本，不在目标环境访问在线 Helm 仓库。离线目录统一为：

```text
kube-media/03.setup_file/v1.30.14/helmapp/redis/
  redis-<version>.tgz
  values-sentinel.yaml
  images.txt
  SHA256SUMS
  README.md
```

当前目录中的旧 `redis-ha` Chart 不作为新方案依据。开发阶段需先完成来源、许可证、目标 Kubernetes 版本、CPU 架构和全部镜像的准入审查，再决定是归档还是移除旧文件；不得静默混用两套 Chart。

### 12.2 安装计划

- 将 `redis_sentinel` 组件组标记为可用。
- `ComponentMediaService` 增加 Redis 介质映射和目录 SHA-256。
- `ComponentPlanFactory` 增加 `43-install-redis-sentinel`，归入 `redis_sentinel` 部署单元。
- 安装使用 `helm upgrade --install --atomic --wait --timeout`，release 和 namespace 使用固定名称。
- 镜像必须全部指向离线 Registry，安装前逐一验证 Registry 中存在。
- Redis 密码使用受管 Secret；首次创建后续用，禁止在命令行、日志、事件或普通配置响应中回显。
- 持久化必须使用明确的 StorageClass；没有可用 StorageClass 时预检查失败，不临时创建不受管理的本地 PV。

后置验证至少包括 Helm release、Redis Pod Ready、Sentinel 数量与 quorum、当前 master 可识别、复制链路正常、PVC 全部 Bound，并执行一次不输出密码的最小读写与故障切换验收。

## 13. 接口变化摘要

| 接口 | 变化 |
| --- | --- |
| `POST /api/clusters/{clusterId}/jobs/{jobId}/resume` | 新增续跑任务 |
| `GET /api/jobs/{jobId}` | 增加 `source_job_id`、`run_mode` |
| `GET /api/jobs/{jobId}/steps` | 增加步骤键和部署单元字段 |
| `GET /api/clusters/{clusterId}/install-plan` | 增加步骤键、部署单元及组内顺序 |
| `GET/PUT /api/clusters/{clusterId}/components` | `storage_observability.config` 增加 MinIO 资源字段；保存时不校验 Worker 数量 |

续跑成功返回 `202 Accepted`。同步准入错误码冻结如下：

| HTTP | 错误码 | 场景 |
| --- | --- | --- |
| 404 | `CLUSTER_NOT_FOUND` / `JOB_NOT_FOUND` | 集群或来源任务不存在 |
| 409 | `INSTALLER_JOB_ACTIVE` | 同一集群存在活动安装、组件安装、预检或重置任务 |
| 409 | `RESUME_SOURCE_NOT_SUPPORTED` | 来源跨集群、类型不支持或状态不是 `failed/interrupted/partial_success` |
| 409 | `RESUME_SNAPSHOT_MISMATCH` | 快照缺失/历史不兼容、配置或节点漂移、计划/目标节点不一致、介质校验信息不完整 |

稳定状态原因码新增：

```text
PREVERIFY_SATISFIED
PREVERIFY_NOT_SATISFIED
PREVERIFY_ERROR
PREVERIFY_TIMEOUT
POSTVERIFY_FAILED
STEP_RESOURCE_UNAVAILABLE
RESUME_SOURCE_NOT_SUPPORTED
RESUME_SNAPSHOT_MISMATCH
MINIO_WORKER_COUNT_INSUFFICIENT
```

异步任务内错误记录在步骤和节点结果中；只有请求准入失败才返回同步 HTTP 4xx。

## 14. 测试与验收

### 14.1 Java

- 正常安装、失败、服务中断和部分成功任务创建续跑任务。
- 成功任务、跨集群任务、活动任务和无快照历史任务拒绝续跑。
- 来源快照被复用且新任务 ID、日志、事件与旧任务隔离。
- 前置验证退出码 `0/10/20/21` 分支及后置验证失败分支。
- 多节点步骤部分跳过、部分执行的步骤汇总。
- 初始化步骤跳过后 Join 产物安全恢复。
- 缺少验证脚本、验证脚本为符号链接或 CRLF 时计划/发布校验失败。
- 部署单元元数据持久化和历史任务兼容迁移。
- MinIO Quantity、request/limit 关系、未知字段和快照环境变量测试。
- MinIO 参数保存不受 Worker 数量限制；安装开始时，0～3 个正式 Worker 返回稳定错误，4 个及以上允许进入安装。
- 已启用后 Worker 数降至 3 个时，下次安装或组件补装准入拒绝执行且不静默修改配置。
- 第二阶段失败、无 Helm、有 Helm release 证据三类重置计划测试。

### 14.2 Vue

- 失败任务显示续跑入口，成功任务不显示。
- 接受续跑后跳转新任务 ID，原任务仍可查看。
- 部署单元默认折叠、当前/失败自动展开、内部步骤状态与进度正确。
- `PREVERIFY_SATISFIED` 显示“已验证并跳过”，不与依赖阻塞混淆。
- MinIO 配置默认值、单位校验、只读锁定和后端错误回填。
- MinIO 参数保存、安装开始时工作节点不足提示和后端准入校验。
- 安装确认页桌面和窄屏均显示节点 IP。

### 14.3 Bash 与真实环境

- 每个安装步骤验证脚本连续执行两次，结论一致且不修改系统。
- 镜像仓库已安装时前置验证通过，续跑不上传或执行 Registry 安装介质。
- 模拟 Kubernetes API 不可达，验证必须返回异常而不是触发重复初始化。
- YUM 仓库本机及远程节点访问元数据返回 200；SELinux Enforcing 下通过。
- etcd 立即备份生成可校验快照，timer 生效，重置后无受管 unit 残留。
- 第二阶段失败且没有 Helm 时可完成重置。
- 用户修改过的共享配置不会被重置脚本静默覆盖。
- Redis 在断网环境完成安装、Sentinel quorum 验证和受控故障切换。
- MinIO 配置值真实反映在 Tenant、PVC 和 Pod resources 中。
- 恰好 4 个正式 Worker 时允许开始 MinIO 安装；不因 Ready Worker 数量单独拒绝安装，实际工作负载仍必须通过 Tenant、Pod 和 PVC 通用就绪验证。

## 15. 实施顺序

### M1：失败续跑与验证状态机（需求 3.9）

- 数据库任务血缘和步骤元数据迁移。
- 验证脚本契约、计划完整性检查和 RemoteStepRunner 双重验证。
- Install/Component Install 续跑服务与接口。
- Join 产物恢复、状态原因、前端入口和自动化测试。

### M2：YUM 仓库权限（需求 3.4）

- ACL、SELinux 和 HTTP 200 修复。
- 重写对应验证脚本并完成远程节点真实验收。

### M3：安装展示与配置体验

- 部署单元分组。
- 安装确认页节点 IP。
- MinIO 资源参数配置。

### M4：重置可靠性

- 失败安装重置准入。
- Helm 条件清理。
- KubeFoundry 配置所有权、基线备份和重置验证。

### M5：新增部署单元

- Redis Sentinel 离线介质、安装和验证。
- etcd 备份最终单元、立即备份、定时执行和重置清理。

## 16. 风险与控制

| 风险 | 影响 | 控制措施 |
| --- | --- | --- |
| 验证异常被当成未安装 | 重复执行 kubeadm、Helm 等破坏性操作 | 使用独立退出码，只有 `10` 允许进入安装 |
| 前置验证跳过产物步骤 | 下游缺少 Join 命令等任务产物 | 显式 `skipPreparationScript`，仅恢复声明产物 |
| 续跑使用当前配置 | 新旧任务目标不一致 | 强制复用来源快照并校验节点身份 |
| 续跑覆盖历史记录 | 审计链断裂 | 新任务 ID 和 `source_job_id`，旧任务只读 |
| 验证脚本嵌套 SSH | 目标错误、凭据扩散、结果难归属 | 验证只在当前目标节点本地执行 |
| 重置误删用户配置 | 节点网络或系统参数损坏 | 独立 drop-in、标记块、校验和及冲突时安全失败 |
| 无 Helm 时组件残留 | 重置结果不完整 | 依据成功步骤证据生成计划；有 release 证据而缺 Helm 时明确失败 |
| YUM 权限过度放宽 | 暴露 `/var/www` 其他内容 | 仅为 httpd 账户设置路径 ACL，保持 SELinux Enforcing |
| Redis Chart 与旧介质混用 | 镜像、参数和升级行为不可预测 | 固定 Bitnami Chart、介质清单和 SHA-256，旧 Chart 单独处置 |
| etcd 备份不可恢复 | 产生虚假安全感 | 安装后立即备份并执行快照完整性检查 |

## 17. 待评审决策

1. etcd 备份目录、执行周期和默认保留数量。
2. Redis Sentinel 的固定 Chart 版本、Pod 数量、StorageClass 和密码交付方式。
3. v0.3.1 已安装集群缺少配置基线备份时，重置允许清理到何种边界。
4. 历史 v0.3.1 失败任务是否完全禁止续跑，还是提供一次只读迁移工具生成 v0.3.2 快照。
5. MinIO 默认资源值是否继续采用当前清单的 `10Gi/250m/2/512Mi/4Gi`；安装开始时至少 4 个正式工作节点的准入规则已经确定，不再作为待评审项。

## 18. 完成定义

- 九项需求均有实现、自动化测试、中文接口说明和验收记录。
- 失败任务可以创建新任务安全续跑，已满足步骤不会重复安装，验证异常不会触发安装。
- 每个安装步骤执行前后都有符合统一契约的验证，验证脚本覆盖率为 100%。
- YUM 仓库在 SELinux Enforcing 环境中通过本机与远程 HTTP 200 验收。
- 安装进度按部署单元展示，状态与叶子步骤一致。
- MinIO PVC、CPU 和内存配置经过前后端校验并真实应用。
- MinIO 少于 4 个正式工作节点时无法开始安装；不设置 Ready Worker 数量门禁，实际部署仍需通过通用就绪验证。
- etcd 备份是完整安装计划最后一个单元，并产生经过完整性验证的快照。
- 安装确认节点清单展示 IP。
- 安装失败且未安装 Helm 时仍可安全重置；重置不遗留 KubeFoundry 受管参数配置，也不覆盖用户改动。
- Redis Sentinel 使用冻结的 Bitnami Chart 和完整离线介质完成断网部署及故障切换验收。
- 所有新增文本文件使用 LF，敏感信息检查、Java/Vue/Bash 测试和发布包检查全部通过。
