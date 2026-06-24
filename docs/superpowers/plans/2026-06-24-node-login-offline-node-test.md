# 节点登录配置与离线安装优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现节点密码录入、后端生成集群 SSH 密钥、测试全部节点自动识别 OS/架构、节点复制草稿，以及删除 `install_mode` 的固定离线安装流程。

**Architecture:** 后端继续沿用 Flask + SQLite + Repository + 后台线程任务模型，新增凭据加密模块、节点配置校验模块和 `node_test` 任务模块。前端继续在 `App.vue` 内实现 Web Wizard，但把 SSH 步骤合并到节点配置页，集群基础配置删除安装模式、操作系统和架构输入。安装和预检查入口通过后端强制校验最近一次节点测试状态，不依赖前端禁用状态。

**Tech Stack:** Python 3、Flask、SQLite、pytest、Bash `ssh/sshpass/ssh-keygen/scp`、Vue 3、Element Plus、Vitest。

---

## Scope and file map

**Create:**

- `web/backend/kubefoundry/security/credentials.py`：主密钥生成、权限校验、密码加解密、敏感信息脱敏。
- `web/backend/kubefoundry/installer/node_test.py`：`node_test` 后台任务、SSH 密钥初始化、并行节点测试、OS/架构识别和同构校验。
- `web/backend/tests/test_credentials.py`：密码加密和权限测试。
- `web/backend/tests/test_node_login_api.py`：节点密码、草稿、复制、`install_mode` 删除和任务门禁 API 测试。
- `web/backend/tests/test_node_test.py`：节点测试执行器的命令构造、结果解析、状态回写测试。

**Modify:**

- `web/backend/requirements.txt`：增加 `cryptography`。
- `web/backend/kubefoundry/store/db.py`：迁移 `clusters.install_mode` 删除，新增 nodes 和 clusters 测试状态字段。
- `web/backend/kubefoundry/store/repository.py`：节点密码密文、草稿状态、配置版本、复制节点、节点测试状态和集群测试状态持久化。
- `web/backend/kubefoundry/api/routes.py`：调整集群/节点 API、增加复制节点和测试全部节点接口、返回脱敏字段。
- `web/backend/kubefoundry/config/context.py`：如存在对 `install_mode`、OS、arch 输入的依赖，改为从节点测试字段和固定离线语义读取。
- `web/backend/kubefoundry/installer/context.py`：上下文不包含 `install_mode`，SSH 固定使用集群密钥、root、22，YAML 不输出密码。
- `web/backend/kubefoundry/installer/precheck.py`：启动前校验节点测试状态；预检查时重新识别 OS/架构并在环境变化时标记 stale。
- `web/backend/kubefoundry/installer/runner.py`：安装启动前校验节点测试状态，阻止 node_test 并发冲突。
- `web/backend/kubefoundry/installer/ssh.py`：确保执行器从 context 的集群密钥、root、22 构造 SSH/SCP。
- `web/frontend/src/api/client.js`：增加复制节点、测试全部节点 API。
- `web/frontend/src/App.vue`：删除安装模式和独立 SSH 步骤，节点页增加密码、草稿、复制、只读 OS/架构、测试全部节点和门禁提示。
- `web/frontend/src/App.test.js`、`web/frontend/src/api/client.test.js`：覆盖前端删除字段、节点复制、测试全部节点入口和禁用状态。
- `doc/v0.1.0/web-wizard-v0.1.0-design.md`、`doc/v0.1.0/web-wizard-v0.1.0-usage.md`：同步新交互和安全约束。

---

## Task 1: 数据库迁移与 repository 脱敏模型

**Files:**

- Modify: `web/backend/kubefoundry/store/db.py`
- Modify: `web/backend/kubefoundry/store/repository.py`
- Test: `web/backend/tests/test_node_login_api.py`

- [ ] **Step 1: 写失败测试，证明 `install_mode` 已删除且节点响应脱敏**

在 `web/backend/tests/test_node_login_api.py` 新增测试：

