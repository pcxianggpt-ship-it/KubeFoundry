# KubeFoundry Web Wizard v0.1.0 Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在当前 `codex/web-wizard-v0.1.0` 分支已有实现上，补齐 Web Wizard v0.1.0 的发布阻塞项，使其能够稳定完成配置、预检查、Phase 2 安装、实时追踪和失败定位。

**Architecture:** 保持 Flask + sqlite3 + Vue 3 + Element Plus 架构，继续由 Python 编排器负责任务状态、节点选择、并发、SSH/SCP、快照和日志，Bash step 只执行节点内命令。任务生命周期通过 SQLite 约束和启动恢复保证一致性，安装结束后增加 Python 驱动的集群综合健康验证。

**Tech Stack:** Python 3.7、Flask 2.2、sqlite3、PyYAML、unittest、Vue 3、Element Plus、Vite 5、Vitest、Bash、GitHub Actions

---

## 当前基线

已具备：

- 集群、节点、SSH 私钥引用和集群设置 CRUD。
- SQLite schema、任务快照、`cluster.yaml` 和 `runtime.env`。
- 节点预检查、SSE、任务历史、节点日志。
- Phase 2 的 13 个步骤及串行/并行目标解析。
- 基础九步 Web 向导。

本计划不重复重建上述功能，只补齐设计文档验收标准与当前发布缺口。

## 文件结构映射

### 新增文件

- `web/backend/tests/test_job_lifecycle.py`：任务互斥、服务重启恢复测试。
- `web/backend/tests/test_runner.py`：安装编排器串行、并行、资源、产物和失败路径测试。
- `web/backend/tests/test_cluster_health.py`：安装后综合健康检查测试。
- `web/backend/kubefoundry/installer/health.py`：集群节点、系统 Pod、Flannel 和 API Server 健康检查。
- `web/frontend/src/api/client.test.js`：前端 API 客户端测试。
- `web/frontend/src/App.test.js`：向导关键流程组件测试。
- `web/frontend/vitest.config.js`：Vitest + jsdom 配置。
- `scripts/ci/check-lf.sh`：受控文本文件 LF 检查。
- `scripts/ci/check-secrets.sh`：示例凭据和常见私钥内容检查。
- `.github/workflows/ci.yml`：后端、前端、Bash、LF 和敏感信息检查。
- `doc/v0.1.0/web-wizard-v0.1.0-acceptance.md`：真实环境成功与失败路径验收记录模板。

### 修改文件

- `web/backend/kubefoundry/store/repository.py`：活动任务查询和中断任务恢复。
- `web/backend/kubefoundry/api/routes.py`：启动恢复、重复安装返回 409。
- `web/backend/kubefoundry/installer/runner.py`：可测试依赖边界和最终健康检查。
- `web/backend/kubefoundry/installer/plan.py`：增加最终健康检查内置步骤。
- `web/frontend/package.json`、`web/frontend/package-lock.json`：增加测试命令和依赖。
- `web/frontend/vite.config.js`：固定跨平台 root/build 路径。
- `web/frontend/src/App.vue`：隐藏尚未执行的 Phase 3 组件，改善重复安装提示。
- `scripts/lib/exec_script.sh`：增加主控制节点和其他控制节点执行函数。
- `scripts/main.sh`：修复控制节点目标范围和无效 dry-run。
- `config/cluster.yaml`：清除明文密码示例。
- `README.md`、`doc/v0.1.0/web-wizard-v0.1.0-usage.md`、`doc/api.md`：同步发布范围、启动和接口行为。
- `.gitattributes`：维持文本文件 LF 规则。

## Task 1: 建立任务生命周期互斥与重启恢复

**Files:**

- Create: `web/backend/tests/test_job_lifecycle.py`
- Modify: `web/backend/kubefoundry/store/repository.py`
- Modify: `web/backend/kubefoundry/api/routes.py`

- [ ] **Step 1: 写重复安装与遗留任务恢复的失败测试**

