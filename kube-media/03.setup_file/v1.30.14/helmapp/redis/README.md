# Redis Sentinel 离线安装介质

使用 Bitnami Chart `28.0.12` 和 Redis、Sentinel `8.10.1` 镜像标签。安装不执行本地 SHA-256 或 Registry 镜像预检查，由 Kubernetes 拉取镜像并检查工作负载状态。

## 安装命名与存储

| 项目 | 配置 |
| --- | --- |
| Helm release | `redis` |
| StatefulSet | `redis-node` |
| Pod | `redis-node-0/1/2` |
| PVC | `redis-data-redis-node-0/1/2` |
| Service / 无头 Service | `redis` / `redis-headless` |
| 密码 Secret | `redis-auth` |
| Sentinel masterSet | `redis-master` |
| 默认 StorageClass | `localpath` |

`localpath` 是 OpenEBS 本地 hostpath 存储类，采用 `WaitForFirstConsumer` 延迟绑定，由 OpenEBS 安装步骤创建。Redis 不再自动选取集群默认存储类；缺少 `localpath` 时明确报错。需要明确指定其它存储类时可设置 `KF_REDIS_STORAGE_CLASS`。

验证脚本检查新命名的 release、StatefulSet、3 个 Pod、3 个 PVC、密码卷引用、Sentinel quorum 和 1 主 2 从复制拓扑；PVC 必须全部 Bound 且使用要求的存储类。

## 已有集群

旧安装的 Pod/PVC 和 NFS 数据卷不能通过改名直接迁移。安装脚本遇到旧 release 时停止，避免建立第二套 Redis；应先备份并迁移数据，或执行明确授权的重置再全新安装。重置逻辑兼容新旧 release，并保留原有所有权和快照校验保护。

集群内部的工具所有权标签保持原约定，不影响资源显示名称。
