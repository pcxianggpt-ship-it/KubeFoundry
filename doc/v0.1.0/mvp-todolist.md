# KubeFoundry MVP TODO List

更新时间：2026-06-20

## 1. 当前结论

当前版本已经具备 Web Wizard MVP 的主要代码骨架：

- 集群、节点、SSH 私钥和路径配置可以保存到 SQLite。
- 可以生成 `cluster.yaml`、任务快照和 `runtime.env`。
- 预检查、SSE 日志、任务历史和节点日志接口已经实现。
- Python Step Plan 已覆盖 Phase 2 的 13 个核心步骤，即 `10-setup-yum-source` 至 `22-install-cni-flannel`。
- 后端现有 10 个单元测试全部通过。

但当前版本仍不建议直接标记为可发布 MVP。以下 P0 项全部完成，并通过真实环境安装验收后，才满足“Kubernetes 集群 + Flannel 一键安装”的最低发布条件。

## 2. P0：MVP 发布阻塞项

- [ ] 修复前端生产构建
  - 当前执行 `npm run build` 时，Vite/Rollup 报错：输出资源名收到 Windows 绝对路径 `D:/code/KubeFoundry/web/frontend/index.html`。
  - 检查 `vite.config.js`、Vite root、工作目录和 Windows 路径处理。
  - 验收：在 Windows 开发环境和目标 Linux 构建环境执行 `npm ci && npm run build` 均成功。

- [ ] 统一工作区文本文件为 LF
  - 当前仍为 CRLF 的受控文件：
    - `scripts/lib/config.sh`
    - `scripts/lib/exec_script.sh`
    - `scripts/lib/tools.sh`
    - `scripts/verify/phase3_ecosystem/verify-41-setup-kubectl-permission.sh`
    - `doc/addstep.md`
    - `doc/cmdlist.md`
    - `doc/manual-ops.md`
    - `doc/v0.1.0/web-wizard-v0.1.0-design.md`
  - `.gitattributes` 已声明 LF，但现有工作区尚未重新规范化。
  - 验收：CRLF 扫描结果为空，所有 Bash 脚本在 Linux 下通过 `bash -n`。

- [ ] 修复 CLI 控制节点目标范围
  - `scripts/main.sh` 仍使用 `exec_script_on_control_plane` 执行只应作用于主控制节点的步骤：
    - `14-replace-kubeadm`
    - `18-init-k8s-cluster`
    - `19-modify-cert-expiry`
    - `22-install-cni-flannel`
  - `20-add-control-nodes` 还需要明确排除主控制节点。
  - 建议增加 `exec_script_on_primary_control_plane` 和 `exec_script_on_other_control_planes`。
  - 验收：三控制节点场景中只有第一台执行 init，其他控制节点仅执行 join。

- [ ] 完成真实环境端到端安装验收
  - 至少准备 1 个控制节点、1 个工作节点和可用 registry 节点。
  - 使用真实离线安装介质从 Web 页面执行完整 Phase 2。
  - 验收：
    - 所有任务步骤为 `success`。
    - `kubectl get nodes` 中所有节点为 `Ready`。
    - Flannel Pod 全部为 `Running`。
    - `kubectl get pods -A` 无非预期失败项。
    - 任务快照、步骤状态、节点日志和 SSE 日志完整可查。

- [ ] 增加安装失败路径验收
  - 分别模拟 SSH 失败、介质缺失、远程脚本非零退出和 join 失败。
  - 验收：任务停止在正确步骤，`jobs`、`job_steps`、`job_step_nodes` 状态一致，并能从页面定位失败节点和日志。

- [ ] 移除示例配置中的明文密码
  - `config/cluster.yaml` 当前包含真实格式的 SSH 明文密码。
  - 改为空值或明显占位符，并确认 Web 后端继续只接受私钥认证。
  - 验收：仓库及提交历史检查中不再包含有效凭据。

## 3. P1：MVP 稳定性与可维护性

- [ ] 为安装编排器补充单元测试
  - Mock SSH/SCP，覆盖串行执行、节点并发、资源分发、产物收集、验证命令和失败中止。
  - 覆盖 `18 -> 20/21` join 产物依赖。
  - 当前测试主要覆盖 API、配置、Step Plan 和资源校验，尚未真正覆盖 runner 执行链。

