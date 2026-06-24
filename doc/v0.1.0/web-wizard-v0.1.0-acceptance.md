# KubeFoundry Web Wizard v0.1.0 验收记录

## 1. 验收结论

验收日期：2026-06-20 至 2026-06-21

真实环境 Phase 2 安装通过。最终结果：

- 1 个控制节点和 2 个工作节点全部为 `Ready`。
- Kubernetes 版本均为 `v1.30.14`。
- containerd 版本均为 `1.7.18`。
- Flannel 3 个 DaemonSet Pod 全部为 `Running`。
- kube-system 核心 Pod 全部为 `Running`。
- registry 和 registry UI 容器均为 `Up`。
- 任务快照、YAML、总日志、节点日志和 join 产物均已生成。
- 最终健康检查 job 4 为 `success`。

本次验收同时发现并修复了三个真实环境问题：

1. 并行节点竞争创建步骤日志目录。
2. 目录资源使用 `scp <directory>/.` 分发时被 OpenSSH 拒绝。
3. Flannel 创建后立即执行健康检查，未等待集群收敛。

对应修复提交：

```text
c63060b 修复安装步骤并发目录竞争
268f85d 修复目录资源SCP分发
e249b3c 增加集群健康检查收敛等待
```

## 2. 测试环境

| 角色 | 主机名 | IP | 操作系统 | 架构 |
|---|---|---|---|---|
| control_plane + registry | k8sc1 | 192.168.123.139 | Kylin Linux Advanced Server V10 | x86_64 |
| worker | k8sw1 | 192.168.123.131 | Kylin Linux Advanced Server V10 | x86_64 |
| worker | k8sw2 | 192.168.123.138 | Kylin Linux Advanced Server V10 | x86_64 |

安装参数：

```text
Kubernetes: 1.30.14
Pod CIDR: 10.244.0.0/16
Service CIDR: 10.96.0.0/16
Registry: 192.168.123.139:5000
安装介质: /root/kube-media
管理节点项目目录: /root/KubeFoundry-acceptance-<commit>
验收数据目录: /root/kubefoundry-acceptance-data
验收 SSH 密钥: /root/.ssh/kubefoundry_acceptance
```

## 3. 预检查

真实预检查 job 1 为 `success`。

| 检查项 | 结果 |
|---|---|
| SSH 私钥认证 | 三台通过 |
| root 权限 | 三台通过 |
| 操作系统 | 三台 Kylin Linux Advanced Server |
| CPU | 三台均为 4 核，通过 |
| 内存 | 三台均大于 4 GB，通过 |
| 关键端口 | 三台未占用，通过 |
| Swap | 三台有 warning，安装步骤已关闭 |
| 磁盘 | 控制节点通过；两个 worker 约 9.5 GB 可用，产生 warning |
| Hostname | 初始为 localhost.localdomain，步骤 11b 已修正 |

## 4. 安装任务记录

### job 1：并发目录竞争

```text
10-setup-yum-source: success
11b-setup-hostname: success
12-setup-k8s-repo: 异常中止
```

日志：

```text
安装任务异常: [Errno 17] File exists:
/root/kubefoundry-acceptance-data/jobs/1/logs/12-setup-k8s-repo
```

修复后增加目录幂等创建和 future 异常收敛测试。

### job 2：目录 SCP 分发失败

步骤 12 至 15 成功，步骤 16 三个节点均失败。

日志：

```text
scp: error: unexpected filename: .
```

修复后将具名目录复制到远端父目录，不再使用 `<directory>/.`。

### job 3：Phase 2 主安装闭环

以下步骤均成功：

```text
16-install-containerd
17-install-registry
18-init-k8s-cluster
19-modify-cert-expiry
20-add-control-nodes        无目标节点，成功跳过
21-add-worker-nodes
22-install-cni-flannel
```

