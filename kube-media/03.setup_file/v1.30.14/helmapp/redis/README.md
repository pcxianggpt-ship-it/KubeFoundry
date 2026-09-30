# Redis Sentinel 离线介质

运行时固定使用 Bitnami Redis Chart `28.0.12`，应用版本为 Redis `8.10.1`。部署拓扑为一个 master、两个 replica，每个 Redis Pod 同置一个 Sentinel，Sentinel quorum 为 2。

资源名称固定为 StatefulSet `redis-node`、Pod `redis-node-0/1/2`、Service `redis` 和无头 Service `redis-headless`；Helm release 仍为 `kubefoundry-redis`，密码 Secret 仍为 `kubefoundry-redis-auth`。

旧命名 `kubefoundry-redis-node` 的已安装集群不能直接重命名 Pod。此配置会改变 StatefulSet 和 PVC 名称，升级前必须完成数据备份与迁移；不要把普通 Helm 升级当作原地重命名。既有真实环境验收记录保留当时的实际名称。

安装文件：

- `redis-28.0.12.tgz`：冻结的 Bitnami Redis Helm Chart，Apache-2.0 许可证。
- `values-sentinel.yaml`：KubeFoundry 离线部署参数。
- `images.txt`：供导入镜像时参考，安装不依赖此文件。
- `SHA256SUMS`：介质摘要记录，安装不依赖此文件，也不执行本地 SHA-256 校验。

所有运行时镜像均通过 `global.imageRegistry=registry:5000` 改写到私有仓库，Redis 与 Sentinel 均使用 `8.10.1` 版本标签，values 中显式清空 digest，安装时不再通过 Registry API 预检查镜像是否存在，由 Kubernetes 在实际拉取和 Helm 等待就绪时报告镜像错误。离线镜像经分架构导入或重新推送后，私有仓库的 manifest 摘要可能与上游多架构摘要不同；不得继续使用上游摘要作为本地拉取地址。私有仓库应保持此版本标签内容不变。当前配置只启用 Redis 与 Redis Sentinel 镜像；exporter、volume permissions、sysctl 和 kubectl 辅助镜像均显式关闭。

该版本要求 Kubernetes 1.23+ 和 Helm 3.8+，与目标 Kubernetes v1.30.14 兼容。离线仓库须为目标节点架构导入 Redis 与 Sentinel `8.10.1` 镜像；混合架构集群须让该标签包含 linux/amd64 和 linux/arm64 manifest。Redis 7.2.5 已存在官方披露的高危漏洞，因此不再作为本版本准入基线。

目录中历史遗留的 `redis-ha/`、`allyaml/` 和 `redis-sentinel-pvc/` 不属于 v0.3.2 运行时方案，安装脚本不会搜索或使用这些目录，避免两套 Chart 混用。