```python
import os
import shutil
import tempfile
import unittest

from kubefoundry.api.routes import create_app
from kubefoundry.store.db import init_db
from kubefoundry.store.repository import Repository


class JobLifecycleTestCase(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix="kf-lifecycle-")
        os.environ["KF_DATA_DIR"] = self.temp_dir
        os.environ["KF_DB_PATH"] = os.path.join(self.temp_dir, "kubefoundry.db")
        init_db()

    def tearDown(self):
        os.environ.pop("KF_DATA_DIR", None)
        os.environ.pop("KF_DB_PATH", None)
        shutil.rmtree(self.temp_dir)

    def test_find_active_job_for_cluster(self):
        repo = Repository()
        cluster = repo.create_cluster({"name": "demo"})
        active = repo.create_job(cluster["id"], "install", {}, "", self.temp_dir)
        self.assertEqual(active["id"], repo.find_active_job(cluster["id"], "install")["id"])

    def test_recover_interrupted_jobs(self):
        repo = Repository()
        cluster = repo.create_cluster({"name": "demo"})
        job = repo.create_job(cluster["id"], "install", {}, "", self.temp_dir)
        repo.update_job(job["id"], status="running")
        recovered = repo.fail_interrupted_jobs("backend restarted")
        self.assertEqual(1, recovered)
        self.assertEqual("failed", repo.get_job(job["id"])["status"])
        self.assertEqual("backend restarted", repo.get_job(job["id"])["failure_reason"])
```

- [ ] **Step 2: 运行测试并确认因方法或字段不存在而失败**

Run:

```bash
cd web/backend
python -m unittest tests.test_job_lifecycle -v
```

Expected: FAIL，指出 `find_active_job`、`fail_interrupted_jobs` 或 `failure_reason` 尚不存在。

- [ ] **Step 3: 给任务表增加失败原因并实现生命周期查询**

在 `jobs` schema 中增加：

```sql
failure_reason TEXT DEFAULT '',
```

由于现有数据库不会被 `CREATE TABLE IF NOT EXISTS` 自动补列，在 `init_db()` 中执行兼容迁移：

```python
columns = [
    row["name"]
    for row in conn.execute("PRAGMA table_info(jobs)").fetchall()
]
if "failure_reason" not in columns:
    conn.execute("ALTER TABLE jobs ADD COLUMN failure_reason TEXT DEFAULT ''")
```

在 `Repository` 中增加：

```python
def find_active_job(self, cluster_id, job_type=None):
    sql = "SELECT * FROM jobs WHERE cluster_id=? AND status IN ('pending', 'running')"
    params = [cluster_id]
    if job_type:
        sql += " AND job_type=?"
        params.append(job_type)
    sql += " ORDER BY id DESC LIMIT 1"
    return _row(self.conn.execute(sql, params).fetchone())

def fail_interrupted_jobs(self, reason):
    with self.conn:
        cur = self.conn.execute(
            "UPDATE jobs SET status='failed', finished_at=datetime('now'), failure_reason=? "
            "WHERE status IN ('pending', 'running')",
            (reason,),
        )
    return cur.rowcount
```

- [ ] **Step 4: 在应用启动时恢复遗留任务，在创建安装任务前拒绝重复任务**

在 `create_app()` 初始化后调用：

```python
Repository().fail_interrupted_jobs("backend restarted before task completion")
```

在安装接口调用 `start_install_job` 前增加：

```python
active_job = repo().find_active_job(cluster_id, "install")
if active_job:
    return jsonify({
        "error": "cluster already has an active install job",
        "job_id": active_job["id"],
    }), 409
```

同时把恢复逻辑放在 `create_app()`，不要放在模块 import 阶段，确保测试数据库环境变量先设置再初始化。

- [ ] **Step 5: 增加 API 级重复安装断言并运行全量后端测试**

Run:

```bash
cd web/backend
python -m unittest discover -s tests -v
```

Expected: 全部 PASS，重复安装请求返回 409，已有任务 ID 可供前端跳转。

- [ ] **Step 6: 提交**

```bash
git add web/backend/tests/test_job_lifecycle.py web/backend/kubefoundry/store/db.py web/backend/kubefoundry/store/repository.py web/backend/kubefoundry/api/routes.py
git commit -m "fix(web): guard install job lifecycle"
```

## Task 2: 为安装编排器补齐执行链测试

**Files:**

