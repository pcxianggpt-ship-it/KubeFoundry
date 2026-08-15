# MinIO 四节点真实环境部署与验证操作手册

## 1. 方案结论

KubeFoundry v0.3.1 使用 MinIO Operator v5.0.14 和 `minio.min.io/v2` Tenant CR，通过本地配置文件部署四节点分布式 MinIO，不再使用单 Pod `minio-dev.yaml`。

官方 `minio-dev.yaml` 是单节点、单磁盘的开发评估示例。四 Worker 环境采用 Operator Tenant：

- 1 个 Tenant：`kubemate-system/kubemate-minio`。
- 1 个 Pool，4 个 Server，每个 Server 1 个 PVC。
- 通过强制 Pod 反亲和分布到 4 个不同 Worker。
- PVC 使用 `openebs-hostpath`，测试容量每卷 `10Gi`。
- 每个 MinIO Server 容器请求 `250m CPU/512Mi`，限制为 `2 CPU/4Gi`。
- 固定镜像 `registry:5000/quay.io/minio/minio:RELEASE.2024-03-05T04-48-44Z`。
- Tenant 内部服务为 `kubemate-minio-hl:9000`，供 Loki 使用。
- MinIO 和 Loki 共用 `kubemate-minio-env` Secret；Loki 安装脚本自动读取，不在日志输出凭据。
- `tenant.env` 会按运维留痕要求原文保存在控制端任务证据和远程执行资源目录，目录仅允许运行账户或 root 访问。
- `requestAutoCert: false`，仅允许隔离内网验收；生产环境必须另行配置 TLS 和受控入口。

参考资料：

