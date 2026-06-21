# KubeFoundry Web 离线生产部署设计

## 1. 目标

为 KubeFoundry Web Wizard 提供一键打包和一键部署两个入口：

- `package.sh` 在制作机上构建前端、收集后端源码和纯 Python 离线依赖，生成单个发布压缩包。
- `deploy.sh` 在目标机上根据发布压缩包完成解压、虚拟环境创建、离线依赖安装、数据库初始化、systemd 服务注册、启动和健康检查。

目标服务器使用系统自带的 Python 3，不需要预装 Node.js，也不需要访问互联网。发布包不包含 Python 解释器，且 Python 依赖使用纯 Python 分发包，因此同一个发布包兼容 `x86_64/amd64` 与 `aarch64/arm64`。

## 2. 部署目录

部署脚本以执行时的当前工作目录 `PWD` 作为部署根目录，不写入 `/opt/kubefoundry` 或 `/var/lib/kubefoundry`。

```text
${PWD}/
├── package.sh
├── deploy.sh
├── dist/
│   └── kubefoundry-web-v0.1.0.tar.gz
├── web/
│   ├── backend/
│   └── frontend/
├── .venv/
├── data/
└── logs/
```

其中：

- `dist/` 保存 `package.sh` 生成的离线发布压缩包。
- `.venv/` 保存离线创建的 Python 虚拟环境。
- `data/` 保存 SQLite 数据库和运行期持久化数据。
- `logs/` 保存 Gunicorn 访问日志、错误日志和部署日志。

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

## 4. 发布包结构

`package.sh` 默认生成：

```text
dist/kubefoundry-web-v0.1.0.tar.gz
```

压缩包内容：

```text
kubefoundry-web-v0.1.0/
├── deploy.sh
├── backend/
├── frontend-dist/
├── wheels/
├── requirements.txt
├── VERSION
└── SHA256SUMS
```

`wheels/` 至少包含以下软件及其全部传递依赖：

- Flask 2.2.5；
- Werkzeug 2.2.3；
- PyYAML 6.0.1；
- Gunicorn。

制作时必须要求 pip 下载纯 Python 分发包，禁止将平台相关的二进制 wheel 放入发布包。若某项依赖无法获取纯 Python 分发包，`package.sh` 必须失败并明确报告依赖名称。

前端在联网构建环境中执行测试和构建，最终只将 `dist` 产物放入：

```text
kubefoundry-web-v0.1.0/frontend-dist/
```

目标服务器不执行 `npm install` 或 `npm run build`。

## 5. 一键打包流程

`package.sh` 按以下顺序执行：

1. 检查脚本位于 KubeFoundry 项目根目录。
2. 检查 `node`、`npm`、`python3` 和 `pip` 可用。
3. 读取版本号，默认使用后端包中的 `0.1.0`。
4. 在 `web/frontend` 执行 `npm ci`、前端测试和生产构建。
5. 创建临时发布目录并复制后端源码。
6. 复制前端 `dist` 到发布目录的 `frontend-dist/`。
7. 使用 pip 下载纯 Python 离线依赖到 `wheels/`。
8. 将目标机使用的 `deploy.sh` 放入发布目录。
9. 生成 `VERSION` 和 `SHA256SUMS`。
10. 生成 `dist/kubefoundry-web-v<版本>.tar.gz`。
11. 校验压缩包可读取并输出文件路径、大小和 SHA-256。

`package.sh` 可重复执行；每次只替换同版本的临时目录和压缩包，不修改源码、数据库或目标机部署目录。

## 6. 一键部署流程

`deploy.sh` 按以下顺序执行：

