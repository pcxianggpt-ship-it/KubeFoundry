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
```

后端接口未启动时，页面会显示请求错误，但前端工程仍可启动和构建。

## SSH 认证范围

v0.1.0 仅支持 SSH 私钥认证，后端不会保存 SSH 密码或 sudo 密码。运行后端的管理节点必须能够使用配置的私钥登录目标节点。
