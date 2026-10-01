# 安装就绪等待与 Redis 命名调整

## 就绪等待

安装工作负载的默认就绪等待由 180 秒延长至 300 秒（5 分钟）。Java 后端下发 `KF_VERIFY_ROLLOUT_TIMEOUT=300s`，独立验证脚本的默认值也统一为 300 秒；显式设置该环境变量时仍使用配置值。

后端单次校验总时限调整为 6 分钟，为 5 分钟就绪等待和附加 API 查询预留时间。Prometheus 校验输出正在等待的工作负载、等待时限和 rollout 状态，便于定位超时对象。

job10 的安装脚本执行成功，但后置校验于 20:13:58 超时；当时镜像拉取和排队接近 3 分钟，最后一个 Alertmanager 副本于 20:14:01 就绪。之后再次执行原校验脚本通过。

## Redis Pod 名称

Redis 介质使用 `fullnameOverride: redis`，新安装时 StatefulSet 为 `redis-node`，Pod 为 `redis-node-0`、`redis-node-1`、`redis-node-2`。服务器上的旧覆盖值 `kubefoundry-redis` 调整为 `redis`。

后续 Redis 整改将 Helm release、密码 Secret 与 Sentinel masterSet 改为 `redis`、`redis-auth`、`redis-master`，并使用 `localpath` 与严格的新名称验证；详见《Redis命名与本地存储整改》。工具内部所有权标签保持原约定。

本次修改安装文件，不对正在运行的旧 StatefulSet 执行改名或迁移。新名称在后续全新安装时生效；已有集群若要迁移名称，需处理对应 PVC 与数据，不应直接执行普通升级。

## 验证

- Prometheus 脚本回归验证默认 300 秒等待及安装顺序。
- Redis 脚本回归验证新旧 StatefulSet 名称兼容。
- Java RemoteStepRunner 回归验证下发 300 秒配置，且后端总时限大于就绪等待。
- 使用实际 Helm Chart 渲染新命名，确认 StatefulSet 与 Pod 命名规则。

## 服务器同步结果

修复文件已同步到玫瑰园管理节点 `192.168.0.129`。管理服务在确认无运行任务后更新并重启，接口恢复正常；后端安装运行时默认值为 `300s`。原文件与后端备份保存在 `/root/app/data/repairs/install-wait-redis-20261001/`。

Java RemoteStepRunner 20 项测试通过；Prometheus、Redis 与存储组件脚本回归通过。实际 Chart 渲染出的 StatefulSet 为 `redis-node`；服务器 Prometheus 与 Redis 校验均通过，5 个节点保持 Ready。本次未执行完整重置重装，也未执行 Sol 独立专项复核。
