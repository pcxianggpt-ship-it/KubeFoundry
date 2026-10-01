# 玫瑰园 job4 故障修复与验收

## 范围与原因

2026-10-01 登录玫瑰园网络管理节点 192.168.0.129（k8sc1），检查安装任务 job4 的步骤状态和全部节点日志。集群包含 k8sc1、k8sw1、k8sw2、k8sw3、k8sw4，Kubernetes 为 v1.30.14。

job4 有三个失败步骤；MinIO、Loki、Alloy 因 OpenEBS 失败被连带跳过。基础 Kubernetes、NFS、Kubemate、Traefik、etcd 备份步骤已成功。

| 步骤 | 实际原因 | 修复 |
| --- | --- | --- |
| OpenEBS | 现场 openebssc.yaml 已使用 /data/openesb-root，脚本却强制要求工作目录占位符 | 更新脚本，兼容占位符和显式路径，保留现场路径 |
| Prometheus | additional-scrape-configs.Secret.yaml 包含 managedFields、resourceVersion、uid 等服务端导出字段 | 备份后清理导出字段，服务端 dry-run 通过；本地对应介质已有清理结果 |
| Redis Sentinel | 现场 values 仍使用旧上游 digest；仓库只有 8.10.1 标签，两种旧 digest 请求均返回 404 | Redis、Sentinel 改用 8.10.1 标签并清空 digest；保留 kubefoundry-redis-node 和既有 PVC |

## 补装发现与处理

补装使用新任务 job5，避免修改历史任务记录或复用已变化介质的旧快照。

- 管理节点缺少 MinIO 安装需要的 yq，已安装仓库提供的 amd64 yq v4.48.2 到 /usr/local/bin/yq。
- local-hostpath 与 nfs-storage 同时标记为默认 StorageClass，会影响 Redis 的唯一默认类判断。已将现场 local-hostpath 默认标记设为 false，并同步修改本地模板，保持 nfs-storage 为唯一默认类。
- Redis 验证脚本写死 redis-node，而现场保留历史 StatefulSet 名称。改为通过 release 标签查找唯一 StatefulSet，兼容新旧资源名称，无需重命名或删除 PVC。
- Loki 启动阶段 memberlist Service 不发布未就绪地址，导致 DNS 成员发现等待。设置 memberlist.service.publishNotReadyAddresses=true，同步脚本并修正现场 Service。
- Prometheus 在 job5 中进一步报错 unrecognized condition: "create"：kubectl v1.30.14 不支持 wait --for=create。改为最多 30 次、每次间隔 2 秒查询 Alertmanager Service，再配置 publishNotReadyAddresses。修正脚本后重跑该步骤成功。
- Flannel 引用了不存在的 global-registry Secret，持续产生 FailedToRetrieveImagePullSecret 告警。现场使用匿名镜像仓库，已清理介质和 DaemonSet 中的无效引用；五节点 CNI 滚动更新成功。

job5 于北京时间 19:16:47 结束，状态 partial_success，保留了 Prometheus 修复前的失败记录。修正后重新创建 job6，Prometheus 等步骤通过 PREVERIFY_SATISFIED 验证；job6 于 19:17:31 成功。所有启用组件组最终均为 installed。

## 验收结果

| 项目 | 结果 |
| --- | --- |
| 五个节点 | 全部 Ready，Flannel 五副本就绪 |
| OpenEBS | 验证脚本退出 0，localpv provisioner 就绪 |
| MinIO | 验证退出 0，Tenant Initialized，四 Pod 就绪，四个 10Gi PVC Bound |
| Loki / Alloy | 验证均退出 0；Loki read、write、backend 均三副本就绪；Alloy 五节点就绪 |
| 日志功能 | Loki 写入返回 204，查询返回测试日志 |
| Prometheus / Alertmanager | 验证退出 0，Prometheus 2/2，Alertmanager 3/3，两个 100Gi PVC Bound |
| Metrics API | kubectl top nodes 返回五节点 CPU、内存指标 |
| Redis Sentinel | 验证退出 0，三 Pod 均 2/2 Running，三个 8Gi PVC Bound，quorum=2，一主两从 |
| Redis 功能 | 实际版本 8.10.1，临时测试键 SET/GET/DEL 通过；测试键已删除 |
| 组件状态 | nfs、kubemate、traefik、storage_observability、prometheus、redis_sentinel 全部 installed |

本地回归测试：test_phase3_storage_observability.sh、test_phase3_prometheus.sh、test_redis_sentinel.sh 均通过；新增覆盖显式存储路径、唯一默认类模板、Loki 启动配置、Alertmanager Service 延迟创建/始终缺失、新旧 Redis StatefulSet 名称。相关修改通过 git diff --check，保持 UTF-8 无 BOM、LF。

现场备份和验收日志位于 /root/app/data/repairs/job4-20261001/，包括原脚本/配置备份、prometheus-repair.log、accept.sh 和 accept.log。job4、job5 的历史日志保持原样；job6 的状态和日志由正常补装流程生成。本次未进行 Redis 故障切换演练，也未删除持久化数据。