- Create: `web/backend/tests/test_runner.py`
- Modify: `web/backend/kubefoundry/installer/runner.py`

- [ ] **Step 1: 写串行、并行、失败中止和产物传递测试**

使用 `unittest.mock.patch` 替换 `run_ssh`、`scp_to_node`、`copy_path_to_node` 和 `ThreadPoolExecutor` 的外部副作用。测试至少包含：

```python
def test_failed_step_stops_following_steps(self):
    plan = [
        self.step("first", mode="serial"),
        self.step("second", mode="serial"),
    ]
    with patch("kubefoundry.installer.runner._run_step", side_effect=[False]) as run_step:
        runner._run_install_job(self.job_id, self.context, plan)
    self.assertEqual(1, run_step.call_count)
    self.assertEqual("failed", self.repo.get_job(self.job_id)["status"])

def test_parallel_step_runs_once_per_target(self):
    step = self.step("parallel", mode="parallel", max_workers=2)
    with patch("kubefoundry.installer.runner._run_step_on_node", return_value=True) as run_node:
        self.assertTrue(runner._run_step(
            self.job_id, self.context, step, self.log_dir, {}
        ))
    self.assertEqual(2, run_node.call_count)

def test_join_artifact_is_collected_and_reused(self):
    artifacts = {}
    with patch("kubefoundry.installer.runner.run_ssh", return_value=(0, "kubeadm join ...\n", "")):
        runner._collect_step_outputs(
            self.job_id,
            self.context,
            {"outputs": [{"key": "worker_join", "remote_path": "/tmp/k8s/kube_join_nodes"}]},
            [self.context["control_plane"][0]],
            artifacts,
        )
    self.assertTrue(os.path.isfile(artifacts["worker_join"]))
```

- [ ] **Step 2: 运行测试并确认暴露当前不可控依赖或状态不一致**

Run:

```bash
cd web/backend
python -m unittest tests.test_runner -v
```

Expected: 新测试至少有一项 FAIL，失败原因对应未注入的外部调用、异常后步骤状态或任务状态。

- [ ] **Step 3: 将单节点执行结果收敛为结构化返回值**

在 `runner.py` 中增加：

```python
def _node_result(ok, exit_code, message, stdout="", stderr=""):
    return {
        "ok": bool(ok),
        "exit_code": int(exit_code),
        "message": message,
        "stdout": stdout or "",
        "stderr": stderr or "",
    }
```

让 `_run_step_on_node()` 返回该字典，并让 `_run_step()` 使用 `result["ok"]` 判断失败。这样测试可以精确断言退出码、消息和输出，不依赖布尔值猜测。

- [ ] **Step 4: 确保异常节点也会落库并写日志**

在 `_run_step_on_node()` 的 SSH/SCP/脚本执行主体外增加 `try/except Exception`，异常路径统一：

```python
except Exception as exc:
    code = 1
    out = ""
    err = str(exc)
```

随后继续执行节点日志写入和 `job_step_nodes` 更新，禁止异常绕过节点终态。

- [ ] **Step 5: 运行编排器测试和全量后端测试**

Run:

```bash
cd web/backend
python -m unittest tests.test_runner -v
python -m unittest discover -s tests -v
python -m compileall -q kubefoundry tests
```

Expected: 全部 PASS，`compileall` 无输出并返回 0。

- [ ] **Step 6: 提交**

```bash
git add web/backend/tests/test_runner.py web/backend/kubefoundry/installer/runner.py
git commit -m "test(installer): cover runner execution chain"
```

## Task 3: 增加安装后的集群综合健康检查

**Files:**

- Create: `web/backend/tests/test_cluster_health.py`
- Create: `web/backend/kubefoundry/installer/health.py`
- Modify: `web/backend/kubefoundry/installer/plan.py`
- Modify: `web/backend/kubefoundry/installer/runner.py`

- [ ] **Step 1: 写健康检查解析测试**