```python
def test_cluster_schema_does_not_expose_install_mode(client, repo):
    response = client.post("/api/clusters", json={"name": "demo", "install_mode": "online"})
    assert response.status_code == 201
    cluster = response.get_json()
    assert "install_mode" not in cluster

    detail = client.get("/api/clusters/%s" % cluster["id"]).get_json()
    assert "install_mode" not in detail

    columns = [row["name"] for row in repo.conn.execute("PRAGMA table_info(clusters)").fetchall()]
    assert "install_mode" not in columns


def test_node_password_is_not_returned(client):
    cluster = client.post("/api/clusters", json={"name": "demo"}).get_json()
    response = client.post(
        "/api/clusters/%s/nodes" % cluster["id"],
        json={
            "hostname": "k8s1",
            "ip": "192.168.123.139",
            "role": "control_plane",
            "password": "Secret123!",
            "ssh_user": "admin",
            "ssh_port": 2222,
            "os_type": "manual",
            "arch": "arm64",
        },
    )
    assert response.status_code == 201
    node = response.get_json()
    assert node["has_password"] is True
    assert node["ssh_user"] == "root"
    assert node["ssh_port"] == 22
    assert node["os_type"] == ""
    assert node["arch"] == ""
    assert "password" not in node
    assert "login_password_encrypted" not in node
```

- [ ] **Step 2: 运行测试确认失败**

Run: `python -m pytest web/backend/tests/test_node_login_api.py -q`

Expected: FAIL，原因包括 `install_mode` 仍存在、`password` 未实现或节点字段未脱敏。

- [ ] **Step 3: 实现 schema 迁移**

在 `web/backend/kubefoundry/store/db.py`：

- 将 `SCHEMA_VERSION` 提升到 `0.1.2`。
- 从 `CREATE TABLE clusters` 删除 `install_mode`。
- 给 `clusters` 增加：

```sql
node_config_version INTEGER NOT NULL DEFAULT 1,
node_test_status TEXT NOT NULL DEFAULT 'pending',
node_tested_at TEXT,
node_test_job_id INTEGER
```

- 给 `nodes` 增加：

```sql
login_password_encrypted TEXT NOT NULL DEFAULT '',
is_draft INTEGER NOT NULL DEFAULT 0,
os_version TEXT NOT NULL DEFAULT '',
node_test_status TEXT NOT NULL DEFAULT 'pending',
node_tested_at TEXT,
node_test_message TEXT NOT NULL DEFAULT '',
node_test_config_version INTEGER
```

- 将 `arch` 默认值从 `amd64` 改为 `''`。
- 在 `_migrate_schema(conn)` 中：
  - 检测缺失列并 `ALTER TABLE ... ADD COLUMN`。
  - 如果 `clusters` 含 `install_mode`，重建 `clusters` 表并复制除 `install_mode` 之外的字段。
  - 保留现有 `_remove_api_server_port_column` 逻辑，但重建表模板也不得包含 `install_mode`。

- [ ] **Step 4: 实现 repository 公共响应模型**

在 `web/backend/kubefoundry/store/repository.py`：

- `create_cluster` 和 `update_cluster` 的 allowed 字段删除 `install_mode`。
- 新增 `_public_cluster(row)`：删除 `install_mode`。
- 新增 `_public_node(row)`：删除 `login_password_encrypted`，增加 `has_password = bool(login_password_encrypted)`，固定 `ssh_user = "root"`、`ssh_port = 22`。
- `list_clusters/get_cluster/list_nodes/get_node/create_node/update_node` 返回 public 模型。
- 新增内部方法 `get_node_private(node_id)` 和 `list_nodes_private(cluster_id)` 供任务读取密码密文。
- 节点新增、更新、删除时调用 `mark_node_config_changed(cluster_id)`，递增 `node_config_version`，设置集群 `node_test_status='stale'`，清空 `node_test_job_id`。

- [ ] **Step 5: 运行测试确认通过**

Run: `python -m pytest web/backend/tests/test_node_login_api.py -q`

Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add web/backend/kubefoundry/store/db.py web/backend/kubefoundry/store/repository.py web/backend/tests/test_node_login_api.py
git commit -m "实现节点登录字段与安装模式迁移"
```

---

## Task 2: 节点密码加密与草稿/复制规则

**Files:**

- Create: `web/backend/kubefoundry/security/credentials.py`
- Modify: `web/backend/requirements.txt`
- Modify: `web/backend/kubefoundry/store/repository.py`
- Modify: `web/backend/kubefoundry/api/routes.py`
- Test: `web/backend/tests/test_credentials.py`
- Test: `web/backend/tests/test_node_login_api.py`

- [ ] **Step 1: 写失败测试，证明密码加密、编辑保留密码、复制草稿**

在 `web/backend/tests/test_credentials.py` 新增：

```python
def test_encrypt_password_is_not_plaintext(tmp_path, monkeypatch):
    monkeypatch.setenv("KF_DATA_DIR", str(tmp_path))
    from kubefoundry.security.credentials import decrypt_text, encrypt_text

    token = encrypt_text("Secret123!")
    assert token != "Secret123!"
    assert decrypt_text(token) == "Secret123!"
    assert (tmp_path / "credentials" / "master.key").exists()
