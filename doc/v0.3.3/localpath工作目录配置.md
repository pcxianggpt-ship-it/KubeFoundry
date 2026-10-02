# localpath 工作目录配置

`localpath` 的标准 BasePath 为 `${KF_K8S_HOME}/openebs-root`。安装介质保存 `__KUBERNETES_WORK_DIR__/openebs-root` 占位符，由 OpenEBS 安装脚本使用当前任务的 `KF_K8S_HOME` 替换后提交；不能将 Shell 变量直接写入已安装 StorageClass，Kubernetes 不会展开该变量。

Worker 准备步骤在每个工作节点执行 `mkdir -p` 创建同一路径。OpenEBS Helm 的本地存储默认路径也使用 `${KF_K8S_HOME}/openebs-root`，更换工作目录后这些配置会同步变化。

玫瑰园先前沿用的 `/data/openesb-root` 已由标准占位符模板替代，当前工作目录 `/data/k8s_install` 对应 `/data/k8s_install/openebs-root`。现场 job12 已完成重置，因此本次同步安装介质，下一次安装时创建 StorageClass，无需操作已绑定卷。

存储组件回归覆盖两个不同的工作目录，检查目录创建、StorageClass 渲染和 Helm 路径的一致性；继续保留显式自定义介质路径的兼容测试。
