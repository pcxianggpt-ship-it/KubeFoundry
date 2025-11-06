# Kubernetes 自动部署系统需求文档

## 一、项目概述

本项目旨在开发一套 **基于离线环境的 Kubernetes 自动化部署系统**，由控制节点统一调度，自动完成从环境准备到集群初始化、节点加入、插件安装、组件部署及备份任务配置的全流程操作。
 目标是：

- **一键式安装**：在上传好安装介质后，只需执行主脚本即可完成部署。
- **幂等执行**：脚本可重复执行，跳过已完成步骤。
- **安全可控**：每一步都进行验证，失败立即停止。
- **离线可用**：所有依赖、镜像、rpm 均来自本地介质，无需外网。

------

## 二、总体架构设计

### 2.1 执行模型

- 采用 **中心控制节点（Controller）推送执行** 的模式。
- 控制节点负责：
  - 分发安装介质至各目标节点；
  - 调用远程执行脚本；
  - 收集结果、验证状态；
  - 生成日志与状态报告。
- 目标节点执行：
  - 接收并校验介质；
  - 执行指定安装步骤；
  - 反馈结果与状态。

### 2.2 系统角色

| 角色                   | 描述                                                      |
| ---------------------- | --------------------------------------------------------- |
| 控制节点（Controller） | 上传介质并执行主控制脚本的节点，通常为部署机。            |
| 控制平面节点（Master） | 运行 etcd、API Server、Controller、Scheduler 等核心组件。 |
| 工作节点（Worker）     | 运行业务 Pod，加入集群。                                  |
| 存储节点（可选）       | 提供 NFS 存储或 NAS 服务。                                |

------

## 三、安装流程与模块说明

完整安装流程如下：

1. **检查是否为 root 用户**
   - 确保脚本以 root 权限执行，否则终止。
2. **服务器间免密登录配置**
   - 控制节点生成 SSH key 或使用用户提供的 key；
   - 将公钥分发至所有目标节点；
   - 验证可无密码登录。
3. **依赖检查与安装（离线 rpm）**
   - 检查所需命令与包（如 `curl`, `iptables`, `conntrack`, `socat`, `ipset` 等）；
   - 使用本地 rpm 包安装缺失依赖；
   - 验证安装结果。
4. **替换 kubeadm / kubelet / kubectl 文件**
   - 分发指定版本的 rpm 或二进制；
   - 校验版本号；
   - 更新 systemd 配置并重载。
5. **配置系统参数**
   - 关闭 swap、禁用 SELinux、防火墙；
   - 设置 sysctl 参数；
   - 加载必要内核模块（`br_netfilter`, `overlay` 等）；
   - 验证系统参数正确。
6. **安装容器运行时（Docker / containerd）**
   - 根据 Kubernetes 版本自动判断容器运行时类型：
     - K8s 1.23 版本：安装 Docker CE
     - K8s 1.30 版本：安装 containerd
   - 离线安装对应 rpm 包；
   - 分发配置文件（镜像加速、私服、cgroup）；
   - 启动并验证运行状态。
7. **安装镜像仓库（Registry / Harbor）**
   - 部署离线私有仓库；
   - 导入基础镜像；
   - 验证可拉取与访问。
8. **初始化 Kubernetes 集群（kubeadm init）**
   - 使用配置文件初始化；
   - 保存 join token；
   - 验证控制平面 Pod 状态。
9. **配置 kube-controller-manager 参数**
   - 备份原始 `/etc/kubernetes/manifests/kube-controller-manager.yaml` 配置文件；
   - 修改 Pod 清单，在 `spec.containers[0].command` 最后一行添加固定参数：
     ```yaml
     - --cluster-signing-duration=867240h0m0s
     ```
   - kubelet 自动重启 Pod 以应用新配置；
   - 验证 Pod 状态和参数加载情况。
10. **添加控制平面节点**
    - 分发 join 命令；
    - 验证 etcd 成员与节点状态。
11. **添加工作节点**
    - 执行 join；
    - 验证节点 `Ready` 状态。
12. **安装 CNI 插件（Flannel）**
    - 使用用户提供的 YAML；
    - 替换变量；
    - 验证网络连通性与 Pod 状态。
13. **安装 NFS Client Provisioner**
    - 替换 NFS 配置；
    - 使用helm安装
    - 部署并验证 PVC 自动创建。
14. **安装定制化组件**
    - Traefik、Prometheus、Redis 等；
    - 脚本仅负责替换配置并 apply；
    - 验证关键 Pod 状态与健康。
15. **配置 etcd 定时备份任务**
    - 部署备份脚本；
    - 写入 crontab；
    - 测试一次快照保存；
    - 验证快照有效性。

------

## 四、系统特性与要求

### 4.1 验证机制

- 每一步执行后立即验证结果；
- 验证失败则：
  - 停止后续流程；
  - 记录日志；
  - 输出错误提示。

### 4.2 幂等性要求

- 每个步骤仅在必要时执行；

- 使用状态文件记录执行状态：

  ```
  /var/lib/k8s-autodeploy/state/<step>.done
  ```

- 重复执行时自动跳过已完成步骤。

### 4.3 离线分发机制

- 所有介质上传至控制节点；
- 使用 rsync/scp 分发；
- 校验 sha256sum；
- 校验失败自动重传。