```

在 `web/backend/tests/test_node_login_api.py` 新增：

```python
def test_node_update_empty_password_keeps_existing_password(client, repo):
    cluster = client.post("/api/clusters", json={"name": "demo"}).get_json()
    node = client.post(
        "/api/clusters/%s/nodes" % cluster["id"],
        json={"hostname": "k8s1", "ip": "192.168.123.139", "role": "control_plane", "password": "Secret123!"},
    ).get_json()
    before = repo.get_node_private(node["id"])["login_password_encrypted"]

    response = client.put("/api/nodes/%s" % node["id"], json={"hostname": "k8s1", "ip": "192.168.123.139", "role": "control_plane", "password": ""})
    assert response.status_code == 200
    after = repo.get_node_private(node["id"])["login_password_encrypted"]
    assert after == before


def test_copy_nodes_creates_drafts_and_copies_password_ciphertext(client, repo):
    cluster = client.post("/api/clusters", json={"name": "demo"}).get_json()
    node = client.post(
        "/api/clusters/%s/nodes" % cluster["id"],
        json={"hostname": "k8s1", "ip": "192.168.123.139", "role": "worker", "password": "Secret123!"},
    ).get_json()

    response = client.post("/api/clusters/%s/nodes/copy" % cluster["id"], json={"node_ids": [node["id"]]})
    assert response.status_code == 201
    copied = response.get_json()["items"][0]
    assert copied["is_draft"] is True
    assert copied["hostname"] == "k8s1"
    assert copied["ip"] == "192.168.123.139"
    assert copied["has_password"] is True
    assert repo.get_node_private(copied["id"])["login_password_encrypted"] == repo.get_node_private(node["id"])["login_password_encrypted"]
```

- [ ] **Step 2: 运行测试确认失败**

Run: `python -m pytest web/backend/tests/test_credentials.py web/backend/tests/test_node_login_api.py -q`

Expected: FAIL，原因是加密模块和复制 API 尚不存在。

- [ ] **Step 3: 实现凭据加密模块**

在 `web/backend/requirements.txt` 增加：

```text
cryptography>=42.0.0
```

创建 `web/backend/kubefoundry/security/credentials.py`，提供：

```python
from cryptography.fernet import Fernet
from kubefoundry.store.db import data_dir
```

函数：

- `credentials_dir()` 返回 `data/credentials` 并确保目录权限 `0700`。
- `master_key_path()` 返回 `data/credentials/master.key`。
- `load_master_key()`：不存在则 `Fernet.generate_key()` 创建并 chmod `0600`；存在则校验权限不允许 group/other 读写。
- `encrypt_text(plain)`：空字符串返回空字符串；非空返回 Fernet token。
- `decrypt_text(token)`：空字符串返回空字符串；解密失败抛 `ValueError("password decrypt failed")`。
- `redact_sensitive(text)`：替换已知敏感词形态，例如 `SSHPASS=...`、`password=...`、用户密码明文不得由调用者传入日志。

- [ ] **Step 4: 实现草稿和复制 repository/API**

在 `repository.py`：

- `create_node` 接受 `password`，非空时加密到 `login_password_encrypted`。
- `update_node` 对 `password` 缺失或空字符串保留原密文；非空时替换密文。
- API 输入中的 `ssh_user/ssh_port/os_type/os_version/arch` 忽略，固定 root/22，只允许测试任务写系统信息。
- 新增 `copy_nodes(cluster_id, node_ids)`：同一事务复制节点，保留主机名、IP、IPv6、角色、密码密文、OS/arch 只读值，设置 `is_draft=1`、`node_test_status='stale'`。
- 新增 `validate_node_configuration(cluster_id)`：返回结构化问题，检查草稿、密码缺失、主机名/IP 缺失、重复。

在 `routes.py` 新增：

```python
@app.route("/api/clusters/<int:cluster_id>/nodes/copy", methods=["POST"])
```

返回：

```json
{"items": [复制后的节点公共模型]}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `python -m pytest web/backend/tests/test_credentials.py web/backend/tests/test_node_login_api.py -q`

Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add web/backend/requirements.txt web/backend/kubefoundry/security/credentials.py web/backend/kubefoundry/store/repository.py web/backend/kubefoundry/api/routes.py web/backend/tests/test_credentials.py web/backend/tests/test_node_login_api.py
git commit -m "实现节点密码加密与复制草稿"
```

---

## Task 3: 节点测试任务与 SSH 密钥初始化

**Files:**

- Create: `web/backend/kubefoundry/installer/node_test.py`
- Modify: `web/backend/kubefoundry/store/repository.py`
- Modify: `web/backend/kubefoundry/api/routes.py`
- Modify: `web/backend/kubefoundry/installer/ssh.py`
- Test: `web/backend/tests/test_node_test.py`
- Test: `web/backend/tests/test_node_login_api.py`

- [ ] **Step 1: 写失败测试，证明 node_test API、命令脱敏、OS/架构解析**

在 `web/backend/tests/test_node_test.py` 新增：

```python
def test_normalize_arch():
    from kubefoundry.installer.node_test import normalize_arch

    assert normalize_arch("x86_64") == "amd64"
    assert normalize_arch("aarch64") == "arm64"
    assert normalize_arch("loongarch64") == "loongarch64"