1. 接收发布压缩包路径，命令格式为 `sudo bash deploy.sh <压缩包>`。
2. 检查压缩包存在且可读取。
3. 检查当前目录可写，并将其作为部署根目录。
4. 检查当前用户是否具有安装 systemd 服务所需的 root 权限。
5. 检查系统 `python3` 满足最低版本要求并支持 `venv`。
6. 解压到临时目录并校验 `SHA256SUMS`。
7. 检查发布包中的后端、前端、wheel 和版本文件完整。
8. 检查端口 `10001` 是否被其他进程占用；若已由 KubeFoundry 服务监听，则执行幂等更新。
9. 创建 `.venv`、`data` 和 `logs` 目录。
10. 将应用内容更新到 `${PWD}/app`，但不覆盖或删除 `data/` 和 `logs/`。
11. 使用系统 Python 创建虚拟环境。
12. 使用发布包中的 wheel 目录安装依赖，必须启用 `--no-index`。
13. 将前端构建产物放入 Flask 可提供服务的静态目录。
14. 设置 `KF_DB_PATH=${PWD}/data/kubefoundry.db` 并初始化 SQLite 数据库。
15. 根据当前绝对路径生成 systemd 服务文件。
16. 执行 `systemctl daemon-reload`，启用并重启服务。
17. 轮询 `/api/health`；成功后输出访问地址，失败时输出日志位置和 `journalctl` 排查命令。

部署脚本重复执行时必须保留 `data/`，更新应用、依赖和前端资源，并重启服务。

## 7. systemd 服务

服务名称：

```text
kubefoundry-web.service
```

关键运行参数：

```text
WorkingDirectory=${PWD}/app/backend
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

## 8. 参数与维护命令

一键打包命令：

```bash
bash package.sh
```

一键部署默认命令：

```bash
sudo bash deploy.sh dist/kubefoundry-web-v0.1.0.tar.gz
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

## 9. 错误处理

部署脚本启用严格错误处理，并通过统一日志函数同时输出到终端和 `${PWD}/logs/deploy.log`。

关键失败必须返回非零退出码并给出明确原因，包括：

- 当前目录不是 KubeFoundry 项目根目录；
- 未使用 root 权限；
- Node.js、npm、Python 或 pip 在打包机上不可用；
- 前端测试或构建失败；
- 无法获得纯 Python 离线依赖；
- 发布压缩包不存在、损坏或校验失败；
- 系统 Python 版本过低或缺少 venv；
- wheel 依赖安装失败；
- 前端构建产物缺失；
- 端口被其他服务占用；
- 数据库初始化失败；
- systemd 服务启动失败；
- 健康检查超时。

部署失败时不得删除已有 `data/`。

## 10. 安全与权限

- systemd 服务默认以执行 Kubernetes 安装所需的 root 用户运行，因为现有后端需要访问 SSH 私钥、执行 Bash 安装步骤并管理远程节点。
- 数据库、日志和生成的运行文件均限制在部署根目录下。
- 部署脚本不保存 SSH 密码；Web Wizard 继续只支持 SSH 私钥认证。
- 服务不启用 Flask debug 模式。

## 11. 测试与验收

实现必须包含自动化测试，至少覆盖：

- 打包脚本生成预期命名的压缩包；
- 压缩包包含后端、前端、wheel、部署脚本、版本和校验文件；
- wheel 目录不包含平台相关二进制 wheel；
- 默认端口为 `10001`；
- 自定义端口参数解析；
- 压缩包缺失或校验失败时部署失败；
- Python 版本不满足要求时失败；
- systemd 服务内容使用当前目录绝对路径；
- 数据目录固定为 `${PWD}/data`；
- 重复部署不删除现有数据库；
- 前端根路径和未知前端路由返回单页应用；
- `/api/health` 保持可用；
- 所有新增文本文件使用 LF 换行符。

验收标准：

1. 同一个发布压缩包可在无互联网连接的 `amd64` 和 `arm64` 管理节点上完成部署。
2. 目标节点无需安装 Node.js。
3. 执行 `sudo bash deploy.sh <压缩包>` 后服务处于 `active (running)`。
4. 重启服务器后服务自动启动。
5. 浏览器访问 `http://<管理节点 IP>:10001/` 可打开 Web Wizard。
6. 重复部署后已有集群配置、任务记录和日志数据不丢失。
