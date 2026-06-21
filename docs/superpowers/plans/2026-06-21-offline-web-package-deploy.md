# KubeFoundry Web 离线打包部署实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供 `package.sh` 和 `deploy.sh`，生成架构无关的 Web 离线压缩包，并在目标机当前目录部署为监听 `10001` 的 systemd 服务。

**Architecture:** 制作机负责测试和构建 Vue 前端，并将 Flask 后端、Gunicorn 入口及纯 Python 依赖源码一起装入 tar.gz。目标机使用系统 Python 创建虚拟环境，不访问网络；部署脚本将应用安装到 `${PWD}/app`，数据保存到 `${PWD}/data`，日志保存到 `${PWD}/logs`，随后生成并启动 systemd 服务。

**Tech Stack:** Bash、Python 3、Flask、Gunicorn、Vue 3、Vite、systemd、tar、SHA-256

---

## 文件结构

- 创建 `package.sh`：联网制作机的一键打包入口。
- 创建 `deploy.sh`：目标机的一键部署和服务维护入口。
- 创建 `scripts/tests/test_web_package_deploy.sh`：测试脚本参数、压缩包结构、路径和 systemd 内容。
- 修改 `web/backend/kubefoundry/api/routes.py`：提供前端静态资源和 SPA 路由回退。
- 修改 `web/backend/tests/test_api.py`：验证前端入口、静态文件和 API 404 边界。
- 修改 `web/backend/requirements.txt`：加入固定版本 Gunicorn。
- 修改 `README.md`：增加离线打包和生产部署说明。
- 修改 `doc/v0.1.0/web-wizard-v0.1.0-usage.md`：补充生产部署、目录和维护命令。

### Task 1: Flask 提供生产前端资源

**Files:**
- Modify: `web/backend/kubefoundry/api/routes.py`
- Modify: `web/backend/tests/test_api.py`

- [ ] **Step 1: 写失败测试**

在 `ApiTestCase` 中创建临时前端目录，设置 `KF_FRONTEND_DIST`，写入 `index.html` 和 `assets/app.js`，增加以下测试：

```python
def test_frontend_static_files_and_spa_fallback(self):
    response = self.client.get("/")
    self.assertEqual(response.status_code, 200)
    self.assertIn("KubeFoundry production", response.get_data(as_text=True))

    response = self.client.get("/assets/app.js")
    self.assertEqual(response.status_code, 200)
    self.assertIn("production asset", response.get_data(as_text=True))

    response = self.client.get("/clusters/1/install")
    self.assertEqual(response.status_code, 200)
    self.assertIn("KubeFoundry production", response.get_data(as_text=True))

    response = self.client.get("/api/not-found")
    self.assertEqual(response.status_code, 404)
```

- [ ] **Step 2: 验证测试失败**

Run:

```bash
cd web/backend
python3 -m unittest tests.test_api.ApiTestCase.test_frontend_static_files_and_spa_fallback -v
```

Expected: FAIL，根路径当前返回 404。

- [ ] **Step 3: 实现静态资源和 SPA 回退**

将 Flask 初始化改为读取 `KF_FRONTEND_DIST`，并在所有 API 路由之后增加：

```python
frontend_dist = os.environ.get(
    "KF_FRONTEND_DIST",
    os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "frontend-dist"),
)
app = Flask(__name__, static_folder=None)

@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def frontend(path):
    if path.startswith("api/"):
        return jsonify({"error": "not found"}), 404
    candidate = os.path.join(frontend_dist, path)
    if path and os.path.isfile(candidate):
        return send_from_directory(frontend_dist, path)
    index_path = os.path.join(frontend_dist, "index.html")
    if os.path.isfile(index_path):
        return send_from_directory(frontend_dist, "index.html")
    return jsonify({"error": "frontend assets not found"}), 404
```

同时从 Flask 导入 `send_from_directory`。

- [ ] **Step 4: 验证测试通过**

Run:

```bash
cd web/backend
python3 -m unittest tests.test_api -v
```

Expected: 所有 API 测试通过。

- [ ] **Step 5: 提交**

```bash
git add web/backend/kubefoundry/api/routes.py web/backend/tests/test_api.py
git commit -m "功能：支持后端托管生产前端资源"
```

### Task 2: 一键部署脚本

**Files:**
- Create: `deploy.sh`
- Create: `scripts/tests/test_web_package_deploy.sh`

- [ ] **Step 1: 写失败测试**

测试通过设置 `KF_DEPLOY_TEST_MODE=1` 跳过真实 systemd 操作，并断言：