def test_parse_os_release():
    from kubefoundry.installer.node_test import parse_os_release

    info = parse_os_release('ID="kylin"\nNAME="Kylin Linux"\nVERSION_ID="V10"\n')
    assert info["os_type"] == "kylin"
    assert info["os_name"] == "Kylin Linux"
    assert info["os_version"] == "V10"
    assert info["os_major"] == "V10"
```

在 `web/backend/tests/test_node_login_api.py` 新增：

```python
def test_node_test_rejects_draft_nodes(client):
    cluster = client.post("/api/clusters", json={"name": "demo"}).get_json()
    node = client.post(
        "/api/clusters/%s/nodes" % cluster["id"],
        json={"hostname": "k8s1", "ip": "192.168.123.139", "role": "worker", "password": "Secret123!"},
    ).get_json()
    client.post("/api/clusters/%s/nodes/copy" % cluster["id"], json={"node_ids": [node["id"]]})

    response = client.post("/api/clusters/%s/node-test" % cluster["id"])
    assert response.status_code == 400
    assert "草稿" in response.get_json()["error"]
```

- [ ] **Step 2: 运行测试确认失败**

Run: `python -m pytest web/backend/tests/test_node_test.py web/backend/tests/test_node_login_api.py -q`

Expected: FAIL，原因是 `node_test.py` 和接口不存在。

- [ ] **Step 3: 实现节点测试模块**

在 `node_test.py`：

- `start_node_test_job(cluster_id)`：
  - 调用 `repo.validate_node_configuration(cluster_id)`，有问题直接 `ValueError`。
  - 检查同集群 active `node_test/precheck/install`，冲突返回 `ValueError` 或由 route 转 409。
  - 创建 `jobs.job_type='node_test'`。
  - 记录启动时 `node_config_version`。
  - 后台线程执行 `run_node_test_job(job_id, cluster_id, config_version)`。
- `ensure_cluster_key(cluster_id)`：
  - 使用 `ssh-keygen -t rsa -b 4096 -N "" -f data/credentials/clusters/{cluster_id}/id_rsa`。
  - chmod 目录 `0700`、私钥 `0600`、公钥 `0644`。
  - upsert `ssh_credentials(auth_type='key', username='root', private_key_path=...)`。
- `run_password_ssh(node, password, command)`：
  - 使用 `sshpass -e ssh -p 22 root@ip ...`。
  - 密码只放 `env={"SSHPASS": password}`。
  - 不把密码写入 stdout/stderr/log。
- 并行执行节点：
  - 创建 `/root/.ssh`。
  - 幂等追加公钥到 `authorized_keys`。
  - 使用私钥验证登录。
  - 执行 `cat /etc/os-release && printf "__KF_ARCH=%s\n" "$(uname -m)"`。
  - 回写 `os_type/os_version/arch/node_test_status/node_tested_at/node_test_message/node_test_config_version`。
- `parse_os_release(text)` 和 `normalize_arch(value)` 独立可测。
- 同构校验：所有节点 `os_type`、OS 主版本、`arch` 必须一致。
- 任一失败时 job failed，但其他节点继续完成。

- [ ] **Step 4: 接入 API 和 repository 状态回写**

在 `routes.py`：

```python
@app.route("/api/clusters/<int:cluster_id>/node-test", methods=["POST"])
```

- 成功返回 202：`{"job_id": id, "status": "pending"}`。
- 同集群已有运行中的 `node_test` 返回 409：`{"error": "...", "job_id": active_id}`。

在 `repository.py` 增加：

- `update_node_test_result(node_id, status, message, os_type="", os_version="", arch="", config_version=None)`。
- `update_cluster_node_test_state(cluster_id, status, job_id=None, tested_at=None)`。

- [ ] **Step 5: 运行测试确认通过**

Run: `python -m pytest web/backend/tests/test_node_test.py web/backend/tests/test_node_login_api.py -q`

Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add web/backend/kubefoundry/installer/node_test.py web/backend/kubefoundry/store/repository.py web/backend/kubefoundry/api/routes.py web/backend/kubefoundry/installer/ssh.py web/backend/tests/test_node_test.py web/backend/tests/test_node_login_api.py
git commit -m "实现节点连通性测试任务"
```

