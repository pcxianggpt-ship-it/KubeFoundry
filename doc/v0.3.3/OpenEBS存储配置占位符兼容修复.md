# OpenEBS 存储配置占位符兼容修复

## 原因

47-install-openebs.sh 原先要求 openebssc.yaml 必须包含 __KUBERNETES_WORK_DIR__。介质中的 StorageClass 已经渲染为实际路径或使用自定义路径时，会被误判为缺少占位符，在执行 kubectl apply 和 Helm 安装前退出。

## 修改

StorageClass 包含占位符时，继续替换为 KF_K8S_HOME；不含占位符时，记录日志并按原配置提交，由 Kubernetes 校验清单。两种情况都通过临时文件安装，保留原介质文件不变。

Helm 管理的 OpenEBS hostpath 路径继续使用 KF_K8S_HOME/openebs-root；额外的 local-hostpath StorageClass 可保留自己的自定义路径。显式路径对应的节点目录由使用者按配置准备。

## 验证与部署

存储组件回归测试覆盖占位符替换、显式路径安装及重复安装，校验提交清单和原文件的路径未被覆盖。保留 Kubernetes 工作目录的原有合法性检查。

部署时更新 scripts/steps/phase3_ecosystem/47-install-openebs.sh 即可，无需为了满足脚本检查而修改已有 StorageClass 介质。初次连接 amar 管理节点超时；后续于 2026-10-01 在玫瑰园集群完成安装和验证，详细结果见《玫瑰园job4故障修复与验收》。额外的 local-hostpath 模板不再标记为默认类，避免覆盖既有默认存储选择。

后续 Redis 本地存储整改将额外模板名称改为 `localpath`，仍保留非默认类和自定义路径兼容；详见《Redis命名与本地存储整改》。