```python
from kubefoundry.installer.health import evaluate_cluster_health


def test_healthy_cluster_passes(self):
    result = evaluate_cluster_health(
        expected_nodes=["master-1", "worker-1"],
        ready_nodes=["master-1", "worker-1"],
        not_ready_nodes=[],
        failed_pods=[],
        flannel_ready=2,
    )
    self.assertTrue(result["ok"])

def test_not_ready_node_fails(self):
    result = evaluate_cluster_health(
        expected_nodes=["master-1", "worker-1"],
        ready_nodes=["master-1"],
        not_ready_nodes=["worker-1"],
        failed_pods=[],
        flannel_ready=1,
    )
    self.assertFalse(result["ok"])
    self.assertIn("worker-1", result["message"])
```

- [ ] **Step 2: 运行测试并确认模块不存在**

Run:

```bash
cd web/backend
python -m unittest tests.test_cluster_health -v
```

Expected: FAIL，`kubefoundry.installer.health` 不存在。

- [ ] **Step 3: 实现纯解析函数和远程检查命令**

`health.py` 对外提供：

```python
def evaluate_cluster_health(expected_nodes, ready_nodes, not_ready_nodes, failed_pods, flannel_ready):
    missing = sorted(set(expected_nodes) - set(ready_nodes) - set(not_ready_nodes))
    problems = []
    if not_ready_nodes:
        problems.append("NotReady nodes: %s" % ", ".join(sorted(not_ready_nodes)))
    if missing:
        problems.append("missing nodes: %s" % ", ".join(missing))
    if failed_pods:
        problems.append("failed pods: %s" % ", ".join(sorted(failed_pods)))
    if flannel_ready < len(expected_nodes):
        problems.append("flannel ready %s/%s" % (flannel_ready, len(expected_nodes)))
    return {
        "ok": not problems,
        "message": "; ".join(problems) if problems else "cluster health check passed",
    }
```

远程命令统一在主控制节点执行，读取：

```bash
KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes --no-headers
KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A --no-headers
```

- [ ] **Step 4: 将内置健康检查作为 Step Plan 最后一步**

在 `STEP_PLAN` 末尾增加：

```python
{
    "key": "web-verify-cluster-health",
    "name": "验证 Kubernetes 集群健康",
    "phase": "verify",
    "target_scope": "primary_control_plane",
    "builtin": "cluster_health",
    "mode": "serial",
    "fail_fast": True,
    "resources": [],
}
```

在 runner 中识别 `builtin == "cluster_health"`，调用 `health.py`，将完整 kubectl 输出写入该节点日志，并按检查结果返回 0 或 1。

- [ ] **Step 5: 更新 Step Plan 数量断言并运行测试**

将现有 `13` 步断言更新为 `14`，最后一步断言改为 `web-verify-cluster-health`。

Run:

```bash
cd web/backend
python -m unittest discover -s tests -v
```

