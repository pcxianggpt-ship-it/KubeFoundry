# KubeFoundry Web Wizard v0.1.0 使用说明

## 离线生产部署

在可联网且已安装 Node.js、npm、Python 3 和 pip 的构建机上，进入项目根目录执行：

```bash
bash package.sh
```

生成的发布包位于：

```text
dist/kubefoundry-web-v0.1.0.tar.gz
```

将发布包和 `deploy.sh` 复制到目标 Linux 服务器。进入最终部署目录后执行：

```bash
sudo bash deploy.sh kubefoundry-web-v0.1.0.tar.gz
```

部署脚本以执行时的 `${PWD}` 为安装根目录：

```text
${PWD}/app
${PWD}/data
${PWD}/logs
```

服务默认监听 `0.0.0.0:10001`，访问地址为：

```text
http://<管理节点 IP>:10001/
```

目标服务器要求 Python 3.7 或更高版本，不需要 Node.js、npm 或互联网连接。部署目录会写入 systemd 服务的绝对路径，部署完成后不要移动或重命名该目录。

重复执行部署脚本会更新应用文件，并保留 `${PWD}/data` 和 `${PWD}/logs`。

常用维护命令：

```bash
sudo bash deploy.sh --status
sudo bash deploy.sh --restart
sudo bash deploy.sh --stop
sudo bash deploy.sh --uninstall
journalctl -u kubefoundry-web -f
```

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
2. 节点与登录配置
3. 路径配置
4. 生态组件选择
5. 预检查任务
6. 配置 YAML 预览
7. 安装任务
8. 任务状态和 SSE 日志

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
web-verify-cluster-health
```

执行安装前，管理节点的安装介质目录至少需要包含：

```text
${install_media}/01.rpm_package/k8srepo_kylinos_sp3_${arch}.tar.gz
${install_media}/01.rpm_package/kubeadm-v${k8s_version}-100y-${arch}
${install_media}/02.container_runtime/
${install_media}/03.setup_file/kube-flannel.yml
${install_media}/04.registry/
```

Python 会在任务启动前验证这些路径，并按步骤分发到目标节点。`18-init-k8s-cluster` 使用 `kubeadm token create --print-join-command` 和 `kubeadm init phase upload-certs` 生成控制节点及工作节点 join 命令，保存为任务产物后自动分发给步骤 20 和 21。

安装介质必须位于运行后端的 Linux 管理节点本地。节点配置页需要录入每台服务器的 IP、SSH 用户、SSH 端口和登录密码；点击“测试全部节点”后，后端会为当前集群生成 SSH 密钥，按节点登录信息分发公钥，并自动识别操作系统和架构。后续预检查和安装统一使用后端生成的集群私钥登录。

最终步骤 `web-verify-cluster-health` 会等待最多 5 分钟，检查所有节点 Ready、Flannel 就绪以及系统 Pod 无失败状态。

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
POST   /api/clusters/{cluster_id}/nodes/copy
POST   /api/clusters/{cluster_id}/node-test
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

## 节点登录与 SSH 认证范围

v0.1.0 支持在节点级配置 SSH 用户和端口，默认值为 `root` 和 `22`。页面仍不暴露全局默认私钥路径；集群私钥由后端生成并管理。

节点密码用于首次连通性测试和公钥分发，后端加密保存到 SQLite，不会出现在 API 响应、日志、`cluster.yaml` 或任务快照中。页面只显示“已配置/未配置”状态；编辑节点时密码框留空表示保留原密码。

节点配置页支持复制所选节点，复制结果会以草稿形式保存。复制节点编辑并保存后会转为正式节点。存在草稿、缺少密码、主机名或 IP 重复、节点测试失败或测试结果失效时，预检查和安装都会被拒绝。

## 已验证环境

2026-06-20 至 2026-06-21 已在以下环境完成真实安装：

```text
Kylin Linux Advanced Server V10
1 control_plane + 2 workers
Kubernetes v1.30.14
containerd 1.7.18
Flannel
registry 2.8.3
```

详细记录见 `doc/v0.1.0/web-wizard-v0.1.0-acceptance.md`。