---

## Task 4: 预检查和安装门禁、上下文固定离线

**Files:**

- Modify: `web/backend/kubefoundry/installer/context.py`
- Modify: `web/backend/kubefoundry/installer/precheck.py`
- Modify: `web/backend/kubefoundry/installer/runner.py`
- Modify: `web/backend/kubefoundry/installer/validator.py`
- Test: `web/backend/tests/test_cluster_health.py`
- Test: `web/backend/tests/test_api.py`
- Test: `web/backend/tests/test_node_login_api.py`

- [ ] **Step 1: 写失败测试，证明没有有效 node_test 不能预检查或安装**

在 `web/backend/tests/test_node_login_api.py` 新增：

```python
def test_precheck_requires_successful_current_node_test(client):
    cluster = client.post("/api/clusters", json={"name": "demo"}).get_json()
    client.post(
        "/api/clusters/%s/nodes" % cluster["id"],
        json={"hostname": "k8s1", "ip": "192.168.123.139", "role": "control_plane", "password": "Secret123!"},
    )
    response = client.post("/api/clusters/%s/precheck" % cluster["id"])
    assert response.status_code == 400
    assert "节点测试" in response.get_json()["error"]


def test_context_uses_fixed_key_auth_and_no_install_mode(client):
    cluster = client.post("/api/clusters", json={"name": "demo"}).get_json()
    payload = client.get("/api/clusters/%s/context" % cluster["id"]).get_json()
    assert "install_mode" not in payload["cluster"]
    assert payload["ssh"]["username"] == "root"
    assert payload["ssh"]["auth_type"] == "key"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `python -m pytest web/backend/tests/test_node_login_api.py web/backend/tests/test_api.py -q`

Expected: FAIL，原因是门禁未接入或上下文仍含旧字段。

- [ ] **Step 3: 实现后端门禁**

在 `repository.py` 增加 `validate_node_test_ready(cluster_id)`：

- 调用 `validate_node_configuration(cluster_id)`。
- 集群 `node_test_status` 必须为 `success`。
- 最近一次成功任务版本必须等于当前 `node_config_version`；用节点的 `node_test_config_version` 或 cluster 保存的 job/version 字段判断。
- 不能存在同集群 active `node_test/precheck/install`。

在 `precheck.py` 和 `runner.py` 启动任务前调用该方法。错误消息使用中文，包含具体问题列表。

- [ ] **Step 4: 固定上下文离线和 SSH 私钥**

在 `context.py`：

- `context_to_yaml_data` 不输出 `install_mode`。
- `ssh` 输出：

```python
{
    "user": "root",
    "port": 22,
    "key_path": context["ssh"].get("private_key_path"),
    "timeout": 30,
    "control_persist": 300,
}
```

- `write_job_snapshot` 的 JSON 不包含节点密码密文。
- `import_cluster_yaml` 不导入 ssh 用户、端口、私钥路径和 install_mode；导入节点时密码缺失则创建为草稿或正式无密码并阻止后续任务。

- [ ] **Step 5: 预检查重新识别 OS/架构**

在 `precheck.py` 的 `CHECK_COMMAND` 增加：

```bash
echo "__KF__ARCH=$(uname -m)"
cat /etc/os-release | sed 's/^/__KF__OS_RELEASE__/'
```

解析后回写节点系统字段；若与最近成功 node_test 的发行版、主版本或架构不一致，则：

- 记录 fail 结果。
- 调用 `mark_node_config_changed` 或专用方法将 cluster `node_test_status='stale'`。
- 预检查任务失败。

- [ ] **Step 6: 运行测试确认通过**

Run: `python -m pytest web/backend/tests/test_node_login_api.py web/backend/tests/test_api.py web/backend/tests/test_cluster_health.py -q`

Expected: PASS。

- [ ] **Step 7: 提交**

```bash
git add web/backend/kubefoundry/installer/context.py web/backend/kubefoundry/installer/precheck.py web/backend/kubefoundry/installer/runner.py web/backend/kubefoundry/installer/validator.py web/backend/tests/test_cluster_health.py web/backend/tests/test_api.py web/backend/tests/test_node_login_api.py
git commit -m "增加节点测试门禁与固定离线上下文"
```

---

## Task 5: 前端向导页面调整

**Files:**

- Modify: `web/frontend/src/api/client.js`
- Modify: `web/frontend/src/App.vue`
- Test: `web/frontend/src/api/client.test.js`
- Test: `web/frontend/src/App.test.js`

- [ ] **Step 1: 写失败测试，证明页面删除旧输入并出现新能力**

在 `web/frontend/src/App.test.js` 增加断言：

```javascript
it('hides install mode and ssh step, then shows node login and test controls', async () => {
  render(App);
  expect(screen.queryByText('安装模式')).toBeNull();
  expect(screen.queryByText('SSH 配置')).toBeNull();
  expect(screen.queryByText('SSH 用户')).toBeNull();
  expect(screen.queryByText('SSH 端口')).toBeNull();
  expect(screen.queryByText('私钥路径')).toBeNull();
  expect(await screen.findByText('测试全部节点')).toBeTruthy();
  expect(await screen.findByText('复制所选')).toBeTruthy();
});
```

在 `web/frontend/src/api/client.test.js` 增加：

```javascript
it('calls copy nodes and node test endpoints', async () => {
  fetch.mockResponseOnce(JSON.stringify({ items: [] }));
  await copyNodes(1, [2, 3]);
  expect(fetch).toHaveBeenCalledWith('/api/clusters/1/nodes/copy', expect.objectContaining({ method: 'POST' }));

  fetch.mockResponseOnce(JSON.stringify({ job_id: 9, status: 'pending' }));
  await startNodeTest(1);
  expect(fetch).toHaveBeenCalledWith('/api/clusters/1/node-test', expect.objectContaining({ method: 'POST' }));
});
```

- [ ] **Step 2: 运行前端测试确认失败**

Run: `npm --prefix web/frontend test -- --run`

Expected: FAIL，原因是旧控件仍存在、新 API 未导出。

- [ ] **Step 3: 更新 API client**

在 `client.js` 增加：

```javascript
export function copyNodes(clusterId, nodeIds) {
  return request(`/api/clusters/${clusterId}/nodes/copy`, {
    method: 'POST',
    body: JSON.stringify({ node_ids: nodeIds })
  });
}