```bash
bash "${PROJECT_ROOT}/deploy.sh" --help | grep -q -- "--port PORT"
bash "${PROJECT_ROOT}/deploy.sh" --help | grep -q "10001"
grep -q 'DEFAULT_PORT="10001"' "${PROJECT_ROOT}/deploy.sh"
grep -q 'DATA_DIR="${DEPLOY_ROOT}/data"' "${PROJECT_ROOT}/deploy.sh"
grep -q 'WorkingDirectory=${APP_DIR}/backend' "${PROJECT_ROOT}/deploy.sh"
grep -q 'KF_FRONTEND_DIST=${APP_DIR}/frontend-dist' "${PROJECT_ROOT}/deploy.sh"
```

测试再创建最小发布包，执行：

```bash
KF_DEPLOY_TEST_MODE=1 bash deploy.sh --port 11001 fixture.tar.gz
```

并断言生成的测试 service 文件包含当前目录绝对路径、端口 `11001`，且预先写入的 `data/keep.txt` 仍存在。

- [ ] **Step 2: 验证测试失败**

Run:

```bash
bash scripts/tests/test_web_package_deploy.sh
```

Expected: FAIL，`deploy.sh` 不存在。

- [ ] **Step 3: 实现部署脚本**

`deploy.sh` 使用 `set -euo pipefail`，实现：

```bash
DEFAULT_PORT="10001"
SERVICE_NAME="kubefoundry-web"
DEPLOY_ROOT="$(pwd -P)"
APP_DIR="${DEPLOY_ROOT}/app"
DATA_DIR="${DEPLOY_ROOT}/data"
LOG_DIR="${DEPLOY_ROOT}/logs"
VENV_DIR="${DEPLOY_ROOT}/.venv"
```

脚本解析 `--port`、`--status`、`--restart`、`--stop`、`--uninstall`、`--help` 和压缩包路径；验证 root、Python 版本、`venv`、tar 包和 SHA-256；将包内容原子更新到 `app/`；保留 `data/` 和 `logs/`；使用：

```bash
python3 -m venv --system-site-packages "${VENV_DIR}"
"${VENV_DIR}/bin/python" -m pip install \
    --no-index \
    --find-links "${APP_DIR}/wheels" \
    -r "${APP_DIR}/requirements.txt"
```

生成 `/etc/systemd/system/kubefoundry-web.service`，核心内容为：

```ini
[Service]
WorkingDirectory=${APP_DIR}/backend
Environment=KF_DB_PATH=${DATA_DIR}/kubefoundry.db
Environment=KF_DATA_DIR=${DATA_DIR}
Environment=KF_FRONTEND_DIST=${APP_DIR}/frontend-dist
ExecStart=${VENV_DIR}/bin/gunicorn --workers 1 --threads 4 --bind 0.0.0.0:${PORT} --access-logfile ${LOG_DIR}/access.log --error-logfile ${LOG_DIR}/error.log kubefoundry.api.routes:create_app()
Restart=on-failure
```

测试模式将 service 文件写入 `${DEPLOY_ROOT}/logs/kubefoundry-web.service.test`，不要求 root、不调用 systemctl、不执行健康检查。

- [ ] **Step 4: 验证部署测试通过**

Run:

```bash
bash scripts/tests/test_web_package_deploy.sh
bash -n deploy.sh
```

Expected: 两条命令均成功。

- [ ] **Step 5: 提交**

```bash
git add deploy.sh scripts/tests/test_web_package_deploy.sh
git commit -m "功能：增加Web一键离线部署脚本"
```

### Task 3: 一键打包脚本

**Files:**
- Create: `package.sh`
- Modify: `scripts/tests/test_web_package_deploy.sh`
- Modify: `web/backend/requirements.txt`

- [ ] **Step 1: 扩展失败测试**

测试 `package.sh --help`、默认输出名称和测试模式打包：

```bash
bash "${PROJECT_ROOT}/package.sh" --help | grep -q "dist/kubefoundry-web-v"
KF_PACKAGE_TEST_MODE=1 bash "${PROJECT_ROOT}/package.sh"
tar -tzf "${PROJECT_ROOT}/dist/kubefoundry-web-v0.1.0.tar.gz" |
    grep -q "kubefoundry-web-v0.1.0/deploy.sh"
```

继续断言压缩包包含：

```text
backend/app.py
backend/kubefoundry/
frontend-dist/index.html
wheels/
requirements.txt
VERSION
SHA256SUMS
```

