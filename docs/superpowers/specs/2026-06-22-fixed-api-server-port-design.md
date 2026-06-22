# API Server 端口固定为 6443 设计

## 背景

KubeFoundry 当前允许通过 `network.api_server_port`、Web 集群字段以及运行时环境变量配置 Kubernetes API Server 端口。项目决定取消该配置能力，所有安装流程统一使用 Kubernetes 默认端口 `6443`。

## 目标

- API Server 端口只能是 `6443`。
- `config/cluster.yaml` 不再包含 API Server 端口配置。
- Bash 脚本不再读取、校验或注入 API Server 端口变量。
- Web 页面不再展示或提交 API Server 端口。
- Web 后端不再把 API Server 端口作为集群配置保存。
- 导入旧 YAML 时静默忽略 `network.api_server_port`，无论其值为何。
- 导出的 YAML 不再包含 `network.api_server_port`。
- 当前有效文档统一说明 API Server 固定使用 `6443`。

## 非目标

- 不修改 SSH、镜像仓库、Web 服务等其他端口配置。
- 不改变 Kubernetes API Server 的固定端口值。
- 不修改归档的历史版本设计、验收和开发计划文档中的历史描述。

## Bash 与配置设计

从 `config/cluster.yaml` 删除 `network.api_server_port`。

配置校验脚本删除 API Server 端口读取和通用端口范围校验。集群初始化脚本中的 kubeadm 配置直接使用：

```yaml
localAPIEndpoint:
  bindPort: 6443
controlPlaneEndpoint: "<control-plane-hostname>:6443"
```

远程脚本注入逻辑删除 `_inj_api_server_port` 和 `API_SERVER_PORT`。集群初始化脚本不再依赖该环境变量。

## Web 后端设计

集群创建和更新接口忽略请求中的 `api_server_port`，不再将其写入数据库。

数据库迁移删除 `clusters.api_server_port` 列。由于 SQLite 不同版本对 `DROP COLUMN` 支持不一致，迁移采用重建 `clusters` 表或兼容当前运行环境的等价安全方式，并保持现有集群数据及外键关系。

集群运行上下文不再生成可配置的 `network.api_server_port`。运行时环境文件不再生成 `KF_API_SERVER_PORT` 或 `API_SERVER_PORT`。

YAML 导入逻辑不读取 `network.api_server_port`。旧 YAML 中该字段可以存在且可以是任意值，导入过程不报错，实际安装仍固定使用 `6443`。

YAML 导出、任务快照和配置预览不再输出 `network.api_server_port`。如果 `network` 中没有其他配置，则不输出空的 `network` 节点。

## Web 前端设计

删除集群表单中的 API Server 端口输入控件、`clusterForm.api_server_port` 默认值和对应校验规则。

加载旧集群数据时，即使后端响应暂时包含旧字段，前端也不展示、不编辑、不主动提交该字段。

## 文档设计

更新当前有效文档中的以下内容：

- 删除 `network.api_server_port` 配置示例、变量表和读取示例。
- 将 kubeadm 示例改为直接写入 `6443`。
- 将步骤依赖说明改为“API Server 固定使用 6443”。
- 明确 API Server 端口不可配置。

归档在 `doc/v0.1.0/` 下的历史设计、开发计划和验收文档保留原貌。

## 测试与验证

测试先覆盖以下行为：

1. Web 创建或更新集群时传入 `api_server_port` 不会改变实际配置。
2. 导入带有非 `6443` 端口的旧 YAML 成功，导出结果不包含该字段。
3. 生成的运行时环境不包含 API Server 端口变量。
4. 集群初始化脚本只包含固定值 `6443`，不引用 `API_SERVER_PORT`。
5. 前端不再渲染 API Server 端口输入项，也不提交该字段。
6. 配置文件、现行脚本和现行文档中不存在 `network.api_server_port`、`KF_API_SERVER_PORT` 或 `API_SERVER_PORT` 配置链路。

完成修改后运行后端测试、前端测试、Shell 语法检查和项目 LF 检查。

## 兼容与风险

- 旧 YAML 保持可导入，旧端口值会被静默忽略。
- 已有数据库中的旧字段通过迁移移除，不影响其他集群属性。
- 历史任务快照可能仍包含旧字段，但恢复或重新执行时不得再读取该值。
- 固定端口会使此前依赖非标准 API Server 端口的环境无法继续使用，这是本次变更的预期行为。
