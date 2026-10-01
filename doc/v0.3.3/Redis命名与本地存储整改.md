# Redis 命名与本地存储整改

## 需求与实现

- 新安装的 Pod 使用 `redis-node-0/1/2`，PVC 使用 `redis-data-redis-node-0/1/2`。
- Helm release、密码 Secret 和 Sentinel masterSet 分别使用 `redis`、`redis-auth`、`redis-master`。
- 默认 StorageClass 改为 `localpath`，不再从集群默认类中自动选择 NFS。
- OpenEBS 额外的本地存储类模板由 `local-hostpath` 更名为 `localpath`，仍使用 `openebs.io/local` 供给器与 `WaitForFirstConsumer`。
- Redis verify 不再包含旧名称前缀；增加精确 Pod/PVC 命名检查和密码卷引用检查，保留副本、PVC 绑定、quorum 与复制拓扑验证。
- 同步真实验收脚本与重置逻辑。重置支持新旧 release，继续验证所有权标签和安装快照摘要。

## 使用边界

本次调整安装文件，不迁移已有 Redis 数据。服务器当前旧安装使用 NFS PVC；运行资源仍保持原名称。旧 release 存在时新安装脚本明确停止，避免重复部署。新命名及存储在后续全新安装时生效。

`localpath` 本地卷绑定到对应节点，不能当作 NFS 共享卷跨节点移动。显式设置 `KF_REDIS_STORAGE_CLASS` 时，安装与验证会使用该指定值。

## 验证与交付

执行 Redis、OpenEBS/存储组件与重置脚本回归，以及 Java ResetPlanFactory/RemoteStepRunner 回归。实际 Chart 渲染检查 StatefulSet 名称、PVC 模板、StorageClass、认证 Secret 和 Sentinel masterSet。

服务器文件同步前保存备份，不对现有 Redis 执行升级、卸载或 PVC 删除。本次未执行完整重置重装或 Sol 独立专项复核。

## 服务器结果

- 玫瑰园管理节点安装介质、安装脚本、verify、验收与重置脚本已同步，后端已更新且服务恢复正常，保留 300 秒就绪等待。
- `localpath` 存储类已创建，供给器为 `openebs.io/local`，绑定模式为 `WaitForFirstConsumer`，非默认类；保留原现场 BasePath 配置。
- 实际 Chart 渲染检查确认 `redis-node`、3 副本、`redis-data` PVC 模板、`localpath`、`redis-auth`。
- 新 Redis verify 在现有旧 release 上返回 10（需要安装新版本），没有把旧资源判断为整改完成；OpenEBS verify 通过。
- Java 27 项针对性测试通过，Redis、存储和重置脚本回归通过。现场 3 个旧 Redis Pod 为 2/2 Running，5 个节点 Ready，未迁移或删除旧 PVC。
- 原文件和后端备份位于 `/root/app/data/repairs/redis-localpath-20261001/`。
