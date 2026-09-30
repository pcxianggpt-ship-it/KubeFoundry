# Redis Sentinel 离线介质

运行时固定使用 Bitnami Redis Chart `28.0.12`，应用版本为 Redis `8.10.1`。部署拓扑为一个 master、两个 replica，每个 Redis Pod 同置一个 Sentinel，Sentinel quorum 为 2。

安装文件：

- `redis-28.0.12.tgz`：冻结的 Bitnami Redis Helm Chart，Apache-2.0 许可证。
- `values-sentinel.yaml`：KubeFoundry 离线部署参数。
- `images.txt`：Chart 涉及的镜像以及当前配置下是否必须导入。
- `SHA256SUMS`：安装前校验的冻结介质摘要。

所有运行时镜像均通过 `global.imageRegistry=registry:5000` 改写到私有仓库，并使用多架构 OCI manifest 的 SHA-256 digest 固定内容。当前配置只启用 Redis 与 Redis Sentinel 镜像；exporter、volume permissions、sysctl 和 kubectl 辅助镜像均显式关闭。

该版本要求 Kubernetes 1.23+ 和 Helm 3.8+，与目标 Kubernetes v1.30.14 兼容。冻结的 Redis 与 Sentinel 镜像均包含 linux/amd64 和 linux/arm64 manifest。Redis 7.2.5 已存在官方披露的高危漏洞，因此不再作为本版本准入基线。

目录中历史遗留的 `redis-ha/`、`allyaml/` 和 `redis-sentinel-pvc/` 不属于 v0.3.2 运行时方案，安装脚本不会搜索或使用这些目录，避免两套 Chart 混用。
