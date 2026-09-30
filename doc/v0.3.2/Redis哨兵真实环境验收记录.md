# Redis 哨兵真实环境验收记录

## 1. 环境与范围

- 日期：2026-09-30，北京时间。
- 环境：amar 办公网，集群 `amar-v032-acceptance`，集群 ID 1。
- 节点：k8sc1（10.2.10.192）、k8sw1（10.2.10.102）、k8sw2（10.2.10.187）。
- Chart：Bitnami Redis 28.0.12；运行版本：Redis 8.10.1。
- Redis 摘要：`sha256:d75bda00b778ad5e03a639ec36e00f6665a5d7e0f35a6250be5b103fb2117275`。
- Sentinel 摘要：`sha256:fcfca07d8b56cea8e990e51c09c0d03102bde09a2147bd6a669e024a56893a8c`。
- 实际镜像路径：`registry:5000/bitnami/redis`、`registry:5000/bitnami/redis-sentinel`，按上述摘要拉取。

## 2. 执行结果

| 验收项 | 结果 | 证据 |
| --- | --- | --- |
| Web 组件补装 | 通过 | 任务 80，10:10:40 开始，10:15:03 成功；步骤 263、264 验证跳过，步骤 265 成功且退出码 0 |
| 工作负载与存储 | 通过 | `kubefoundry-redis-node-0/1/2` 全部 2/2 Running；3 个 PVC 全部 Bound，StorageClass 为 nfs-storage，各 8Gi |
| 版本与初始读写 | 通过 | redis-server 输出 v=8.10.1；SET 返回 OK，GET 返回写入值，DEL 返回 1 |
| 删除主 Pod 故障演练 | 通过 | `scripts/acceptance/redis-sentinel-failover.sh` 退出码 0；master 从 node-0 切换为 node-2；演练前数据仍可读取 |
| 切换后新读写 | 通过 | 新 master node-2 上 SET 返回 OK，GET 返回 v032-after，DEL 返回 1 |
| 切换后严格验证 | 通过 | 任务 80 工作目录的 verify.sh 退出码 0，确认 3 Pod、3 PVC、quorum=2、1 master/2 replica 及受管 Secret |
| 集群最终状态 | 通过 | `KF_EXPECT_MINIO=0` 执行只读集群验收，退出码 0；三个节点 Ready，API 就绪，Redis release 与 etcd 备份校验通过 |

测试键已删除；验证过程未输出 Redis 密码。故障演练只删除 Redis master Pod，StatefulSet 已恢复全部副本。

原始安装日志：管理节点 `/root/data/jobs/80/logs/43-install-redis-sentinel/k8sc1.log`。

远端验收脚本：`/root/app/redis-sentinel-failover-acceptance.sh`、`/root/app/v032-cluster-readiness-acceptance.sh`。

## 3. 观察与未完成事项

- k8sw2 安装中短暂 SSH 不通、kubelet 心跳停止并出现 Ready=Unknown，随后自行恢复。Redis 镜像拉取约 117 秒、Sentinel 约 45 秒；最终补装与故障切换均通过。
- 通用安装预检任务 79 检查到现有 Kubernetes 端口占用，未通过；它用于从零安装，不作为本次组件补装失败证据。
- 运行仓库已经补齐镜像，仍需重新制作独立离线仓库包以覆盖后续从零部署。
- 安装进度分组、安装确认节点 IP 页面动态验收，以及非实现者高风险复核尚未完成。本次没有独立 Sol 专项复核，不据此签署最终发布结论。