首次最终健康检查发生在 Flannel 创建后 0 秒，因节点和 Pod 尚未收敛而失败。修复为最多等待 5 分钟后重新执行。

### job 4：最终健康检查

```text
status: success
step: web-verify-cluster-health
```

健康日志：

```text
k8sc1 Ready control-plane v1.30.14
k8sw1 Ready <none>          v1.30.14
k8sw2 Ready <none>          v1.30.14
cluster health check passed
```

## 5. 最终集群状态

```text
NAME    STATUS   ROLES           VERSION
k8sc1   Ready    control-plane   v1.30.14
k8sw1   Ready    <none>          v1.30.14
k8sw2   Ready    <none>          v1.30.14
```

Flannel：

```text
kube-flannel-ds-46wgf   1/1 Running   k8sw1
kube-flannel-ds-nqbk7   1/1 Running   k8sc1
kube-flannel-ds-q2h2x   1/1 Running   k8sw2
```

registry：

```text
registry:2.8.3                         Up 0.0.0.0:5000->5000
registry-ui                           Up 0.0.0.0:5080->80
```

## 6. 失败路径验收

| 场景 | 结果 | 证据 |
|---|---|---|
| SSH 私钥不可用 | PASS | job 5、step 和 node 均 failed；退出码 255；日志包含私钥不存在和认证失败 |
| 安装介质缺失 | PASS | 安装在创建 job 前被资源校验拒绝；jobs 数量保持 0 |
| 远程执行非零退出 | PASS | job 2 的三个节点均记录 exit_code=1 和独立日志 |
| worker join 失败 | PASS | 隔离 job 6 将 join 命令设为 `false`；job、step 和两个 worker 节点均为 failed，exit_code=1，现有集群未被修改 |

## 7. 任务产物

远端路径：

```text
/root/kubefoundry-acceptance-data/jobs/{job_id}/config_snapshot.json
/root/kubefoundry-acceptance-data/jobs/{job_id}/cluster.yaml
/root/kubefoundry-acceptance-data/jobs/{job_id}/logs/job.log
/root/kubefoundry-acceptance-data/jobs/{job_id}/logs/{step_key}/{hostname}.log
/root/kubefoundry-acceptance-data/jobs/3/artifacts/control_join
/root/kubefoundry-acceptance-data/jobs/3/artifacts/worker_join
```

## 8. 已知限制

- v0.1.0 仅支持 SSH 私钥认证。
- 安装介质必须位于运行后端的 Linux 管理节点本地。
- 任务由进程内线程执行，不支持取消、步骤重试或进程重启后恢复。
- Phase 3 生态组件未接入 Web 安装计划。

## 9. Web 页面自动验收

前端组件测试覆盖：

```text
创建集群、保存 SSH 和路径设置
添加节点
启动预检查
安装任务 409 冲突后绑定现有任务
打开任务历史并恢复预检查结果
打开节点级日志
连接 SSE、事件触发刷新、终态自动断开
Phase 3 生态组件只读提示
```

2026-06-21 本地真实服务链路验证：

```text
GET http://127.0.0.1:5173/                         200
GET http://127.0.0.1:5173/api/health              200
GET http://127.0.0.1:5173/api/clusters            200
GET http://127.0.0.1:5173/api/jobs                200
GET http://127.0.0.1:5173/api/jobs/1/steps        200
GET http://127.0.0.1:5173/api/jobs/1/precheck-results 200
GET http://127.0.0.1:5173/api/job-step-nodes/1/log    200
GET http://127.0.0.1:5173/api/jobs/1/events       200 text/event-stream
```

真实 SSE 响应包含 `job.status` 和 `precheck.result` 事件，节点日志接口返回历史预检查日志。

本次 Codex 应用内浏览器控制插件因运行环境元数据异常无法建立会话，因此未完成视觉截图和人工点击复核；上述结论来自 Vue 组件测试和真实 HTTP 代理链路，不将其表述为人工浏览器验收。
