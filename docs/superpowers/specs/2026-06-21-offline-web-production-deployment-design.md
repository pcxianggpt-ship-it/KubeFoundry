# KubeFoundry Web 离线生产部署设计

## 1. 目标

为 KubeFoundry Web Wizard 提供一个完全离线的一键生产部署入口。用户在项目根目录执行部署脚本后，脚本完成架构识别、离线 Python 环境安装、前端静态资源部署、数据库初始化、systemd 服务注册、启动和健康检查。

部署必须兼容 `x86_64/amd64` 与 `aarch64/arm64`，目标服务器不需要预装 Node.js，也不需要访问互联网。

## 2. 部署目录

部署脚本以执行时的当前工作目录 `PWD` 作为部署根目录，不写入 `/opt/kubefoundry` 或 `/var/lib/kubefoundry`。

```text
${PWD}/
├── deploy.sh
├── web/
│   ├── backend/
│   └── frontend/
├── offline/
│   ├── runtime/
│   │   ├── amd64/
│   │   └── arm64/
│   ├── wheels/
│   │   ├── amd64/
│   │   └── arm64/
│   └── frontend-dist/
├── .runtime/
├── .venv/
├── data/
└── logs/
```

其中：

- `.runtime/` 保存部署时解压的当前架构 Python 运行时。
- `.venv/` 保存离线创建的 Python 虚拟环境。
- `data/` 保存 SQLite 数据库和运行期持久化数据。
- `logs/` 保存 Gunicorn 访问日志、错误日志和部署日志。
- `offline/frontend-dist/` 保存提前构建完成的前端产物。

systemd 服务会引用部署时解析出的绝对路径。部署完成后不得移动或重命名项目目录；如需移动，应在新目录重新执行部署脚本。

## 3. 运行架构

生产环境由 Gunicorn 托管 Flask 应用。Flask 同时提供：

- `/api/*` 后端接口；
- 前端构建后的静态资源；
- Vue 单页应用的路由回退。

不引入 Nginx，避免在完全离线环境中额外维护操作系统和架构相关的软件包。

服务默认监听：

```text
0.0.0.0:10001
```

端口 `10001` 用于避开镜像仓库使用的 `5000` 端口。

访问地址：

```text
http://<管理节点 IP>:10001/
```

健康检查地址：

```text
http://127.0.0.1:10001/api/health
```

## 4. 离线资源

离线发布包必须为两种架构分别准备资源：

```text
offline/runtime/amd64/
offline/runtime/arm64/
offline/wheels/amd64/
offline/wheels/arm64/
```

Python 离线依赖至少包括：

- Flask 2.2.5；
- Werkzeug 2.2.3；
- PyYAML 6.0.1；
- Gunicorn；
- 上述软件的全部传递依赖。

前端在联网构建环境中执行测试和构建，最终只将 `dist` 产物放入：

```text
offline/frontend-dist/
```

目标服务器不执行 `npm install` 或 `npm run build`。

## 5. 一键部署流程

`deploy.sh` 按以下顺序执行：

1. 检查是否在项目根目录运行。
2. 检查当前用户是否具有安装 systemd 服务所需的 root 权限。
3. 将 `uname -m` 映射为 `amd64` 或 `arm64`，不支持的架构立即报错。
4. 检查当前架构的 Python 运行时、wheel 包和前端构建产物是否完整。
5. 检查端口 `10001` 是否被其他进程占用；若已由 KubeFoundry 服务监听，则执行幂等更新。
6. 创建 `.runtime`、`.venv`、`data` 和 `logs` 目录。
7. 解压当前架构的 Python 运行时。
8. 使用离线 wheel 目录创建或更新虚拟环境，禁止访问 Python 包索引。
9. 将前端构建产物同步到后端静态资源目录。
10. 设置 `KF_DB_PATH=${PWD}/data/kubefoundry.db` 并初始化 SQLite 数据库。
11. 根据当前绝对路径生成 systemd 服务文件。
12. 执行 `systemctl daemon-reload`，启用并重启服务。
13. 轮询 `/api/health`；成功后输出访问地址，失败时输出日志位置和 `journalctl` 排查命令。

部署脚本重复执行时必须保留 `data/`，更新应用、运行时、依赖和前端资源，并重启服务。

## 6. systemd 服务

服务名称：

```text
kubefoundry-web.service
```

关键运行参数：

```text
WorkingDirectory=${PWD}/web/backend
Environment=KF_DB_PATH=${PWD}/data/kubefoundry.db
Environment=KF_WEB_HOST=0.0.0.0
Environment=KF_WEB_PORT=10001
ExecStart=${PWD}/.venv/bin/gunicorn ...
```

服务应配置：

- 开机自启；
- 异常退出自动重启；
- 明确的工作目录和环境变量；
- Gunicorn 访问日志写入 `${PWD}/logs/access.log`；
- Gunicorn 错误日志写入 `${PWD}/logs/error.log`。

## 7. 参数与维护命令

一键部署默认命令：

```bash
sudo bash deploy.sh
```

脚本提供以下辅助参数：

```text
--port PORT     覆盖默认端口 10001
--status        查看服务状态
--restart       重启服务
--stop          停止服务
--uninstall     删除 systemd 服务，但保留 data 和 logs
--help          显示帮助
```

常用维护命令：

```bash
systemctl status kubefoundry-web
systemctl restart kubefoundry-web
journalctl -u kubefoundry-web -f
```

## 8. 错误处理

部署脚本启用严格错误处理，并通过统一日志函数同时输出到终端和 `${PWD}/logs/deploy.log`。

关键失败必须返回非零退出码并给出明确原因，包括：

- 当前目录不是 KubeFoundry 项目根目录；
- 未使用 root 权限；
- 不支持的 CPU 架构；
- 当前架构离线资源缺失；
- Python 运行时不可执行；
- wheel 依赖安装失败；
- 前端构建产物缺失；
- 端口被其他服务占用；
- 数据库初始化失败；
- systemd 服务启动失败；
- 健康检查超时。

部署失败时不得删除已有 `data/`。

## 9. 安全与权限

- systemd 服务默认以执行 Kubernetes 安装所需的 root 用户运行，因为现有后端需要访问 SSH 私钥、执行 Bash 安装步骤并管理远程节点。
- 数据库、日志和生成的运行文件均限制在部署根目录下。
- 部署脚本不保存 SSH 密码；Web Wizard 继续只支持 SSH 私钥认证。
- 服务不启用 Flask debug 模式。

## 10. 测试与验收

实现必须包含自动化测试，至少覆盖：

- `x86_64` 映射为 `amd64`；
- `aarch64` 映射为 `arm64`；
- 不支持架构时失败；
- 默认端口为 `10001`；
- 自定义端口参数解析；
- 离线资源缺失时失败；
- systemd 服务内容使用当前目录绝对路径；
- 数据目录固定为 `${PWD}/data`；
- 重复部署不删除现有数据库；
- 前端根路径和未知前端路由返回单页应用；
- `/api/health` 保持可用；
- 所有新增文本文件使用 LF 换行符。

验收标准：

1. 在无互联网连接的 `amd64` 和 `arm64` 管理节点上均可完成部署。
2. 目标节点无需安装 Node.js。
3. 执行 `sudo bash deploy.sh` 后服务处于 `active (running)`。
4. 重启服务器后服务自动启动。
5. 浏览器访问 `http://<管理节点 IP>:10001/` 可打开 Web Wizard。
6. 重复部署后已有集群配置、任务记录和日志数据不丢失。