Expected: 全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add web/backend/tests/test_cluster_health.py web/backend/tests/test_api.py web/backend/kubefoundry/installer/health.py web/backend/kubefoundry/installer/plan.py web/backend/kubefoundry/installer/runner.py
git commit -m "feat(installer): verify final cluster health"
```

## Task 4: 修复跨平台前端构建并建立前端测试基线

**Files:**

- Modify: `web/frontend/vite.config.js`
- Modify: `web/frontend/package.json`
- Modify: `web/frontend/package-lock.json`
- Create: `web/frontend/vitest.config.js`
- Create: `web/frontend/src/api/client.test.js`

- [ ] **Step 1: 先复现生产构建失败**

Run:

```bash
cd web/frontend
npm ci
npm run build
```

Expected: 当前 Windows 环境复现 Rollup 将绝对路径作为资源名的错误。

- [ ] **Step 2: 使用 URL 解析固定 Vite root 和输出目录**

将 `vite.config.js` 改为：

```javascript
import { fileURLToPath, URL } from 'node:url';
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  root: fileURLToPath(new URL('.', import.meta.url)),
  plugins: [vue()],
  build: {
    outDir: 'dist',
    emptyOutDir: true
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:5000',
        changeOrigin: true
      }
    }
  }
});
```

- [ ] **Step 3: 增加 Vitest 测试命令和依赖**

`package.json` 增加：

```json
"test": "vitest run",
"test:watch": "vitest"
```

开发依赖增加：

```json
"@vue/test-utils": "^2.4.6",
"jsdom": "^25.0.1",
"vitest": "^2.1.9"
```

执行 `npm install` 更新 lockfile。

- [ ] **Step 4: 配置 jsdom 并测试 API 错误传播**

`vitest.config.js`：

```javascript
import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  test: {
    environment: 'jsdom',
    clearMocks: true
  }
});
```

`client.test.js` 至少断言：

```javascript
it('throws backend error message', async () => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
    ok: false,
    status: 409,
    text: async () => JSON.stringify({ error: 'cluster already has an active install job' })
  }));
  await expect(startInstall(1)).rejects.toThrow('cluster already has an active install job');
});
```

- [ ] **Step 5: 运行测试和构建**

Run:

```bash
cd web/frontend
npm test
npm run build
```

Expected: 两条命令均返回 0，`dist/index.html` 存在。

- [ ] **Step 6: 提交**

```bash
git add web/frontend/vite.config.js web/frontend/vitest.config.js web/frontend/package.json web/frontend/package-lock.json web/frontend/src/api/client.test.js
git commit -m "test(frontend): add cross-platform build checks"
```

## Task 5: 覆盖向导关键用户流程并对齐 MVP 展示范围

**Files:**

- Create: `web/frontend/src/App.test.js`
- Modify: `web/frontend/src/App.vue`
- Modify: `web/frontend/src/api/client.js`

- [ ] **Step 1: 写创建集群、添加节点、预检查和重复安装提示测试**

使用 Vue Test Utils shallow mount，并 mock `./api/client`。测试断言：

```javascript
it('creates a cluster before moving to node step', async () => {
  createCluster.mockResolvedValue({ id: 7, name: 'demo' });
  upsertSshCredentials.mockResolvedValue({});
  updateClusterSettings.mockResolvedValue({});
  const wrapper = mount(App);
  await wrapper.vm.saveCluster();
  expect(createCluster).toHaveBeenCalled();
  expect(wrapper.vm.selectedClusterId).toBe(7);
});

it('shows active job returned by conflict response', async () => {
  startInstall.mockRejectedValue(Object.assign(
    new Error('cluster already has an active install job'),
    { jobId: 42 }
  ));
  await wrapper.vm.runInstall();
  expect(wrapper.text()).toContain('cluster already has an active install job');
});
```

- [ ] **Step 2: 运行测试并确认组件当前不可测试或行为不完整**

Run:

```bash
cd web/frontend
npm test -- App.test.js
```

Expected: FAIL，暴露未导出逻辑、Element Plus 全局组件或 409 job_id 未透传。

- [ ] **Step 3: 让 API 错误保留状态码和后端字段**

在 `request()` 中构造错误：

```javascript
const error = new Error(message);
error.status = response.status;
error.payload = payload;
error.jobId = payload?.job_id;
throw error;
```

安装冲突时，前端绑定 `error.jobId` 并跳转任务结果页，不创建第二个任务。

- [ ] **Step 4: 暂时隐藏未接入的生态组件开关**

设计稿允许高级选项后置，但当前 Phase 3 未进入 Step Plan。将生态组件步骤展示为：

```text
生态组件安装将在 v0.2.0 接入；v0.1.0 安装任务仅执行 Kubernetes 底座和 Flannel。
```

保留已保存配置的只读摘要，禁用开关，避免用户误认为当前任务会执行 Phase 3。

- [ ] **Step 5: 运行前端测试和构建**

Run:

```bash
cd web/frontend
npm test
npm run build
```

Expected: 全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add web/frontend/src/App.vue web/frontend/src/App.test.js web/frontend/src/api/client.js
git commit -m "fix(frontend): align wizard with mvp execution scope"
```

## Task 6: 修复 Bash CLI 控制节点目标范围和 dry-run

**Files:**

- Modify: `scripts/lib/exec_script.sh`
- Modify: `scripts/main.sh`
- Modify: `doc/api.md`

- [ ] **Step 1: 增加 Shell 级目标解析测试命令**

在修改前用静态断言记录预期：

```bash
rg -n 'exec_script_on_control_plane.*(14-replace|18-init|19-modify|20-add|22-install)' scripts/main.sh
```

Expected: 能匹配到当前错误调用。

