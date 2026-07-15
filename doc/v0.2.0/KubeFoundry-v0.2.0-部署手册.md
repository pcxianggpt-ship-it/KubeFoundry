# KubeFoundry v0.2.0 部署手册

## 发布包说明

v0.2.0 发布包按 CPU 架构独立生成：

```text
kubefoundry-web-v0.2.0-x86_64.tar.gz
kubefoundry-web-v0.2.0-aarch64.tar.gz
```

包内包含 Java 17 精简运行时、Spring Boot JAR、Vue 前端、安装步骤脚本、部署脚本和逐文件校验和。目标服务器不需要安装 Java、Python、Node.js、Maven、npm 或 `sshpass`。

## 构建发布包

构建机要求：

- Linux；同架构构建最简单，也支持由本机 JDK 17 的 `jlink` 读取目标架构 JDK 17 的 `jmods` 进行交叉构建。
- JDK 17，必须包含 `jlink`。
- Maven 3.8 或更高版本、Node.js 18 或更高版本、npm、Bash、tar、sha256sum。
- 首次构建允许联网下载 Maven 和 npm 依赖；离线重建前应预热依赖缓存。

执行 x86_64 构建：

```bash
KF_TARGET_ARCH=x86_64 \
KF_JAVA_HOME=/opt/jdk-17 \
bash package.sh
```

执行 ARM64 构建：

```bash
KF_TARGET_ARCH=aarch64 \
KF_JAVA_HOME=/opt/jdk-17 \
bash package.sh
```

已预热 Maven 与 npm 缓存时，可增加 `KF_BUILD_OFFLINE=1`，构建过程将使用 Maven 和 npm 离线模式。脚本会核对 JDK 版本、目标 JDK 和生成的 ELF 架构；不能把 x86 运行时标记为 ARM64。交叉构建 ARM64 时增加 `KF_TARGET_JDK_HOME=/opt/jdk-17-aarch64`，生成后仍必须在真实 ARM64 服务器完成动态验收。

JAR 和前端已经在受控流水线完成测试与构建时，可将平台无关的 `web/backend-java/target/kubefoundry-backend-0.2.0.jar` 和 `web/frontend/dist/` 带到目标架构构建机，增加 `KF_USE_PREBUILT=1`。该模式不访问 Maven 或 npm 仓库，只生成同架构 JRE、复制已验证应用产物并创建校验包。

## 离线部署

先确认服务器架构：

```bash
uname -m
```

`x86_64` 使用 x86_64 包，`aarch64` 使用 aarch64 包。将发布包上传到计划部署目录，例如 `/opt/kubefoundry`：

```bash
mkdir -p /opt/kubefoundry
cd /opt/kubefoundry
tar -xzf kubefoundry-web-v0.2.0-x86_64.tar.gz
cp kubefoundry-web-v0.2.0-x86_64/deploy.sh .
sudo bash deploy.sh kubefoundry-web-v0.2.0-x86_64.tar.gz
```

自定义服务端口：

```bash
sudo bash deploy.sh --port 11001 kubefoundry-web-v0.2.0-x86_64.tar.gz
```

部署脚本会验证压缩包路径安全、`SHA256SUMS` 和 CPU 架构，安装 systemd 服务并等待 `/api/health` 返回成功。

## 目录与数据

以 `/opt/kubefoundry` 为部署目录时：

| 目录 | 内容 | 升级策略 |
|------|------|----------|
| `app/` | 包内 JRE、JAR 和前端 | 每次部署原子替换 |
| `scripts/` | 远端安装步骤 | 每次部署替换 |
| `data/` | H2、主密钥、SSH 私钥、任务数据和日志片段 | 永久保留，权限 `0700` |
| `logs/` | 应用日志和部署日志 | 永久保留，权限 `0700` |

不要删除或复制 `data/secrets/master.key`。节点密码和集群私钥依赖该主密钥解密；丢失后无法恢复已有加密凭据。

## 服务管理

```bash
sudo bash deploy.sh --status
sudo bash deploy.sh --restart
sudo bash deploy.sh --stop
sudo bash deploy.sh --uninstall
```

卸载只删除 systemd 服务，不删除程序、业务数据、密钥和日志。

## 升级与回退

升级前备份 `data/`，然后在原部署目录使用新包再次运行部署命令。脚本会保留数据并替换 `app/` 与 `scripts/`。

需要回退时，使用旧版本同架构发布包重新部署。H2 数据库迁移通常只向前兼容；涉及数据库结构变化时，应先在备份副本验证旧版本能否读取，再执行生产回退。

## 验证与排障

健康检查：

```bash
curl -fsS http://127.0.0.1:10001/api/health
```

检查前端和浏览器路由：

```bash
curl -fsS http://127.0.0.1:10001/
curl -fsS http://127.0.0.1:10001/jobs/1/execution
```

查看服务日志：

```bash
systemctl status kubefoundry-web --no-pager
journalctl -u kubefoundry-web -n 100 --no-pager
tail -n 100 logs/kubefoundry.log
```

常见失败：

- `发布包与服务器架构不匹配`：重新选择与 `uname -m` 一致的发布包。
- `发布包文件校验失败`：文件在传输或存储时损坏，重新上传完整压缩包。
- 主密钥权限错误：确认服务以 root 运行，`data/` 未被不安全权限或其他用户改写。
- 健康检查超时：检查端口占用、`journalctl` 和 `logs/kubefoundry.log`。

## 验收边界

x86_64 与 ARM64 必须分别在真实同架构 Linux 服务器完成启动、H2、Java SSH、前端加载和重启恢复验证。静态解包、校验和或模拟运行时测试不能替代真实架构验收。
