# API Server 端口固定为 6443 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 彻底移除 API Server 端口配置链路，并让所有 Kubernetes 安装固定使用 `6443`。

**Architecture:** Bash 端在 kubeadm 配置中直接写入 `6443`，不再读取或注入端口变量。Web 后端忽略旧请求和旧 YAML 中的端口字段、迁移删除数据库旧列，前端删除输入项；导出和运行时环境不再携带该配置。

**Tech Stack:** Bash、YAML、Python 3.7+/Flask/SQLite/PyYAML、Vue 3/Vitest。

---

### Task 1: 用后端测试锁定兼容与迁移行为

**Files:**
- Modify: `web/backend/tests/test_api.py`
- Modify: `web/backend/kubefoundry/store/db.py`
- Modify: `web/backend/kubefoundry/store/repository.py`
- Modify: `web/backend/kubefoundry/installer/context.py`
- Modify: `web/backend/kubefoundry/config/context.py`
- Modify: `web/backend/kubefoundry/installer/runtime.py`

- [ ] **Step 1: 编写失败测试**

在 `test_api.py` 增加测试，断言：

```python
cluster = repo.create_cluster({"name": "fixed-port", "api_server_port": 7443})
self.assertNotIn("api_server_port", cluster)
repo.update_cluster(cluster["id"], {"api_server_port": 8443})
self.assertNotIn("api_server_port", repo.get_cluster(cluster["id"]))

import_cluster_yaml(cluster["id"], yaml_text="""
cluster:
  name: fixed-port
network:
  api_server_port: 9443
""")
context = build_cluster_context(cluster["id"])
self.assertNotIn("network", context)
self.assertNotIn("network", context_to_yaml_data(context))
self.assertNotIn("API_SERVER_PORT", render_runtime_env(context, node))
self.assertNotIn("KF_API_SERVER_PORT", render_runtime_env(context, node))
```

另建一个带旧 `api_server_port` 列的临时数据库，调用 `init_db()` 后断言 `PRAGMA table_info(clusters)` 中不再有该列，原集群记录仍存在。

- [ ] **Step 2: 运行测试并确认按预期失败**

Run:

```bash
cd web/backend
python -m unittest tests.test_api -v
```

Expected: FAIL，失败原因是旧字段仍被保存、导出或写入运行时环境。

- [ ] **Step 3: 实现数据库与仓储层最小修改**

在 `db.py`：

- 从新建表结构删除 `api_server_port`。
- `_migrate_schema()` 检测旧列；存在时关闭外键、创建不含旧列的 `clusters_new`、复制其他列、删除旧表并重命名。
- 保持 `id`、时间戳和所有非端口字段原值。

在 `repository.py` 的 `create_cluster()`、`update_cluster()` 允许字段列表中删除 `"api_server_port"`，使旧 API 请求被静默忽略。

- [ ] **Step 4: 实现上下文、YAML 和运行时最小修改**

在两个 context 模块中删除：

```python
"network": {
    "api_server_port": ...
}
```

在 YAML 导入更新字典中删除：

```python
"api_server_port": network.get("api_server_port")
```

保留读取旧 YAML 的能力，但不使用 `network` 中的该字段。`runtime.py` 删除 `KF_API_SERVER_PORT` 和兼容变量 `API_SERVER_PORT`。

- [ ] **Step 5: 运行测试并确认通过**

Run:

```bash
cd web/backend
python -m unittest tests.test_api -v
```

Expected: PASS。

### Task 2: 用前端测试移除页面配置

**Files:**
- Modify: `web/frontend/src/App.test.js`
- Modify: `web/frontend/src/App.vue`

- [ ] **Step 1: 编写失败测试**

在 `App.test.js` 增加断言：

```javascript
expect(wrapper.text()).not.toContain('API Server 端口');
expect(wrapper.vm.clusterForm).not.toHaveProperty('api_server_port');
```

并在保存集群的 API mock 调用参数中断言：

```javascript
expect(payload).not.toHaveProperty('api_server_port');
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
cd web/frontend
npm test -- --runInBand
```

Expected: FAIL，页面或提交数据仍包含 `api_server_port`。

- [ ] **Step 3: 删除前端配置链路**

从 `App.vue` 删除 API Server 端口表单项：

```vue
<el-form-item label="API Server 端口" prop="api_server_port">
  <el-input-number ... />
</el-form-item>
```

同时删除 `clusterForm.api_server_port` 和 `clusterRules.api_server_port`。

- [ ] **Step 4: 运行前端测试**

Run:

```bash
cd web/frontend
npm test
npm run build
```