### 4.4 配置参数管理

- 使用统一配置文件（YAML 格式），定义所有环境参数：

```
global:
  # K8s 安装根目录，默认为 /data
  k8s_install_dir: /data
  # 离线安装介质存放目录，默认为 /data/k8s_install
  media_source: /data/k8s_install
  nas_mount: /mnt/nas/k8s
  timezone: Asia/Shanghai
  # 系统架构，默认为 x86_64，可选值：x86_64, arm64
  architecture: x86_64

hosts:
  control_plane:
    - ip: 192.168.1.11
      hostname: master1
    - ip: 192.168.1.12
      hostname: master2
  workers:
    - ip: 192.168.1.21
      hostname: node1

packages:
  # 容器运行时将根据 K8s 版本自动选择：
  # - kube_version 1.23.x -> container_runtime: docker
  # - kube_version 1.30.x -> container_runtime: containerd
  container_runtime: auto  # 可选值：auto, docker, containerd
  kube_version: 1.30.14

  # 版本映射关系（系统自动判断，无需手动配置）
  runtime_version_mapping:
    "1.23": "docker"
    "1.30": "containerd"

registry:
  enabled: true
  host: registry.local
  port: 5000

nfs:
  server: 10.0.0.5
  path: /export/k8s

addons: [traefik, prometheus, redis]

etcd_backup:
  schedule: "0 2 * * *"
  # etcd 备份路径，默认为 /data/nfs_root/etcdbackup
  backup_path: /data/nfs_root/etcdbackup
```

------

## 五、日志与回滚机制

### 5.1 日志规范

- 每步执行日志：

  ```
  /var/log/k8s-autodeploy/<timestamp>-<step>.log
  ```

- 所有节点日志可汇总到控制节点。

- 执行结果生成汇总报告（success / failed）。

### 5.2 回滚策略

- 每步执行前自动备份配置文件与关键目录；

- 若失败，可执行：

  ```
  deploy.sh cleanup --step <step>
  ```

- 重大错误可调用 `kubeadm reset` 进行集群清理。

------

## 六、接口与命令设计

| 命令                                   | 功能                       |
| -------------------------------------- | -------------------------- |
| `deploy.sh apply --config deploy.yaml` | 按流程执行完整安装         |
| `deploy.sh retry --step <step>`        | 重新执行指定步骤           |
| `deploy.sh dry-run`                    | 演练模式（仅打印执行计划） |
| `deploy.sh cleanup`                    | 清理安装痕迹               |
| `deploy.sh status`                     | 查看已完成步骤状态         |

------

## 七、验证与测试

### 7.1 安装验证

- 检查节点状态：

  ```
  kubectl get nodes
  ```

- 检查系统组件：

  ```
  kubectl get pods -n kube-system
  ```

- 检查网络插件：

  ```
  kubectl get ds -n kube-system
  ```

### 7.2 Smoke Test

- 部署 busybox 测试 Pod；
- 创建 PVC 验证存储；
- 检查 Prometheus/Traefik 服务是否可访问。

------

## 八、安全与凭证管理

- 所有 SSH key、token、证书统一存放：

  ```
  /root/.k8s-autodeploy/creds/
  ```

  权限：`600`

- 日志中不输出敏感内容；

- Token 自动过期或轮换。

------

## 九、扩展与后续计划

| 功能               | 说明                               |
| ------------------ | ---------------------------------- |
| Web UI / CLI 监控  | 未来可增加部署状态可视化界面       |
| 模块化插件机制     | 每个安装模块独立可插拔             |
| 断点续传与并发优化 | 提升大规模节点部署速度             |
| 集群升级 / 扩容    | 后续扩展支持版本升级和节点自动扩容 |

------

## 十、交付内容

| 类型       | 文件                         | 描述               |
| ---------- | ---------------------------- | ------------------ |
| 主控制脚本 | `controller.sh`              | 控制节点运行入口   |
| 执行脚本   | `executor.sh`                | 节点执行器         |
| 分发工具   | `distribute.sh`              | 分发介质与文件     |
| 配置模板   | `deploy-config.yaml.example` | 参数模板           |
| 校验清单   | `manifest.json`              | 包与镜像校验信息   |
| 备份脚本   | `etcd-backup.sh`             | etcd 备份与恢复    |
| 文档       | `README.md` / `需求文档.md`  | 使用说明与部署流程 |

------

## 十一、非功能性需求

| 项目            | 要求                                       |
| --------------- | ------------------------------------------ |
| 操作系统兼容性  | 支持 RHEL/CentOS/AlmaLinux/Oracle Linux 8+ |
| Kubernetes 版本 | 支持 1.23 和 1.30                          |
| 系统架构        | 支持 x86_64 和 arm64                       |
| 安全性          | 所有 SSH、Token 不明文存储                 |
| 并发性能        | 50+ 节点可在30分钟内部署完成               |
| 可维护性        | 结构模块化、脚本可单独重用                 |
| 日志可追溯性    | 每步记录执行时间、结果与错误信息           |

------

## 十二、结语

该自动化部署系统将实现：

- 完整离线环境下的 Kubernetes 集群自动化安装；
- 可靠的错误检测与幂等执行；
- 可扩展的组件与配置管理机制；
- 一键式可重复部署能力。