- [ ] **Step 2: 验证测试失败**

Run:

```bash
bash scripts/tests/test_web_package_deploy.sh
```

Expected: FAIL，`package.sh` 不存在。

- [ ] **Step 3: 固定生产依赖**

将 `web/backend/requirements.txt` 更新为：

```text
Flask==2.2.5
Werkzeug==2.2.3
PyYAML==6.0.1
gunicorn==21.2.0
```

- [ ] **Step 4: 实现打包脚本**

`package.sh` 使用 `set -euo pipefail`，读取 `web/backend/kubefoundry/__init__.py` 中的版本号，正常模式执行：

```bash
cd web/frontend
npm ci
npm test
npm run build

python3 -m pip download \
    --dest "${STAGING_DIR}/wheels" \
    --requirement web/backend/requirements.txt
```

脚本复制后端源码、前端构建产物、`deploy.sh` 和 requirements，生成 `VERSION`。在发布目录中执行：

```bash
find . -type f ! -name SHA256SUMS -print0 |
    sort -z |
    xargs -0 sha256sum > SHA256SUMS
```

最后生成：

```text
dist/kubefoundry-web-v0.1.0.tar.gz
```

测试模式不运行 npm 或 pip，创建最小前端文件和空 wheel 占位文件，用于验证归档结构。

- [ ] **Step 5: 验证打包测试通过**

Run:

```bash
bash scripts/tests/test_web_package_deploy.sh
bash -n package.sh
```

Expected: 所有断言通过。

- [ ] **Step 6: 提交**

```bash
git add package.sh scripts/tests/test_web_package_deploy.sh web/backend/requirements.txt
git commit -m "功能：增加Web一键离线打包脚本"
```

### Task 4: 文档同步

**Files:**
- Modify: `README.md`
- Modify: `doc/v0.1.0/web-wizard-v0.1.0-usage.md`

- [ ] **Step 1: 写文档检查测试**

在部署测试中加入：

```bash
grep -q "bash package.sh" "${PROJECT_ROOT}/README.md"
grep -q "sudo bash deploy.sh" "${PROJECT_ROOT}/README.md"
grep -q "10001" "${PROJECT_ROOT}/doc/v0.1.0/web-wizard-v0.1.0-usage.md"
grep -q '${PWD}/data' "${PROJECT_ROOT}/doc/v0.1.0/web-wizard-v0.1.0-usage.md"
```

- [ ] **Step 2: 验证文档测试失败**

Run:

```bash
bash scripts/tests/test_web_package_deploy.sh
```

Expected: FAIL，现有文档缺少生产部署命令。

- [ ] **Step 3: 更新文档**

文档明确：

```bash
bash package.sh
sudo bash deploy.sh dist/kubefoundry-web-v0.1.0.tar.gz
```

并记录默认端口 `10001`、`${PWD}/app`、`${PWD}/data`、`${PWD}/logs`、目标机 Python 3/venv 要求、目录不可移动、systemd 维护命令和重复部署保留数据。

- [ ] **Step 4: 验证文档测试通过**

Run:

```bash
bash scripts/tests/test_web_package_deploy.sh
```

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add README.md doc/v0.1.0/web-wizard-v0.1.0-usage.md scripts/tests/test_web_package_deploy.sh
git commit -m "文档：补充Web离线生产部署说明"
```

### Task 5: 全量验证

**Files:**
- Verify only

- [ ] **Step 1: 运行后端测试**

Run:

```bash
cd web/backend
python3 -m unittest discover -s tests -v
```

Expected: 全部通过。

- [ ] **Step 2: 运行前端测试和构建**

Run:

```bash
cd web/frontend
npm test
npm run build
```

Expected: 测试通过并生成 `dist/`。

- [ ] **Step 3: 运行脚本测试和语法检查**

Run:

```bash
bash scripts/tests/test_cli_routing.sh
bash scripts/tests/test_web_package_deploy.sh
bash -n package.sh
bash -n deploy.sh
```

Expected: 全部通过。

- [ ] **Step 4: 检查 LF 和 Git 差异**

Run:

```bash
bash scripts/ci/check-lf.sh
git diff --check
```

Expected: 无输出且退出码为 0。

- [ ] **Step 5: 生成真实发布包并检查结构**

Run:

```bash
bash package.sh
tar -tzf dist/kubefoundry-web-v0.1.0.tar.gz
sha256sum dist/kubefoundry-web-v0.1.0.tar.gz
```

Expected: 压缩包生成成功，包含后端、前端、依赖、部署脚本和校验文件。
