# etcd 备份目录隔离修复

## 1. 问题与原因

2026-10-08，ARM 节点上的 etcd 备份服务在 `etcdctl` 保存快照成功后，报错“etcd 临时快照不存在或不安全”。该节点使用 systemd `243 (v243-67.p05.ky10)`，etcd 数据目录为 `/home/k8s_install/etcd_root`。

服务原先配置 `ProtectHome=true`，导致服务无法访问 `/home` 下的数据目录，即使该目录已列入 `ReadWritePaths`，宿主机检查仍无法找到 Pod 写出的快照。

用户在节点上以相同的 `ProtectSystem=strict` 和 `ReadWritePaths` 执行临时服务对比：`ProtectHome=yes` 时 `stat` 返回 `No such file or directory`，`ProtectHome=read-only` 时目录可见且服务成功退出。该证据确认了目录隔离问题，尚不能据此认定问题仅影响 ARM 架构。

## 2. 修复方案

安装脚本 `scripts/steps/phase3_ecosystem/44-setup-etcd-backup.sh` 生成的服务改用 `ProtectHome=read-only`，保留 `ProtectSystem=strict` 和原有 `ReadWritePaths`。

家目录从不可访问变为只读可见，受管 etcd 数据目录通过现有写入白名单放行。快照生成、完整性检查、SHA-256 校验、原子更名和保留 7 份的流程保持原有行为。

已部署节点可使用以下覆盖配置修复，并执行一次完整备份验证：

```bash
mkdir -p /etc/systemd/system/kubefoundry-etcd-backup.service.d

cat > /etc/systemd/system/kubefoundry-etcd-backup.service.d/protect-home.conf <<'EOF'
[Service]
ProtectHome=read-only
EOF

systemctl daemon-reload
systemctl start kubefoundry-etcd-backup.service
systemctl show kubefoundry-etcd-backup.service -p ProtectHome -p Result
journalctl -u kubefoundry-etcd-backup.service -n 40 --no-pager
```

## 3. 验证与边界

- Bash 语法检查及本地备份回归已通过。回归使用临时根目录下的 `home/k8s_install/etcd_root`，检查生成服务采用只读家目录保护、严格系统保护及准确的数据目录写入白名单，并运行既有备份、保留份数和临时文件清理检查。
- Sol 只读专项复核未发现阻断问题。服务仍以 root 运行，改为只读可见后可读取家目录中的其他文件，读取范围扩大；`NoNewPrivileges`、`PrivateTmp`、严格系统保护及现有写入白名单继续保留。
- 本地测试模拟 `systemctl` 和 `kubectl`，不证明真实 systemd 挂载隔离或 etcd 快照恢复可用性。
- 真实 ARM 节点已完成目录可见性对比，修复后的完整备份尚待复验。成功标准为 `ProtectHome=read-only`、`Result=success`，并出现“etcd 快照已生成并验证”的日志。