- [ ] **Step 2: 增加主控制节点和其他控制节点执行函数**

`scripts/lib/exec_script.sh` 增加：

```bash
exec_script_on_primary_control_plane() {
    local script_file="$1"
    shift
    local primary_ip
    primary_ip="$(config_get_node 'control_plane' 0 'ip')" || {
        log_error "无法获取主控制节点 IP"
        return 1
    }
    exec_script_on_single_node "$primary_ip" "$script_file" "$@"
}

exec_script_on_other_control_planes() {
    local script_file="$1"
    shift
    local primary_ip node_ip
    primary_ip="$(config_get_node 'control_plane' 0 'ip')" || return 1
    while IFS= read -r node_ip; do
        [ -z "$node_ip" ] && continue
        [ "$node_ip" = "$primary_ip" ] && continue
        exec_script_on_single_node "$node_ip" "$script_file" "$@" || return 1
    done < <(get_all_control_plane_ips)
}
```

这里直接复用现有 `config_get_node`、`get_all_control_plane_ips` 和 `exec_script_on_single_node`，保持“主节点一台、其他控制节点排除主节点”的行为。

- [ ] **Step 3: 替换 main.sh 中五个目标错误调用**

以下步骤使用 `exec_script_on_primary_control_plane`：

```text
14-replace-kubeadm
18-init-k8s-cluster
19-modify-cert-expiry
22-install-cni-flannel
```

`20-add-control-nodes` 使用 `exec_script_on_other_control_planes`。

- [ ] **Step 4: 让 dry-run 在任何远程或本地修改前退出**

在完成参数解析和配置校验、进入步骤调度之前增加：

```bash
if [ "$DRY_RUN" = true ]; then
    log_info "Dry-run：仅展示将执行的步骤，不执行 SSH、SCP 或系统修改"
    print_execution_plan
    return 0
fi
```

删除仅打印提示但继续执行的旧逻辑。`print_execution_plan` 必须只读取配置和输出文本。

- [ ] **Step 5: 在 Linux/WSL 运行语法和静态验证**

Run:

```bash
bash -n scripts/main.sh
find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
! rg -n 'exec_script_on_control_plane.*(14-replace|18-init|19-modify|20-add|22-install)' scripts/main.sh
```

Expected: 全部返回 0。

- [ ] **Step 6: 更新公共函数文档并提交**

```bash
git add scripts/lib/exec_script.sh scripts/main.sh doc/api.md
git commit -m "fix(cli): target primary and secondary control planes"
```

## Task 7: 清理换行符和示例敏感信息

**Files:**

- Create: `scripts/ci/check-lf.sh`
- Create: `scripts/ci/check-secrets.sh`
- Modify: `config/cluster.yaml`
- Normalize: 受控 `.sh`、`.yaml`、`.md`、`.py`、`.js`、`.vue`、`.css`、`.html`

- [ ] **Step 1: 写 LF 检查脚本**

```bash
#!/bin/bash

set -euo pipefail

failed=0
while IFS= read -r -d '' file; do
    if LC_ALL=C grep -Iq . "$file" && LC_ALL=C grep -n $'\r' "$file" >/dev/null; then
        printf 'CRLF detected: %s\n' "$file"
        failed=1
    fi
done < <(git ls-files -z '*.sh' '*.yaml' '*.yml' '*.md' '*.py' '*.js' '*.vue' '*.css' '*.html')

exit "$failed"
```

- [ ] **Step 2: 写敏感信息检查脚本**

```bash
#!/bin/bash

set -euo pipefail

if git grep -nE 'BEGIN (RSA |OPENSSH )?PRIVATE KEY|password:[[:space:]]*[^"'\''[:space:]]+' -- \
    ':!scripts/ci/check-secrets.sh'; then
    echo "发现疑似私钥或明文密码"
    exit 1
fi
```

- [ ] **Step 3: 清空示例密码字段**

`config/cluster.yaml` 中密码相关字段统一使用空字符串：

```yaml
password: ""
sudo_password: ""
```

Web v0.1.0 仍只支持私钥认证。

- [ ] **Step 4: 按 `.gitattributes` 重新规范化受控文本**

Run:

