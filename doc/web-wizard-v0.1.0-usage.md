# KubeFoundry Web Wizard v0.1.0 使用说明

## 后端启动

后端位于 `web/backend`，使用 Flask、SQLite 和 Python 标准库执行任务编排。

```bash
cd web/backend
python3 -m pip install -r requirements.txt
python3 app.py
```

默认服务地址：

```text
http://127.0.0.1:5000
```

数据库默认创建在：

```text
data/kubefoundry.db
```

可以用环境变量覆盖默认路径：

```bash
export KF_DB_PATH=/data/kubefoundry.db
export KF_WEB_HOST=0.0.0.0
export KF_WEB_PORT=5000
python3 app.py
```

最小验证：

```bash
curl http://127.0.0.1:5000/api/health
curl -X POST http://127.0.0.1:5000/api/init-db
python3 -m unittest discover -s tests -v
```

创建集群和节点示例：

```bash
curl -X POST http://127.0.0.1:5000/api/clusters \
  -H 'Content-Type: application/json' \
  -d '{"name":"k8s-cluster","k8s_version":"1.30.14","registry_ip":"192.168.123.130"}'

curl -X POST http://127.0.0.1:5000/api/clusters/1/nodes \
  -H 'Content-Type: application/json' \
  -d '{"hostname":"k8sc1","ip":"192.168.123.130","role":"control_plane"}'
```

## 前端启动

前端位于 `web/frontend`，使用 Vue 3、Vite 和 Element Plus。

```bash
cd web/frontend
npm install
npm run dev
```

默认开发地址：

```text
http://127.0.0.1:5173
```

Vite 会把 `/api` 请求代理到后端：

```text
http://127.0.0.1:5000
```

## 页面范围

v0.1.0 前端提供基础向导能力：

1. 集群基础配置
2. 节点配置
3. SSH 配置
4. 路径配置
5. 生态组件选择
6. 预检查任务
7. 配置 YAML 预览
8. 安装任务
9. 任务状态和 SSE 日志

安装执行页会展示步骤状态、节点状态和节点级完整日志。预检查页会按节点展示 CPU、内存、磁盘、Swap、端口等检查结果。

配置确认页可以直接预览当前 SQLite 配置生成的 `cluster.yaml`，也可以粘贴 YAML 覆盖当前集群配置。顶部“任务历史”可以重新打开历史预检查或安装任务，并查看步骤、节点状态和日志。

安装执行页会先展示实际执行的 Phase 2 步骤清单，点击执行后必须再次确认，避免误操作。

## Phase 2 安装范围

当前 Python 编排器已接入以下 Kubernetes 底座步骤：

```text
10-setup-yum-source
11b-setup-hostname
12-setup-k8s-repo
13-install-k8s-deps
14-replace-kubeadm
15-environment-config
16-install-containerd
17-install-registry
18-init-k8s-cluster
19-modify-cert-expiry
20-add-control-nodes
21-add-worker-nodes
22-install-cni-flannel
```

执行安装前，管理节点的安装介质目录至少需要包含：

```text
${install_media}/01.rpm_package/k8srepo_kylinos_sp3_${arch}.tar.gz
${install_media}/01.rpm_package/kubeadm-${k8s_version}-100y-${arch}
${install_media}/02.container_runtime/
${install_media}/03.setup_file/kube-flannel.yml
${install_media}/04.registry/
```

Python 会在任务启动前验证这些路径，并按步骤分发到目标节点。`18-init-k8s-cluster` 使用 `kubeadm token create --print-join-command` 和 `kubeadm init phase upload-certs` 生成控制节点及工作节点 join 命令，保存为任务产物后自动分发给步骤 20 和 21。

## API 依赖

前端按设计文档调用以下接口：

```text
GET    /api/clusters
POST   /api/clusters
PUT    /api/clusters/{cluster_id}
GET    /api/clusters/{cluster_id}/nodes
POST   /api/clusters/{cluster_id}/nodes
PUT    /api/nodes/{node_id}
DELETE /api/nodes/{node_id}
GET    /api/clusters/{cluster_id}/settings
PUT    /api/clusters/{cluster_id}/settings
POST   /api/clusters/{cluster_id}/precheck
POST   /api/clusters/{cluster_id}/install
GET    /api/jobs/{job_id}
GET    /api/jobs/{job_id}/steps
GET    /api/jobs/{job_id}/events
GET    /api/jobs/{job_id}/config-yaml
GET    /api/jobs/{job_id}/precheck-results
GET    /api/job-step-nodes/{item_id}/log
```

后端接口未启动时，页面会显示请求错误，但前端工程仍可启动和构建。

## SSH 认证范围

v0.1.0 仅支持 SSH 私钥认证，后端不会保存 SSH 密码或 sudo 密码。运行后端的管理节点必须能够使用配置的私钥登录目标节点。
