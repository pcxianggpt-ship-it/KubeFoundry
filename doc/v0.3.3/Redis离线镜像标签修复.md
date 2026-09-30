# Redis 离线镜像标签修复

## 原因

安装前的 images.txt 和 Helm values 使用上游多架构 manifest 摘要。镜像经分架构导入或重新推送后，私有仓库即使已有 bitnami/redis:8.10.1，也可能没有该上游摘要，导致预检查返回 404；只改预检查还会使 Pod 按旧摘要拉取失败。

## 修改

Redis 和 Redis Sentinel 的镜像清单、Helm 参数统一使用 registry:5000/bitnami/redis:8.10.1 与 registry:5000/bitnami/redis-sentinel:8.10.1，并显式清空两者 digest，避免 Chart 默认摘要覆盖标签。移除安装脚本对镜像清单的解析和 Registry API 存在性预检查。同时移除本地介质 SHA-256 校验，安装仅检查 Chart 和 values 是否存在，不依赖 images.txt 或 SHA256SUMS。images.txt 保留为导入清单，SHA256SUMS 保留为介质摘要记录。镜像拉取失败由 Kubernetes 和 Helm 等待就绪流程报告。

私有仓库应保持 8.10.1 标签内容不变，且包含目标节点架构的镜像；混合架构集群需要多架构标签。registry:5000 继续使用集群已有的仓库地址解析配置。

## 验证与使用

回归测试将 curl 设置为始终失败，确认安装流程不访问镜像仓库且仍调用 Helm；检查 Redis、Sentinel 版本参数，仅提供 Chart 和 values，并修改本地 values，验证没有镜像清单和摘要文件时仍能执行安装。

更新部署侧的 43-install-redis-sentinel.sh 和 values-sentinel.yaml 后，重新运行 Redis Sentinel 安装步骤。使用发布包安装时，须重新打包并更新部署介质。本次未执行生产集群安装。