- [ ] 增加前端自动化测试
  - 至少覆盖创建集群、添加节点、保存设置、启动预检查、启动安装和查看节点日志。
  - 增加一条生产构建测试，防止 Windows 路径问题回归。

- [ ] 完善 CI 检查
  - 后端：Python 3.7 单元测试和 `compileall`。
  - 前端：`npm ci` 和 `npm run build`。
  - Bash：全量 `bash -n`。
  - 文件：LF、敏感信息和 YAML 格式检查。

- [ ] 修复或移除无效的 CLI `--dry-run`
  - 当前参数只输出提示，后续仍会执行真实操作。
  - 验收：dry-run 模式不得执行 SSH、SCP、文件修改或服务操作。

- [ ] 防止同一集群并发创建多个安装任务
  - 创建 install job 前检查是否已有 `pending` 或 `running` 任务。
  - 验收：重复点击安装不会产生两个并行修改同一批节点的任务。

- [ ] 处理服务重启后的运行中任务
  - 当前任务由进程内 daemon thread 执行，后端重启会留下 `running` 状态。
  - MVP 可先在启动时将遗留任务标记为 `failed/interrupted`。
  - 验收：后端重启后不存在永久卡住的运行中任务。

- [ ] 对齐生态组件页面与实际执行范围
  - 前端可以选择生态组件，但当前 Python Step Plan 只执行 Phase 2。
  - MVP 二选一：
    - 暂时隐藏或明确标记生态组件为“后续版本”。
    - 接入已承诺的 Phase 3 步骤并补充验收。
  - 验收：页面展示的选项不会让用户误以为当前安装任务会执行未接入步骤。

- [ ] 补充最终集群健康验证
  - 当前步骤验证主要是单步命令检查。
  - 增加安装结束后的节点 Ready、系统 Pod、Flannel 和 API Server 综合验证。

## 4. P2：发布后增强项

- [ ] 支持任务取消、步骤重试和失败后恢复。
- [ ] 实现完整自动回滚，或删除当前未生效的 `auto_rollback` 配置。
- [ ] 增加安装任务超时控制，实际使用 `advanced.install_timeout`。
- [ ] 支持密码或 sudo 场景时，设计安全的临时凭据方案。
- [ ] 增加 SQLite schema migration 机制和数据库备份说明。
- [ ] 增加生产部署方式，包括静态前端托管、后端进程管理和日志轮转。
- [ ] 接入 Phase 3 生态组件安装与验证。
- [ ] 增加 ARM64、不同操作系统和多控制节点测试矩阵。

## 5. 文档同步项

- [ ] 更新根目录 `README.md`，加入 Web Wizard 的启动方式、范围和限制。
- [ ] 在使用文档中明确 MVP 仅支持 SSH 私钥认证。
- [ ] 记录支持的操作系统、Kubernetes 版本、架构和安装介质目录结构。
- [ ] 增加真实安装验收记录，包括环境信息、执行时间、结果和已知问题。
- [ ] 对齐 `doc/design.md`、Web 设计文档和当前 Python Step Plan，删除过时描述。

## 6. 本次检查记录

| 检查项 | 结果 |
|---|---|
| Git 工作区 | 干净 |
| Python 3.7 后端测试 | 10 项全部通过 |
| Phase 2 Step Plan | 13 个核心步骤已接入 |
| 前端生产构建 | 失败，Windows 绝对路径导致 Rollup 报错 |
| LF 检查 | 8 个受控文本文件仍为 CRLF |
| 前端测试 | 未发现测试文件 |
| 真实集群安装 | 本次未执行，仍需专项验收 |
| Bash 全量语法检查 | 当前环境无可用 Linux/WSL Bash，需在 Linux CI 或部署机补跑 |

## 7. MVP 完成定义

只有同时满足以下条件，才能将当前版本标记为 MVP 完成：

1. P0 项全部关闭。
2. 后端测试、前端构建、Bash 语法和 LF 检查全部通过。
3. 至少完成一次全新环境安装和一次失败路径验证。
4. Web 页面能够创建配置、执行预检查、完成 Phase 2 安装并展示可定位的日志。
5. 最终 Kubernetes 节点全部 Ready，Flannel 和核心系统 Pod 正常运行。
