# MinIO 真实环境部署与验证操作手册

## 1. 适用范围

本文用于 KubeFoundry v0.3.1 在隔离测试环境验证 MinIO 自动部署。当前实现使用以下固定资源：

- MinIO Operator：v5.0.14 对应的离线清单 `minio-operator.yaml`。
- MinIO 镜像：`quay.io/minio/minio:RELEASE.2024-03-05T04-48-44Z`。
- 对象存储清单：`minio-dev.yaml`，由安装脚本渲染实际 Worker、镜像和数据目录。
- 命名空间：`kubemate-system`。
- 数据目录：目标 Worker 的 `/data/minio-root`。
- 服务：`kubemate-minio-hl:9000`，供 Loki 使用。

当前版本部署单节点对象存储工作负载，不声明已实现 Tenant CR、动态 PVC 或生产高可用拓扑。

## 2. 安全边界

- 只允许在隔离测试集群执行。
- 测试前记录目标 Worker、磁盘和 `/data/minio-root` 现状。
- 不得把 Secret 内容、访问密钥、kubeconfig 或真实密码写入本文、Git、任务日志或验收附件。
- 未经单独确认，不得删除 PVC、PV、Secret、MinIO 数据目录或已有对象。
- 安装失败时保留现场，先采集脱敏诊断，不执行自动清理。

## 3. 环境信息

家庭网络验收服务器：

| 角色 | 地址 |
| --- | --- |
| 主控制节点 | `192.168.0.225` |
| Worker 1 | `192.168.0.160` |
| Worker 2 | `192.168.0.64` |

执行前确认三台服务器均已开机，管理机可以访问 SSH，并且 Kubernetes 集群节点为 `Ready`。

## 4. 离线介质检查

在主控制节点执行：

```bash
cd /root/app/kube-media/03.setup_file/v1.30.14/minio
test -s minio-operator.yaml
test -s minio-dev.yaml
sha256sum minio-operator.yaml minio-dev.yaml
```

验证私有仓库镜像：

```bash
curl --fail --silent --show-error --output /dev/null \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  http://registry:5000/v2/quay.io/minio/minio/manifests/RELEASE.2024-03-05T04-48-44Z
```

命令退出码必须为 `0`。将 SHA-256 记录到 Git 之外的验收证据目录。

## 5. 通过 KubeFoundry 安装

1. 在 Kubemate 组件配置中启用“存储与日志套件”。
2. 完成组件预检查。
3. 创建安装或组件补装任务，记录集群 ID 和任务 ID。
4. 在任务详情中确认执行顺序为：准备 Worker → OpenEBS → MinIO → Loki → Alloy。
5. MinIO 步骤必须等待 Operator、MinIO Pod 和 `kubemate-minio-hl` Service 就绪后才能成功。

## 6. Kubernetes 验证

```bash
kubectl get deployment,pod,service -n kubemate-system -o wide
kubectl rollout status deployment/minio-operator -n kubemate-system --timeout=10m
kubectl wait --for=condition=Ready pod/minio -n kubemate-system --timeout=10m
kubectl get service kubemate-minio-hl -n kubemate-system
kubectl get pod minio -n kubemate-system \
  -o jsonpath='{.spec.nodeName}{"\n"}{.spec.containers[*].image}{"\n"}'
```

预期结果：

- Operator Deployment 完成 rollout。
- `pod/minio` 为 Ready。
- MinIO 镜像版本与本文一致。
- MinIO 被调度到 Ready Worker，而不是固定旧节点名。
- `kubemate-minio-hl` 服务存在且暴露 9000 端口。

在 MinIO 所在 Worker 验证数据目录：

```bash
test -d /data/minio-root
findmnt --target /data/minio-root || true
df -h /data/minio-root
```

## 7. Loki 最小链路验证

```bash
kubectl get pod -n kubemate-system -o wide | grep loki
kubectl get service kubemate-minio-hl -n kubemate-system
helm status loki -n kubemate-system
kubectl logs -n kubemate-system -l app.kubernetes.io/name=loki \
  --tail=200 --prefix | grep -Ei 's3|minio|error|denied|timeout' || true
```

验收要求：Loki 安装成功且日志中没有持续出现对象存储认证失败、连接拒绝或 bucket 访问失败。

## 8. 幂等与故障验证

- 再次发起仅包含存储与日志套件的组件安装，确认 Operator 和 MinIO 工作负载可重复应用。
- 重试前后记录 MinIO Pod、Service、数据目录和已有对象状态。
- 临时移除测试介质副本或使用不存在的镜像标签验证快速失败；恢复后重新执行。
- 故障与重试过程中不得删除或替换持久化数据。
- MinIO 失败时，Loki/Alloy 应在本组内停止或失败，其他无依赖组件组继续执行。

## 9. 验收证据

证据存放于 Git 之外，至少包含：

- Git 提交、发布包 SHA-256、介质 SHA-256。
- 集群 ID、任务 ID、步骤状态和脱敏日志。
- Operator、Pod、Service、镜像和节点输出。
- Loki Helm 状态及脱敏对象存储诊断。
- 首装、重复执行和故障恢复结论。
- 执行人、复核人、日期和环境标识。
