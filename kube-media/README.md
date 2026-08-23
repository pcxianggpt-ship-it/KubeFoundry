# KubeFoundry 离线介质目录

本目录由运维人员独立维护，部署 `v0.3.0` 发布包时不会被打包、复制或覆盖。请将 Kubernetes RPM 仓库包、容器运行时、镜像介质以及 Kubemate 组件所需的 Chart、YAML 放入目标管理端的 `${APP_DIR}/kube-media`。

发布包仅携带运行时必需的双架构 Helm 二进制：`${APP_DIR}/tools/helm-amd` 与 `${APP_DIR}/tools/helm-arm`。组件安装时，系统会按主控制节点架构选择对应文件，校验 SHA-256 后分发到主控制节点，再在该节点使用 `kubectl` 或 Helm 执行操作。

预检查会按当前节点架构和启用组件校验实际介质；本说明文件不构成可安装介质。

Kubernetes RPM 仓库包还必须包含 [YUM 仓库安装包清单](./yum-required-packages.txt) 中的软件。重新制作离线仓库后，应确认这些包及其依赖能通过 `k8s-yum` 仓库安装；仓库步骤不依赖 `sshpass`、ACL 或 SELinux 管理工具。节点密码首连和密钥分发由 Web 节点测试中的 Java SSH 完成。