```bash
git add --renormalize .
bash scripts/ci/check-lf.sh
bash scripts/ci/check-secrets.sh
```

Expected: 两个检查脚本均返回 0。

- [ ] **Step 5: 验证 Bash 语法**

Run:

```bash
find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

Expected: 返回 0。

- [ ] **Step 6: 提交**

```bash
git add .gitattributes config/cluster.yaml scripts/ci/check-lf.sh scripts/ci/check-secrets.sh
git add --renormalize scripts config doc web README.md AGENTS.md CLAUDE.md
git commit -m "chore: enforce lf and sanitize sample config"
```

## Task 8: 建立持续集成质量门禁

**Files:**

- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: 创建后端、前端和 Shell 三组检查**

```yaml
name: ci

on:
  push:
  pull_request:

jobs:
  backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.7'
      - run: pip install -r web/backend/requirements.txt
      - run: python -m unittest discover -s tests -v
        working-directory: web/backend
      - run: python -m compileall -q kubefoundry tests
        working-directory: web/backend

  frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: npm
          cache-dependency-path: web/frontend/package-lock.json
      - run: npm ci
        working-directory: web/frontend
      - run: npm test
        working-directory: web/frontend
      - run: npm run build
        working-directory: web/frontend

  repository:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
      - run: bash scripts/ci/check-lf.sh
      - run: bash scripts/ci/check-secrets.sh
```

- [ ] **Step 2: 在本地执行等价命令**

Run:

```bash
cd web/backend && python -m unittest discover -s tests -v && python -m compileall -q kubefoundry tests
cd ../../web/frontend && npm ci && npm test && npm run build
cd ../.. && find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
bash scripts/ci/check-lf.sh
bash scripts/ci/check-secrets.sh
```

Expected: 全部返回 0。

- [ ] **Step 3: 提交**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: verify backend frontend and shell"
```

## Task 9: 执行真实环境成功路径与失败路径验收

**Files:**

- Create: `doc/v0.1.0/web-wizard-v0.1.0-acceptance.md`
- Modify: `doc/v0.1.0/web-wizard-v0.1.0-usage.md`

- [ ] **Step 1: 记录测试环境**

验收文档必须写明：

```text
管理节点 OS/Python/Node 版本
控制节点、工作节点、registry 节点的 hostname/IP/OS/arch
Kubernetes 版本
离线安装介质路径和校验值
测试开始和结束时间
Git commit
```

- [ ] **Step 2: 从 Web 页面执行完整成功路径**

操作顺序：

```text
创建集群
添加至少 1 个 control_plane、1 个 worker、1 个 registry
保存 SSH 私钥和路径
执行预检查并确认全部阻塞项通过
执行完整安装计划
观察 SSE、步骤状态和节点日志
等待 web-verify-cluster-health 成功
```