Expected: 全部 PASS，构建退出码为 0。

### Task 3: 固定 Bash 安装端口

**Files:**
- Create: `scripts/tests/test_fixed_api_server_port.sh`
- Modify: `scripts/lib/exec_script.sh`
- Modify: `scripts/steps/phase1_precheck/03-validate-config.sh`
- Modify: `scripts/steps/phase2_k8s_base/18-init-k8s-cluster.sh`
- Modify: `config/cluster.yaml`

- [ ] **Step 1: 编写失败的静态回归测试**

创建脚本检查：

```bash
#!/bin/bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

! grep -R -n -E 'network\.api_server_port|KF_API_SERVER_PORT|API_SERVER_PORT' \
    "${PROJECT_ROOT}/scripts" "${PROJECT_ROOT}/config/cluster.yaml"
grep -q 'bindPort: 6443' \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/18-init-k8s-cluster.sh"
grep -q 'controlPlaneEndpoint: "${local_hostname}:6443"' \
    "${PROJECT_ROOT}/scripts/steps/phase2_k8s_base/18-init-k8s-cluster.sh"
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
bash scripts/tests/test_fixed_api_server_port.sh
```

Expected: FAIL，现有脚本仍包含变量配置链路。

- [ ] **Step 3: 实现固定端口**

- `config/cluster.yaml` 仅删除 API Server 端口注释和字段，保留用户现有 IP、路径等修改。
- `exec_script.sh` 删除 `_inj_api_server_port`、配置读取及 `API_SERVER_PORT` 导出。
- `03-validate-config.sh` 删除 API Server 端口读取与校验段，并顺延注释序号。
- `18-init-k8s-cluster.sh` 删除环境变量说明，把两个 `bindPort` 和两个 `controlPlaneEndpoint` 改为字面量 `6443`。

- [ ] **Step 4: 运行测试和 Shell 语法检查**

Run:

```bash
bash scripts/tests/test_fixed_api_server_port.sh
bash -n scripts/lib/exec_script.sh
bash -n scripts/steps/phase1_precheck/03-validate-config.sh
bash -n scripts/steps/phase2_k8s_base/18-init-k8s-cluster.sh
```

Expected: 全部退出码为 0。

### Task 4: 同步当前有效文档

**Files:**
- Modify: `README.md`
- Modify: `doc/api.md`
- Modify: `doc/cmdlist.md`
- Modify: `doc/design.md`
- Modify: `doc/steps-reference.md`
- Modify: `doc/variables.md`
- Modify: `doc/manual-ops.md`（仅在需要明确固定端口时）

- [ ] **Step 1: 更新配置和变量说明**

删除 `network.api_server_port` 的配置示例、读取示例、变量表项和端口合法性校验示例。保留 kubeadm、join、手工运维命令中的字面量 `6443`。

- [ ] **Step 2: 更新步骤与接口说明**

将步骤文档中的“依赖 `network.api_server_port`”改为“API Server 固定使用 `6443`”，并从参数来源列表中删除该配置。

- [ ] **Step 3: 检查现行文档残留**

Run:

```bash
grep -R -n -E 'network\.api_server_port|KF_API_SERVER_PORT|API_SERVER_PORT|api_server_port:' \
    README.md doc \
    --exclude-dir=v0.1.0
```

Expected: 无输出。归档目录 `doc/v0.1.0/` 不在修改范围。

### Task 5: 完整验证与提交

**Files:**
- Verify all modified files

- [ ] **Step 1: 运行后端完整测试**

Run:

```bash
cd web/backend
python -m unittest discover -s tests -v
```

Expected: 全部 PASS。

- [ ] **Step 2: 运行前端完整测试与构建**

Run:

```bash
cd web/frontend
npm test
npm run build
```

Expected: 全部 PASS。

- [ ] **Step 3: 运行 Bash 与 LF 检查**

Run:

```bash
bash scripts/tests/test_cli_routing.sh
bash scripts/tests/test_web_package_deploy.sh
bash scripts/tests/test_fixed_api_server_port.sh
bash scripts/ci/check-lf.sh
```

Expected: 全部退出码为 0。

- [ ] **Step 4: 审查差异和需求覆盖**

Run:

```bash
git diff --check
git diff --stat
git status --short
```

确认没有覆盖用户在 `config/cluster.yaml`、`README.md` 和文档整理中的无关改动。

- [ ] **Step 5: 提交**

仅暂存本需求相关文件和相关行，使用中文提交说明：

```bash
git commit -m "变更：固定API Server端口为6443"
```