export function startNodeTest(clusterId) {
  return request(`/api/clusters/${clusterId}/node-test`, {
    method: 'POST'
  });
}
```

- [ ] **Step 4: 更新向导步骤和集群基础配置**

在 `App.vue`：

- `steps` 改为 8 步，删除 `ssh`。
- 集群基础配置删除 `安装模式` 控件和 `installModeOptions`。
- `clusterForm` 删除 `install_mode`。
- `saveCluster` 不调用 `upsertSshCredentials`。
- 删除 `sshForm`、`authTypeOptions` 和独立 SSH 表单。
- 在基础配置展示只读提示：“当前版本仅支持离线安装”。

- [ ] **Step 5: 更新节点表格和弹窗**

在节点页：

- 表格增加 selection 列，维护 `selectedNodeIds`。
- 增加按钮：

```text
复制所选
测试全部节点
```

- 列显示：主机名、IP、IPv6、角色、密码状态、草稿状态、操作系统、系统版本、架构、测试状态、测试时间、操作。
- 删除 SSH 用户、端口、操作系统输入、架构输入。
- 弹窗字段改为主机名、IPv4、IPv6、角色、登录密码。
- 新增节点密码必填；编辑已有节点密码可空，placeholder 为“留空表示保留原密码”。
- 草稿节点显示未完成原因，复制后显示草稿标签。

- [ ] **Step 6: 接入测试全部节点和门禁提示**

在 `App.vue`：

- `runNodeTest()` 调用 `startNodeTest`，绑定 `currentJob`，连接 SSE。
- `copySelectedNodes()` 调用 `copyNodes` 后刷新节点。
- `nodeConfigProblems` computed 根据节点字段和 cluster `node_test_status` 生成中文提示。
- 预检查和安装按钮在 `nodeConfigProblems.length > 0` 时禁用并显示原因。
- `refreshJob()` 对 `node_test` 任务刷新步骤并在结束后刷新 cluster/nodes。

- [ ] **Step 7: 运行前端测试确认通过**

Run: `npm --prefix web/frontend test -- --run`

Expected: PASS。

- [ ] **Step 8: 提交**

```bash
git add web/frontend/src/api/client.js web/frontend/src/App.vue web/frontend/src/api/client.test.js web/frontend/src/App.test.js
git commit -m "更新节点登录配置前端向导"
```

---

## Task 6: 文档、全量验证与安全检查

**Files:**

- Modify: `doc/v0.1.0/web-wizard-v0.1.0-design.md`
- Modify: `doc/v0.1.0/web-wizard-v0.1.0-usage.md`
- Modify: `README.md` if it references install mode or SSH step

- [ ] **Step 1: 更新文档**

同步写明：

- 集群基础配置无安装模式，系统固定离线安装。
- 节点配置必须录入 root 密码，端口固定 22。
- 后端生成集群 SSH 密钥，节点测试负责分发公钥。
- OS/架构由测试全部节点自动识别。
- 复制节点会生成草稿，草稿阻止预检查和安装。
- 密码不会在 API、日志、YAML 或任务快照中出现。

- [ ] **Step 2: 运行后端测试**

Run: `python -m pytest web/backend/tests -q`

Expected: PASS。

- [ ] **Step 3: 运行前端测试和构建**

Run: `npm --prefix web/frontend test -- --run`

Expected: PASS。

Run: `npm --prefix web/frontend run build`

Expected: exit code 0。

- [ ] **Step 4: 运行项目格式和泄密检查**

Run: `bash scripts/ci/check-lf.sh`

Expected: exit code 0。

Run: `bash scripts/ci/check-secrets.sh`

Expected: exit code 0。

Run: `git diff --check`

Expected: exit code 0。

- [ ] **Step 5: 手动浏览器验收**

启动后端和前端后，在页面确认：

1. 集群基础配置没有安装模式。
2. 没有独立 SSH 配置步骤。
3. 节点弹窗没有 SSH 用户、端口、操作系统、架构输入。
4. 新增节点必须填写密码。
5. 节点表格可以多选并复制为草稿。
6. 页面只有“测试全部节点”入口。
7. 草稿、测试失败或测试失效时预检查和安装禁用。

- [ ] **Step 6: 提交文档和验证补充**

```bash
git add doc/v0.1.0/web-wizard-v0.1.0-design.md doc/v0.1.0/web-wizard-v0.1.0-usage.md README.md
git commit -m "更新节点登录优化文档"
```

---

## Self-review checklist

- Spec coverage:
  - SSH 配置合并到节点配置：Task 2、Task 5。
  - 密码必填、加密保存、API 脱敏：Task 1、Task 2。
  - 后端生成集群密钥并分发公钥：Task 3。
  - 节点复制为草稿：Task 2、Task 5。
  - 删除 `install_mode` 字段：Task 1、Task 4、Task 5。
  - 删除 OS/架构输入并自动识别：Task 3、Task 4、Task 5。
  - 节点测试并行、同构校验和状态回写：Task 3。
  - 预检查/安装门禁：Task 4、Task 5。
  - 文档同步和验证：Task 6。
- Placeholder scan: 本计划未发现空泛占位语义，所有任务均绑定具体文件、命令和期望结果。
- Type consistency: 统一使用 `node_test_status`、`node_config_version`、`login_password_encrypted`、`is_draft`、`has_password`、`os_type`、`os_version`、`arch` 字段名。