远端验收命令：

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get nodes -o wide
kubectl get pods -A
kubectl get pods -n kube-flannel
```

Expected:

```text
所有节点 Ready
Flannel Pod Running
无非预期 Failed、Error、CrashLoopBackOff Pod
任务、步骤和节点状态均为 success
config_snapshot.json、cluster.yaml、job.log 和节点日志存在
```

- [ ] **Step 3: 执行四类失败路径**

分别执行独立任务验证：

```text
SSH 私钥不可用
安装介质文件缺失
远程 step 返回非零退出码
控制节点或工作节点 join 失败
```

每类失败均断言：

```text
jobs.status=failed
失败 job_steps.status=failed
失败 job_step_nodes.status=failed
后续关键步骤未执行
页面显示失败步骤、节点、退出码和日志
```

- [ ] **Step 4: 验证重复点击和服务重启**

```text
安装运行中再次点击安装，API 返回 409 并跳转已有任务
任务运行中重启后端，原任务被标记 failed
原任务 failure_reason 明确为后端中断
重启后允许重新创建安装任务
```

- [ ] **Step 5: 把实际结果写入验收文档**

文档不能只保留空模板；每项填写 `PASS` 或 `FAIL`、证据命令输出摘要和日志路径。任何 P0 失败都阻止 v0.1.0 发布。

- [ ] **Step 6: 提交**

```bash
git add doc/v0.1.0/web-wizard-v0.1.0-acceptance.md doc/v0.1.0/web-wizard-v0.1.0-usage.md
git commit -m "test(web): record v0.1.0 acceptance"
```

## Task 10: 同步发布文档并完成最终验证

**Files:**

- Modify: `README.md`
- Modify: `doc/v0.1.0/web-wizard-v0.1.0-usage.md`
- Modify: `doc/v0.1.0/web-wizard-v0.1.0-dev-plan.md`
- Modify: `doc/api.md`
- Modify: `doc/v0.1.0/mvp-todolist.md`

- [ ] **Step 1: 更新 README 的 Web Wizard 快速启动**

必须包含：

```bash
cd web/backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
python app.py
```

```bash
cd web/frontend
npm ci
npm run dev
```

并明确 v0.1.0：

```text
仅支持 SSH 私钥认证
安装范围为 Kubernetes Phase 2 + Flannel + 最终健康检查
生态组件配置仅保留，不执行 Phase 3
任务由进程内线程执行，不提供取消、重试或恢复
```

- [ ] **Step 2: 更新 API 文档**

记录：

```text
POST /api/clusters/{cluster_id}/install
202: 创建成功
409: 同一集群已有 pending/running 安装任务，响应包含 job_id
```

记录 `jobs.failure_reason` 和 `web-verify-cluster-health`。

- [ ] **Step 3: 更新里程碑与发布清单状态**

`doc/v0.1.0/web-wizard-v0.1.0-dev-plan.md` 标记已完成里程碑；`doc/v0.1.0/mvp-todolist.md` 只勾选已经由测试或真实环境证据证明完成的条目，不凭代码存在推断通过。

- [ ] **Step 4: 运行最终验证**

Run:

```bash
cd web/backend
python -m unittest discover -s tests -v
python -m compileall -q kubefoundry tests
cd ../frontend
npm ci
npm test
npm run build
cd ../..
find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
bash scripts/ci/check-lf.sh
bash scripts/ci/check-secrets.sh
git diff --check
git status --short
```

Expected:

```text
后端测试全部 PASS
前端测试全部 PASS
前端构建成功
Bash 语法检查成功
LF 和敏感信息检查成功
git diff --check 无输出
git status 仅包含本计划预期修改
```

- [ ] **Step 5: 提交文档**

```bash
git add README.md doc/v0.1.0/web-wizard-v0.1.0-usage.md doc/v0.1.0/web-wizard-v0.1.0-dev-plan.md doc/api.md doc/v0.1.0/mvp-todolist.md
git commit -m "docs: finalize web wizard v0.1.0 release guide"
```

## 需求覆盖矩阵

| 设计要求 | 对应任务 |
|---|---|
| SQLite 保存配置、任务、步骤、节点结果 | 当前基线、Task 1 |
| 任务级 JSON/YAML 快照 | 当前基线、Task 9 |
| Python Step Plan 与节点并发 | 当前基线、Task 2 |
| runtime.env 与 Bash 兼容 | 当前基线、Task 2、Task 9 |
| SSH/权限/OS/CPU/内存/磁盘/swap/hostname/端口预检查 | 当前基线、Task 9 |
| SSE 实时日志和节点日志 | 当前基线、Task 5、Task 9 |
| 安装失败定位 | Task 2、Task 5、Task 9 |
| 安装后 Kubernetes 健康验收 | Task 3、Task 9 |
| 九步 Web 向导 | 当前基线、Task 5 |
| Python 3.7 兼容 | Task 2、Task 8、Task 10 |
| LF 换行 | Task 7、Task 8、Task 10 |
| 文档同步与可部署说明 | Task 9、Task 10 |

## 发布完成定义

只有同时满足以下条件才可发布 v0.1.0：

1. Task 1 至 Task 10 全部完成。
2. CI 的 backend、frontend、repository 三个 job 全部通过。
3. 至少一次全新环境完整安装通过 `web-verify-cluster-health`。
4. 四类失败路径都能在页面定位到失败步骤、失败节点、退出码和日志。
5. 仓库中不存在 CRLF 受控文本、示例明文密码或私钥内容。
6. README、使用文档、API 文档和实际行为一致。