- [MinIO Kubernetes 单节点评估示例](https://www.minio.org.cn/docs/minio/kubernetes/upstream/index.html)
- [MinIO Operator v5.0.14 Tenant 配置示例](https://github.com/minio/operator/tree/v5.0.14/examples/kustomization/base)
- [MinIO Tenant CRD 字段说明](https://min.io/docs/minio/kubernetes/upstream/reference/operator-crd.html)

## 2. 配置文件

MinIO 安装文件直接归档在仓库的 `kube-media/03.setup_file/v1.30.14/minio/`，部署到服务器后离线介质目录必须包含以下文件：

```text
/root/app/kube-media/03.setup_file/v1.30.14/minio/
├── minio-operator.yaml
├── kustomization.yaml
├── tenant.yaml
└── tenant.env
```

其中：

- `kustomization.yaml`：生成固定名称的 Secret 并应用 Tenant。
- `tenant.yaml`：四 Server 拓扑、OpenEBS PVC、CPU/内存资源、反亲和和非 root 安全上下文。
- `tenant.env`：现场实际凭据文件，被 Git 忽略，但正式安装和组件补装前必须存在。
- 发布包同时提供 `/root/app/templates/minio/tenant.env.example` 作为凭据模板，不能直接用于安装。

创建实际凭据文件：

```bash
install -m 600 /root/app/templates/minio/tenant.env.example \
  /root/app/kube-media/03.setup_file/v1.30.14/minio/tenant.env
```

使用编辑器修改 `tenant.env`，将两个 `CHANGE_ME_` 值替换为真实随机凭据。值仅允许字母、数字、点、下划线和连字符，不得把真实值提交 Git：

```text
export MINIO_ROOT_USER="实际用户名"
export MINIO_ROOT_PASSWORD="实际高强度密码"
export MINIO_STORAGE_CLASS_STANDARD="EC:2"
export MINIO_BROWSER="on"
```

确认文件权限和占位符：

```bash
chmod 600 /root/app/kube-media/03.setup_file/v1.30.14/minio/tenant.env
! grep -q 'CHANGE_ME_' /root/app/kube-media/03.setup_file/v1.30.14/minio/tenant.env
```

## 3. 部署前检查

```bash
kubectl get nodes
kubectl get storageclass openebs-hostpath
kubectl get crd tenants.minio.min.io || true
test -s /root/app/kube-media/03.setup_file/v1.30.14/minio/minio-operator.yaml
test -s /root/app/kube-media/03.setup_file/v1.30.14/minio/kustomization.yaml
test -s /root/app/kube-media/03.setup_file/v1.30.14/minio/tenant.yaml
test -s /root/app/kube-media/03.setup_file/v1.30.14/minio/tenant.env
```

要求：

- 至少 4 个 Ready Worker。
- `openebs-hostpath` 存在。
- 每个 Worker 的实际可用空间大于测试计划写入量。
- Operator 和 MinIO 镜像在私有仓库可读取。
- `tenant.env` 不包含占位符，权限为 `600`。

### 3.1 磁盘容量和宿主机路径

`volumeClaimTemplate.spec.resources.requests.storage` 是必要配置，当前值 `10Gi` 只用于家庭网络验收。生产环境必须结合数据保留周期、写入增长、纠删码冗余和扩容余量重新确定每卷容量，不能直接沿用测试值。

OpenEBS HostPath 的实际根目录为 `${Kubernetes 工作目录}/openebs-root`。安装脚本通过 `KF_K8S_HOME` 渲染 StorageClass 和 Helm values；例如 Kubernetes 工作目录为 `/data/k8s_install` 时，实际根目录为 `/data/k8s_install/openebs-root`。

注意：HostPath PVC 的 `storage: 10Gi` 不是独立磁盘配额，不能替代宿主机容量监控。生产环境应优先使用独立磁盘或生产级 CSI，并保证每个 Worker 的文件系统可用空间高于计划数据量和安全余量。

### 3.2 CPU 和内存

当前四节点验收基线为每个 Server：

```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: "2"
    memory: 4Gi
```

该配置用于资源有限的验证环境。生产环境需要根据并发、对象大小、纠删码、TLS 和监控开销压测后调整，尤其不能在发生 OOM 时只依赖自动重启。

### 3.3 KES 镜像结论

当前 `tenant.yaml` 没有配置 `spec.kes`，Operator 清单和 Tenant 清单也没有引用 `minio/kes` 镜像，因此本安装过程不会拉取或启动 KES。

KES（Key Encryption Service）是 MinIO 对接外部 KMS 的密钥服务，用于 SSE-S3/SSE-KMS 和后端元数据加密。只有需要服务端加密并完成外部 KMS、mTLS 证书、密钥策略及 KES 高可用设计时，才应在 Tenant 中配置 `spec.kes` 和对应镜像；当前 Loki 对象存储验收不需要 KES。

参考：[MinIO Operator 字段说明](https://github.com/minio/operator/blob/v5.0.14/docs/operator-fields.md)、[MinIO 服务端加密说明](https://github.com/minio/minio/blob/master/docs/security/README.md)。

## 4. 通过 KubeFoundry 安装

在组件配置中启用“存储与日志套件”，发起组件补装。安装顺序为：

```text
准备 Worker → OpenEBS → MinIO Operator/Tenant → Loki → Alloy
```

MinIO 脚本执行以下固定步骤：

1. 校验四个介质配置文件和私有仓库镜像。
2. 应用 Operator v5.0.14 并等待 CRD 和 Deployment 就绪。
3. 选择前 4 个 Ready Worker，设置 `kubefoundry.io/minio=true` 标签。
4. 执行 `kubectl apply -k <MinIO资源目录>`。
5. 等待 Tenant `Initialized`、4 个 Pod Ready、4 个 PVC Bound 和内部 Service 可用。
6. Loki 从 `kubemate-minio-env` Secret 读取同一份 S3 凭据。

也可以在排障时手工应用配置：

```bash
cd /root/app/kube-media/03.setup_file/v1.30.14/minio
kubectl apply -f minio-operator.yaml
kubectl rollout status deployment/minio-operator -n kubemate-system --timeout=5m
kubectl label node k8sw1 k8sw2 k8sw3 k8sw4 kubefoundry.io/minio=true --overwrite
kubectl apply -k .
```

## 5. MinIO 验收

```bash
kubectl get tenant kubemate-minio -n kubemate-system
kubectl get pods -n kubemate-system -l v1.min.io/tenant=kubemate-minio -o wide
kubectl get pvc -n kubemate-system -l v1.min.io/tenant=kubemate-minio
kubectl get service kubemate-minio-hl -n kubemate-system
kubectl get secret kubemate-minio-env -n kubemate-system \
  -o jsonpath='{.metadata.name}{"\n"}'
```

通过标准：

- Tenant `currentState` 为 `Initialized`。
- 4 个 MinIO Pod 全部 Ready，并分布在 4 个不同 Worker。
- 4 个 PVC 全部为 Bound，StorageClass 为 `openebs-hostpath`。
- `kubemate-minio-hl:9000` 可从集群内解析和访问。
- MinIO Pod 使用固定版本私有仓库镜像，并以非 root 用户运行。
- 验收输出不包含 Secret 解码值。
- 控制端 `data/jobs/<任务ID>/evidence/49-install-minio/<节点>/` 包含脚本、完整资源、日志、结果和 `checksums.sha256`。
- 远程 `/tmp/kubefoundry/jobs/<任务ID>/resources/storage_observability/49-install-minio/` 在步骤结束后仍存在。

## 6. Loki 和 Alloy 链路验收

```bash
helm status loki -n kubemate-system
kubectl get pod -n kubemate-system -o wide | grep -E 'loki|alloy'
kubectl logs -n kubemate-system -l app.kubernetes.io/name=loki \
  --since=10m --prefix | grep -Ei 'access.?denied|signature|credential|timeout' || true
```

通过标准：

- Loki Helm Release 为 `deployed`。
- Loki read/write/backend 和 Canary Ready。
- Alloy 在 5 个 Kubernetes 节点运行。
- 近期日志无持续 S3 认证、连接或 bucket 错误。

## 7. 幂等和故障恢复

再次发起“存储与日志套件”补装，确认：

- Operator、Tenant、Secret 和 Service 可重复应用。
- Tenant 不重复创建 PVC，不轮换凭据。
- MinIO 已有对象和 PVC 不被删除。
- Loki 和 Alloy保持可用。
- MinIO 失败只阻断存储与日志组，不阻断其他独立组件组。

故障注入只能在隔离验收环境执行。不得删除 Tenant、PVC、PV 或 Worker 数据目录。

## 8. 已知边界

- Operator v5.0.14 和 MinIO Server 版本已冻结，不自动跟随上游升级。
- OpenEBS HostPath 适用于本次验收，不等同于生产级独立磁盘或 CSI 存储。
- 当前测试关闭 Tenant 自动证书并只提供集群内部 Service。
- 生产发布前必须完成 TLS、网络入口、备份恢复、磁盘故障和容量规划专项验收。
