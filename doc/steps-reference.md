# KubeFoundry 脚本说明文档

## Description

本文档是 KubeFoundry 项目的核心参考文档，详细说明了 Kubernetes 自动化部署过程中所有 33 个步骤脚本的功能、执行位置、依赖关系和参数需求。

**文档用途：**
- 快速查找每个脚本的功能和作用
- 了解脚本执行的正确节点和顺序
- 查看脚本所需的配置参数及其来源
- 理解脚本之间的依赖关系
- 作为开发和调试的参考手册

**文档结构：**
- 按三个阶段组织（前置检查、K8S底座、生态组件）
- 每个脚本包含：功能描述、执行机器、批量执行函数、依赖关系、所需参数
- 提供执行顺序总览和关键节点说明
- 包含注意事项和使用提示

**使用说明：**
1. 按顺序执行脚本，严格遵循依赖关系
2. 在正确的节点上执行对应的脚本
3. 根据配置参数说明准备 `config/cluster.yaml`
4. 遇到问题时参考此文档的脚本说明

**适用对象：**
- 系统管理员：用于了解部署流程
- 开发人员：用于理解脚本逻辑和参数需求
- 运维人员：用于故障排查和维护参考

---

## 文档元信息

- **生成时间：** 2026-03-26
- **更新时间：** 2026-03-27
- **脚本总数：** 33个
- **项目路径：** `D:\code\KubeFoundry`
- **相关文档：** [cmdlist.md](./cmdlist.md) - 原始命令清单<br>**重要：** [api.md](./api.md) - 批量执行函数接口定义

---

## 目录

- [阶段1：前置检查与准备](#阶段1前置检查与准备)
- [阶段2：K8S底座安装](#阶段2k8s底座安装)
- [阶段3：Kubemate及生态组件](#阶段3kubemate及生态组件)
- [执行顺序总览](#执行顺序总览)
- [关键节点说明](#关键节点说明)
- [注意事项](#注意事项)

---

## 阶段1：前置检查与准备

本阶段包含3个脚本，主要用于环境检查、配置文件加载和验证，所有脚本均在**管理节点（本地）**执行。

### 01-check-tools.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 2.3 检查必要工具安装 |
| **脚本路径** | `scripts/steps/phase1_precheck/01-check-tools.sh` |
| **执行机器** | 管理节点（本地执行） |
| **批量执行函数** | 无需远程执行，本地直接运行脚本 |
| **依赖关系** | 无前置依赖 |
| **主要功能** | 检查本地必要工具（ssh、scp、rsync、yaml、jq、bc）、检查配置文件中指定的工具路径（如 helm）、检查 SSH 连接到所有节点的连通性、生成前置检查报告 |
| **检查清单** | ssh、scp、rsync、yaml、jq、bc、helm（可选）、SSH 连通性 |
| **所需参数** | 所有节点 IP、ssh.user、ssh.port、ssh.timeout<br>（来源：config.control_plane[].ip、config.workers[].ip、config.ssh.*） |

---

### 02-init-config.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 2.1 初始化参数配置 |
| **脚本路径** | `scripts/steps/phase1_precheck/02-init-config.sh` |
| **执行机器** | 管理节点（本地执行） |
| **批量执行函数** | 无需远程执行，本地直接运行脚本 |
| **依赖关系** | 依赖 01-check-tools.sh |
| **主要功能** | 加载 `config/config.yaml` 配置文件<br>解析 YAML 格式的配置参数<br>验证配置文件格式<br>初始化全局变量（K8S版本、网络参数等）<br>显示配置摘要（K8S版本、Pod网段、Service网段、节点数量） |
| **关键输出** | K8S 版本、Pod 网段、Service 网段、控制节点数量、工作节点数量 |
| **所需参数** | cluster.k8s_version、cluster.pod_subnet、cluster.service_subnet、cluster.name、control_plane[].hostname、control_plane[].ip、workers[].hostname、workers[].ip、paths.k8s_install<br>（来源：config.cluster.*、config.control_plane[]、config.workers[]、config.paths.k8s_install） |

---

### 03-validate-config.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 2.2 检查配置文件完整性 |
| **脚本路径** | `scripts/steps/phase1_precheck/03-validate-config.sh` |
| **执行机器** | 管理节点（本地执行） |
| **批量执行函数** | 无需远程执行，本地直接运行脚本 |
| **依赖关系** | 依赖 02-init-config.sh |
| **主要功能** | 检查配置文件是否存在、验证必需配置项、验证所有节点 IP 地址格式（IPv4）、验证 API Server 端口号有效性、验证文件路径可访问性（如 YUM 源文件）、生成验证报告 |
| **验证内容** | IP 地址格式、端口号范围、文件路径存在性 |
| **所需参数** | 所有节点 IP、network.api_server_port、paths.repo_source、paths.kubeadm_100y、paths.container_runtime、paths.registry_install<br>（来源：config.control_plane[].ip、config.workers[].ip、config.network.*、config.paths.*） |

---

## 阶段2：K8S底座安装

本阶段包含13个脚本，用于安装 Kubernetes 核心组件和配置运行环境。

### 10-setup-yum-source.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.1 配置本地yum源 |
| **脚本路径** | `scripts/steps/phase2_k8s_base/10-setup-yum-source.sh` |
| **执行机器** | 管理节点（本地执行） |
| **批量执行函数** | 无需远程执行，本地直接运行脚本 |
| **依赖关系** | 无前置依赖 |
| **主要功能** | 验证 YUM 源文件是否存在、解压 YUM 源到 `/var/www/html/`、添加 `.repo` 文件配置、刷新 YUM 缓存、验证 k8s yum 源（搜索 kubelet）、安装 httpd 服务并设置开机自启、关闭防火墙 |
| **关键服务** | httpd（YUM 源 HTTP 服务）、firewalld（已关闭） |
| **所需参数** | paths.repo_source、registry.ip、control_plane[0].ip、control_plane[0].hostname<br>（来源：config.paths.repo_source、config.registry.*、config.control_plane[0].*） |

---

### 11-setup-ssh-login.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.2 配置SSH免密登录 |
| **脚本路径** | `scripts/steps/phase2_k8s_base/11-setup-ssh-login.sh` |
| **执行机器** | 管理节点 |
| **批量执行函数** | 无需远程执行，本地直接运行脚本 |
| **依赖关系** | 可选步骤，无强制依赖 |
| **主要功能** | 生成 SSH 密钥对、复制公钥到所有节点、验证免密登录 |
| **执行方式** | 手动执行，可选 |
| **所需参数** | ssh.user、ssh.key_path、ssh.port、所有节点 IP<br>（来源：config.ssh.*、config.control_plane[].ip、config.workers[].ip） |

---

### 12-setup-k8s-repo.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.3 配置本地k8s repo源客户端 |
| **脚本路径** | `scripts/steps/phase2_k8s_base/12-setup-k8s-repo.sh` |
| **执行机器** | 除 k8sc1 外，所有服务器 |
| **批量执行函数** | `exec_remote_script "control_plane" "scripts/steps/phase2_k8s_base/12-setup-k8s-repo.sh"`（在控制节点k8sc2、k8sc3）<br>`exec_remote_script "workers" "scripts/steps/phase2_k8s_base/12-setup-k8s-repo.sh"`（在所有工作节点）<br>注意：不包括 k8sc1 |
| **依赖关系** | 依赖 10-setup-yum-source.sh |
| **主要功能** | 添加 `k8s-http.repo` 配置文件指向 `http://k8sc1/repo`、刷新 YUM 缓存 |
| **配置内容** | baseurl: `http://k8sc1/repo`、gpgcheck: 0 |
| **所需参数** | control_plane[0].ip、control_plane[0].hostname、所有节点 IP<br>（来源：config.control_plane[0].*、config.control_plane[].ip、config.workers[].ip） |

---

### 13-install-k8s-deps.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.4 安装K8s依赖包 |
| **脚本路径** | `scripts/steps/phase2_k8s_base/13-install-k8s-deps.sh` |
| **执行机器** | 所有控制平面和所有工作节点 |
| **批量执行函数** | `exec_script_on_control_plane "scripts/steps/phase2_k8s_base/13-install-k8s-deps.sh"`（控制节点）<br>`exec_script_on_workers "scripts/steps/phase2_k8s_base/13-install-k8s-deps.sh"`（工作节点） |
| **依赖关系** | 依赖 12-setup-k8s-repo.sh |
| **主要功能** | 安装 K8S 依赖包 |
| **安装组件** | cri-tools、kubeadm、kubectl、kubelet、kubernetes-cni、nfs |
| **所需参数** | 所有节点 IP<br>（来源：config.control_plane[].ip、config.workers[].ip） |

---

### 14-replace-kubeadm.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.5 替换kubeadm为支持100年证书版本 |
| **脚本路径** | `scripts/steps/phase2_k8s_base/14-replace-kubeadm.sh` |
| **执行机器** | 仅在 k8sc1 上执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase2_k8s_base/14-replace-kubeadm.sh"` |
| **依赖关系** | 依赖 13-install-k8s-deps.sh |
| **主要功能** | 备份原始 kubeadm 到 `/tmp/k8s/kubeadm_bak`、从指定路径复制支持 100 年证书的 kubeadm 二进制文件到 `/usr/bin/kubeadm` |
| **关键参数** | 证书有效期：100 年（867240h0m0s） |
| **所需参数** | cluster.k8s_version、paths.kubeadm_100y、paths.k8s_install、control_plane[0].ip<br>（来源：config.cluster.k8s_version、config.paths.*、config.control_plane[0].ip） |

---

### 15-environment-config.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.6 环境配置 |
| **脚本路径** | `scripts/steps/phase2_k8s_base/15-environment-config.sh` |
| **执行机器** | 所有节点执行 |
| **批量执行函数** | `exec_script_on_all_nodes "scripts/steps/phase2_k8s_base/15-environment-config.sh"` |
| **依赖关系** | 依赖 13-install-k8s-deps.sh |
| **主要功能** | 关闭 swap（临时和永久）、关闭防火墙并禁用、卸载 podman 等容器、配置 DNS（8.8.8.8）、加载 overlay 和 br_netfilter 内核模块、修改 sysctl.conf 配置 IPv4/IPv6 转发、配置 systemd-resolved、修改 open files 参数为 65535 |
| **关键配置** | net.ipv4.ip_forward=1、net.bridge.bridge-nf-call-iptables=1、net.ipv6.conf.all.forwarding=1 |
| **所需参数** | env.kubelet_root、所有节点 IP<br>（来源：config.env.kubelet_root、config.control_plane[].ip、config.workers[].ip） |

---

### 16-install-containerd.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.7 安装containerd |
| **脚本路径** | `scripts/steps/phase2_k8s_base/16-install-containerd.sh` |
| **执行机器** | 所有节点执行 |
| **批量执行函数** | `exec_script_on_all_nodes "scripts/steps/phase2_k8s_base/16-install-containerd.sh"` |
| **依赖关系** | 依赖 15-environment-config.sh |
| **主要功能** | 解压并安装 containerd 1.7.18、安装 runc 1.3.3、安装 cni-plugins 1.8.0、配置 containerd 服务、安装 buildkit 0.25.2 并启动服务、安装 nerdctl 2.2.0、配置镜像仓库地址（支持变量和域名两种方式）、启动 containerd 服务 |
| **关键组件** | containerd: 1.7.18、runc: 1.3.3、cni-plugins: 1.8.0、buildkit: 0.25.2、nerdctl: 2.2.0 |
| **所需参数** | paths.container_runtime、registry.hostname、registry.port、所有节点 IP<br>（来源：config.paths.container_runtime、config.registry.*、config.control_plane[].ip、config.workers[].ip） |

---

### 17-install-registry.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.8 安装镜像仓库 |
| **脚本路径** | `scripts/steps/phase2_k8s_base/17-install-registry.sh` |
| **执行机器** | 镜像仓库节点（registry，通常为 k8sc3） |
| **批量执行函数** | `exec_script_on_registry "scripts/steps/phase2_k8s_base/17-install-registry.sh"` |
| **依赖关系** | 无强制依赖，建议在 containerd 安装后执行 |
| **主要功能** | 调用 registry 安装脚本，指定镜像仓库 IP 地址 |
| **所需参数** | registry.ip、paths.registry_install、control_plane[2].ip<br>（来源：config.registry.ip、config.paths.registry_install、config.control_plane[2].ip，通常为 k8sc3） |

---

### 18-init-k8s-cluster.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.9.1 初始化K8S集群 |
| **脚本路径** | `scripts/steps/phase2_k8s_base/18-init-k8s-cluster.sh` |
| **执行机器** | 仅在 k8sc1（第一个控制节点）上执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase2_k8s_base/18-init-k8s-cluster.sh"` |
| **依赖关系** | 依赖 14-replace-kubeadm.sh 和 16-install-containerd.sh |
| **主要功能** | 编辑 cluster.yaml 配置文件（控制平面地址、本机IP、Pod网段、Service网段）、配置 kubelet 路径（`--root-dir=/data/kubelet_root`）、使用 kubeadm init 初始化集群、配置 kubectl（复制 admin.conf 到 `~/.kube/config`）、记录 kubeadm join 命令供后续添加节点使用 |
| **关键输出** | kubeadm join 控制节点命令（包含 --control-plane 参数）、kubeadm join 工作节点命令 |
| **所需参数** | cluster.name、cluster.pod_subnet、cluster.service_subnet、control_plane[0].ip、control_plane[0].hostname、network.api_server_port、env.kubelet_root<br>（来源：config.cluster.*、config.control_plane[0].*、config.network.api_server_port、config.env.kubelet_root） |

---

### 19-modify-cert-expiry.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.9.2 修改证书有效期 |
| **脚本路径** | `scripts/steps/phase2_k8s_base/19-modify-cert-expiry.sh` |
| **执行机器** | k8sc1 控制节点上执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase2_k8s_base/19-modify-cert-expiry.sh"` |
| **依赖关系** | 依赖 18-init-k8s-cluster.sh |
| **主要功能** | 编辑 `/etc/kubernetes/manifests/kube-controller-manager.yaml`、添加 `--cluster-signing-duration=867240h0m0s` 参数（100年）、kube-controller-manager 会自动重启生效 |
| **证书有效期** | 100 年（867240h0m0s） |
| **所需参数** | 无特殊参数（固定配置证书有效期为100年） |

---

### 20-add-control-nodes.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.9.3 添加K8S控制节点 |
| **脚本路径** | `scripts/steps/phase2_k8s_base/20-add-control-nodes.sh` |
| **执行机器** | k8sc2 和 k8sc3 节点执行（一台执行完后再执行另一台） |
| **批量执行函数** | `exec_remote_script "k8sc2" "scripts/steps/phase2_k8s_base/20-add-control-nodes.sh"`（k8sc2）<br>`exec_remote_script "k8sc3" "scripts/steps/phase2_k8s_base/20-add-control-nodes.sh"`（k8sc3） |
| **依赖关系** | 依赖 18-init-k8s-cluster.sh |
| **主要功能** | 使用 kubeadm join 命令添加控制节点（包含 --control-plane 和 --certificate-key 参数）、配置 kubectl（复制 admin.conf 并设置权限） |
| **执行顺序** | k8sc2 → k8sc3（按顺序执行） |
| **适用场景** | 仅在高可用部署时执行 |
| **所需参数** | control_plane 列表、control_plane[0].ip<br>（来源：config.control_plane[].ip，k8sc2 和 k8sc3；config.control_plane[0].ip，主控制节点） |

---

### 21-add-worker-nodes.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.9.4 添加K8S工作节点 |
| **脚本路径** | `scripts/steps/phase2_k8s_base/21-add-worker-nodes.sh` |
| **执行机器** | 所有工作节点（k8sw1-k8sw6）执行 |
| **批量执行函数** | `exec_script_on_workers "scripts/steps/phase2_k8s_base/21-add-worker-nodes.sh"` |
| **依赖关系** | 依赖 18-init-k8s-cluster.sh |
| **主要功能** | 使用 kubeadm join 命令添加工作节点（不包含 --control-plane 参数）、如出现证书错误提示配置 kubectl 的方法，用于验证节点状态 |
| **执行节点** | k8sw1, k8sw2, k8sw3, k8sw4, k8sw5, k8sw6 |
| **所需参数** | workers 列表、control_plane[0].ip<br>（来源：config.workers[].ip、config.control_plane[0].ip，主控制节点） |

---

### 22-install-cni-flannel.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 3.9.5 安装CNI插件-Flannel |
| **脚本路径** | `scripts/steps/phase2_k8s_base/22-install-cni-flannel.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase2_k8s_base/22-install-cni-flannel.sh"` |
| **依赖关系** | 依赖 21-add-worker-nodes.sh（所有工作节点加入后） |
| **主要功能** | 查看并确认 kube-flannel.yml 中的网络配置与 cluster.yaml 一致、使用 kubectl apply 安装 Flannel CNI 插件、验证节点状态应为 Ready、验证 Pod 状态（包括 coredns 和 kube-flannel-ds） |
| **关键验证** | kubectl get nodes（状态为 Ready）、kubectl get pods -A（所有 Pod 状态为 Running 或 Completed） |
| **所需参数** | cluster.pod_subnet、paths.k8s_install、control_plane[0].ip<br>（来源：config.cluster.pod_subnet、config.paths.k8s_install、config.control_plane[0].ip，k8sc1） |

---

## 阶段3：Kubemate及生态组件

本阶段包含17个脚本，用于安装和配置 Kubernetes 生态系统组件。

> **注意：** 如无特殊说明，以下所有操作仅在 k8sc1（master1）控制节点上执行。

### 30-create-namespace.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.1 创建命名空间 |
| **脚本路径** | `scripts/steps/phase3_ecosystem/30-create-namespace.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/30-create-namespace.sh"` |
| **依赖关系** | 依赖阶段2完成（集群正常运行） |
| **主要功能** | 使用 kubectl apply 创建 kubemate-system 命名空间、验证命名空间创建成功 |
| **命名空间** | kubemate-system |
| **所需参数** | 无特殊参数（固定命名空间为 kubemate-system） |

---

### 31-install-kubemate-ui.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.2 安装kubemate管理界面 |
| **脚本路径** | `scripts/steps/phase3_ecosystem/31-install-kubemate-ui.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/31-install-kubemate-ui.sh"` |
| **依赖关系** | 依赖 30-create-namespace.sh |
| **主要功能** | 编辑 1.kubemate.yml 配置文件（修改第730行为 k8sc1 的 IP 地址）、执行 kubectl apply 安装（可能需要执行两遍）、验证 Pod 状态、提供 Web 界面访问地址 |
| **访问信息** | 地址：http://10.3.66.18:30088、默认用户名：admin、默认密码：000000als |
| **所需参数** | control_plane[0].ip<br>（来源：config.control_plane[0].ip，k8sc1） |

---

### 32-install-nfs.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.3 安装NFS插件 |
| **脚本路径** | `scripts/steps/phase3_ecosystem/32-install-nfs.sh` |
| **执行机器** | 所有节点（控制节点、工作节点、镜像仓库） |
| **批量执行函数** | `exec_script_on_all_nodes "scripts/steps/phase3_ecosystem/32-install-nfs.sh"` |
| **依赖关系** | 依赖 30-create-namespace.sh |
| **主要功能** | k8sc1 控制节点：检查并安装 nfs-server 服务、启动 nfs-server 服务、配置 NAS 挂载路径、修改 nfs-value.yaml 配置、配置开机自动挂载 NFS、安装 helm 工具、使用 helm 安装 nfs-subdir-external-provisioner<br><br>其他节点：检查并安装 nfs-server 服务、启动 nfs-server 服务、配置开机自动挂载 NFS |
| **关键配置** | NAS server IP: 10.3.5.221、NAS 路径: /kvmdata/nfsdata/xdnfs、挂载点: /data/nas_root |
| **所需参数** | 无特殊参数（NAS配置为硬编码） |

---

### 33-install-elasticsearch.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.4 安装elasticsearch |
| **脚本路径** | `scripts/steps/phase3_ecosystem/33-install-elasticsearch.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/33-install-elasticsearch.sh"` |
| **依赖关系** | 依赖 30-create-namespace.sh |
| **主要功能** | 使用 kubectl apply 安装 elasticsearch CRD、安装 elasticsearch operator、安装 skywalking 配置文件、验证 es-skywalking 相关 Pod 状态 |
| **部署顺序** | 2.es-crds.yml → 2.es-operator.yml → 2.es-skywalking.yml |
| **所需参数** | 无特殊参数 |

---

### 34-install-skywalking.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.5 安装skywalking |
| **脚本路径** | `scripts/steps/phase3_ecosystem/34-install-skywalking.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/34-install-skywalking.sh"` |
| **依赖关系** | 依赖 33-install-elasticsearch.sh |
| **主要功能** | 获取 Elasticsearch 密码并保存、编辑 skywalking 配置文件（替换 ES 密码）、删除并重新应用 skywalking 配置、验证 skywalking 相关 Pod 状态（skywalking-oap 启动较慢） |
| **关键步骤** | 密码获取：`kubectl get -n kubemate-system secret es-skywalking-es-elastic-user -o go-template='{{.data.elastic \| base64decode}}'` |
| **所需参数** | 无特殊参数 |

---

### 35-install-loki.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.6 安装loki |
| **脚本路径** | `scripts/steps/phase3_ecosystem/35-install-loki.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/35-install-loki.sh"` |
| **依赖关系** | 依赖 30-create-namespace.sh |
| **主要功能** | k8sc1 控制节点：使用 kubectl apply 安装 loki 日志系统、安装相关安全配置、验证 loki 相关 Pod 状态<br><br>工作节点（如使用本地磁盘存储）：创建本地存储目录 `/data/loki_root`、设置目录权限为 `10001:10001` |
| **部署顺序** | 4.loki.yml → 4.loki-sec.yml |
| **所需参数** | 无特殊参数 |

---

### 36-install-traefik.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.7 安装traefik |
| **脚本路径** | `scripts/steps/phase3_ecosystem/36-install-traefik.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/36-install-traefik.sh"` |
| **依赖关系** | 依赖 30-create-namespace.sh |
| **主要功能** | 使用 kubectl apply 安装 traefik 网关相关配置、安装日志格式化管理配置、验证 traefik 相关 Pod 状态 |
| **部署顺序** | 5.traefki-ds.yaml（可能执行两遍） → 6.logfmt-manage.yml |
| **所需参数** | 无特殊参数 |

---

### 37-install-traefik-mesh.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.8 安装traefik-mesh |
| **脚本路径** | `scripts/steps/phase3_ecosystem/37-install-traefik-mesh.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/37-install-traefik-mesh.sh"` |
| **依赖关系** | 依赖 36-install-traefik.sh |
| **主要功能** | 使用 kubectl apply 安装 Traefik Mesh 服务网格、验证 traefik-mesh 相关 Pod 状态 |
| **配置文件** | 5-1.traefik-mesh.yml |
| **所需参数** | 无特殊参数 |

---

### 38-install-prometheus.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.9 安装prometheus |
| **脚本路径** | `scripts/steps/phase3_ecosystem/38-install-prometheus.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/38-install-prometheus.sh"` |
| **依赖关系** | 依赖 30-create-namespace.sh |
| **主要功能** | 创建 Prometheus CRD、创建 kubemate-monitoring-system 命名空间、安装 RBAC 配置、安装 prometheus-operator、安装 additional-scrape-configs、安装 prometheus、安装 alertmanager、安装 prometheus-rule、安装 node-exporter、安装 kube-state-metrics、验证 prometheus 相关 Pod 状态 |
| **命名空间** | kubemate-monitoring-system |
| **部署顺序** | 1-crd.yml → 2-namespace.yml → 3-rbac.yml → 4-prometheus-operator.yml → 5-additional-scrape-configs.yml → 6-prometheus.yml → 7-alertmanager.yml → 8-prometheus-rule.yml → node-exporter.yml → kube-state-metrics.yml |
| **所需参数** | 无特殊参数 |

---

### 39-update-coredns.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.10 更新coredns配置 |
| **脚本路径** | `scripts/steps/phase3_ecosystem/39-update-coredns.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/39-update-coredns.sh"` |
| **依赖关系** | 依赖阶段2完成（集群正常运行） |
| **主要功能** | 应用 coredns 更新配置、重启 coredns 和 traefik-mesh-controller、编辑 coredns deployment 添加 podAntiAffinity 配置（使 Pod 分布在不同节点）、验证 coredns Pod 状态和分布 |
| **关键配置** | 添加 podAntiAffinity，确保 CoreDNS Pod 分布在不同节点上 |
| **所需参数** | 无特殊参数 |

---

### 40-install-metrics-server.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.11 安装metrics-server |
| **脚本路径** | `scripts/steps/phase3_ecosystem/40-install-metrics-server.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/40-install-metrics-server.sh"` |
| **依赖关系** | 依赖阶段2完成（集群正常运行） |
| **主要功能** | 执行 metrics-server 安装脚本（指定架构为 amd64）、验证 metrics-server Pod 状态、使用 kubectl top nodes 验证节点资源监控功能 |
| **命名空间** | kube-system |
| **所需参数** | paths.k8s_install<br>（来源：config.paths.k8s_install） |

---

### 41-setup-kubectl-permission.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.12 配置普通用户kubectl权限 |
| **脚本路径** | `scripts/steps/phase3_ecosystem/41-setup-kubectl-permission.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/41-setup-kubectl-permission.sh"` |
| **依赖关系** | 依赖 18-init-k8s-cluster.sh |
| **主要功能** | 复制 .kube 目录到 `/home/appusr/`、修改所有者为 appusr:appusr、验证普通用户 appusr 能使用 kubectl 查看节点 |
| **目标用户** | appusr |
| **所需参数** | control_plane[0].ip<br>（来源：config.control_plane[0].ip，k8sc1） |

---

### 42-setup-f5-ha.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.13 配置F5 master高可用 |
| **脚本路径** | `scripts/steps/phase3_ecosystem/42-setup-f5-ha.sh` |
| **执行机器** | 所有控制节点（k8sc1、k8sc2、k8sc3） |
| **批量执行函数** | `exec_script_on_control_plane "scripts/steps/phase3_ecosystem/42-setup-f5-ha.sh"` |
| **依赖关系** | 依赖阶段2完成 |
| **主要功能** | 编辑 `/etc/hosts` 文件、将 k8sc1 的 IP 改为当前中心 F5 的 IP、验证 hosts 文件配置 |
| **适用场景** | F5 负载均衡高可用部署 |
| **所需参数** | control_plane 列表<br>（来源：config.control_plane[].ip，k8sc1/k8sc2/k8sc3） |

---

### 43-install-redis-sentinel.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.14 安装redis哨兵模式 |
| **脚本路径** | `scripts/steps/phase3_ecosystem/43-install-redis-sentinel.sh` |
| **执行机器** | k8sc1 控制节点执行 |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/43-install-redis-sentinel.sh"` |
| **依赖关系** | 依赖 32-install-nfs.sh |
| **主要功能** | 创建 redis-sentinel 命名空间、应用 redis PV 配置、应用 StorageClass 配置、使用 helm 安装 redis-ha、验证 redis 相关 Pod 状态 |
| **命名空间** | redis-sentinel |
| **部署顺序** | redis-pv.yml → storageclass.yml → helm install redis-ha |
| **所需参数** | paths.k8s_install<br>（来源：config.paths.k8s_install） |

---

### 44-setup-etcd-backup.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.15.1 ETCD备份 |
| **脚本路径** | `scripts/steps/phase3_ecosystem/44-setup-etcd-backup.sh` |
| **执行机器** | 主副中心的 k8sc1 控制节点执行（root 权限） |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/44-setup-etcd-backup.sh"`（主中心）<br>`exec_remote_script "副中心k8sc1的IP" "scripts/steps/phase3_ecosystem/44-setup-etcd-backup.sh"`（副中心） |
| **依赖关系** | 依赖 18-init-k8s-cluster.sh |
| **主要功能** | 配置 crontab 定时任务（每天 2:10 执行）、调用 etcdbak.sh 脚本（参数 1 代表主中心，2 代表副中心）、验证定时任务和备份日志文件 |
| **定时任务** | `10 2 * * * nohup sh /data/k8s_install/05.crontab/etcdbak.sh 1 >> /data/crontab_task/etcdbak/etcdbak.log &` |
| **参数说明** | 参数 1：主中心、参数 2：副中心 |
| **所需参数** | paths.k8s_install<br>（来源：config.paths.k8s_install） |

---

### 45-setup-traefik-cleanup.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.15.2 Traefik清理 |
| **脚本路径** | `scripts/steps/phase3_ecosystem/45-setup-traefik-cleanup.sh` |
| **执行机器** | 主副中心的 k8sc1 控制节点执行（root 权限） |
| **批量执行函数** | `exec_remote_script "k8sc1" "scripts/steps/phase3_ecosystem/45-setup-traefik-cleanup.sh"`（主中心）<br>`exec_remote_script "副中心k8sc1的IP" "scripts/steps/phase3_ecosystem/45-setup-traefik-cleanup.sh"`（副中心） |
| **依赖关系** | 依赖 36-install-traefik.sh |
| **主要功能** | 配置 crontab 定时任务（每天 2:00 执行）、调用 traefikClear.sh 脚本清理 Traefik、验证定时任务和清理日志 |
| **定时任务** | `0 2 * * * nohup sh /data/k8s_install/05.crontab/traefikClear.sh >> /data/k8s_install/05.crontab/traefikClear.log &` |
| **所需参数** | paths.k8s_install<br>（来源：config.paths.k8s_install） |

---

### 46-setup-log-cleanup.sh

| 项目 | 说明 |
|------|------|
| **对应章节** | cmdlist.md 4.15.3 应用日志清理 |
| **脚本路径** | `scripts/steps/phase3_ecosystem/46-setup-log-cleanup.sh` |
| **执行机器** | 所有工作节点执行（root 权限） |
| **批量执行函数** | `exec_script_on_workers "scripts/steps/phase3_ecosystem/46-setup-log-cleanup.sh"` |
| **依赖关系** | 无强制依赖 |
| **主要功能** | 配置 crontab 定时任务（每天 2:00 执行）、调用 logback.sh 脚本清理应用日志、验证定时任务和清理日志 |
| **定时任务** | `0 2 * * * nohup sh /data/k8s_install/05.crontab/logback.sh >> /data/k8s_install/05.crontab/logback.log &` |
| **所需参数** | paths.k8s_install、workers 列表<br>（来源：config.paths.k8s_install、config.workers[].ip） |

---

## 执行顺序总览

### 阶段1：前置检查与准备（必须在管理节点执行）

```
01-check-tools.sh
    ↓
02-init-config.sh
    ↓
03-validate-config.sh
```

### 阶段2：K8S底座安装

```
10-setup-yum-source.sh (k8sc1)
    ↓
11-setup-ssh-login.sh (管理节点，可选)
    ↓
12-setup-k8s-repo.sh (所有节点，除k8sc1)
    ↓
13-install-k8s-deps.sh (所有节点)
    ↓
14-replace-kubeadm.sh (k8sc1)
    ↓
15-environment-config.sh (所有节点)
    ↓
16-install-containerd.sh (所有节点)
    ↓
17-install-registry.sh (registry节点)
    ↓
18-init-k8s-cluster.sh (k8sc1)
    ↓
19-modify-cert-expiry.sh (k8sc1)
    ↓
20-add-control-nodes.sh (k8sc2, k8sc3 顺序执行)
    ↓
21-add-worker-nodes.sh (k8sw1-k8sw6)
    ↓
22-install-cni-flannel.sh (k8sc1)
```

### 阶段3：Kubemate及生态组件（除非特别说明，均在k8sc1执行）

```
30-create-namespace.sh
    ↓
31-install-kubemate-ui.sh
    ↓
32-install-nfs.sh (所有节点)
    ↓
33-install-elasticsearch.sh
    ↓
34-install-skywalking.sh
    ↓
35-install-loki.sh (工作节点需创建本地存储目录)
    ↓
36-install-traefik.sh
    ↓
37-install-traefik-mesh.sh
    ↓
38-install-prometheus.sh
    ↓
39-update-coredns.sh
    ↓
40-install-metrics-server.sh
    ↓
41-setup-kubectl-permission.sh
    ↓
42-setup-f5-ha.sh (所有控制节点)
    ↓
43-install-redis-sentinel.sh (可选)
    ↓
44-setup-etcd-backup.sh (k8sc1)
    ↓
45-setup-traefik-cleanup.sh (k8sc1)
    ↓
46-setup-log-cleanup.sh (所有工作节点)
```

### 关键依赖关系

1. **阶段1完成后才能开始阶段2**
2. **阶段2中的脚本顺序必须遵守**：
   - 10 → 12 → 13 → 14/15 → 16 → 17 → 18 → 19 → 20 → 21 → 22
3. **阶段3需要先完成阶段2的22号脚本**（CNI插件安装完成）
4. **阶段3中的脚本大部分在k8sc1上执行**（除32、42、46外）
5. **定时任务脚本（44、45、46）可以在最后任意时间配置**

---

## 关键节点说明

### 控制节点（Control Plane）
- **k8sc1**: 主控制节点（kubeadm init 执行节点）
- **k8sc2**: 从控制节点（kubeadm join --control-plane）
- **k8sc3**: 从控制节点（kubeadm join --control-plane），同时作为镜像仓库

### 工作节点（Worker Node）
- **k8sw1-k8sw6**: 工作节点（kubeadm join）

### 镜像仓库
- **registry**: 镜像仓库节点（IP: 10.3.66.20，通常复用 k8sc3）

### 管理节点
- 执行脚本的本地节点，负责分发命令到所有集群节点

### 服务器规划

| 主机名   | IP         | IPv6        | 角色及功能                 |
| -------- | ---------- | ----------- | -------------------------- |
| k8sc1    | 10.3.66.18 | fd00:42::18 | 控制平面（主）、repo源服务 |
| k8sc2    | 10.3.66.19 | fd00:42::19 | 控制平面（从）             |
| k8sc3    | 10.3.66.20 | fd00:42::20 | 控制平面（从）             |
| k8sw1    | 10.3.66.21 | fd00:42::21 | 工作节点、nfs服务器        |
| k8sw2    | 10.3.66.22 | fd00:42::22 | 工作节点                   |
| k8sw3    | 10.3.66.23 | fd00:42::23 | 工作节点                   |
| k8sw4    | 10.3.66.24 | fd00:42::24 | 工作节点                   |
| k8sw5    | 10.3.66.25 | fd00:42::25 | 工作节点                   |
| k8sw6    | 10.3.66.26 | fd00:42::26 | 工作节点                   |
| registry | 10.3.66.20 | fd00:42::20 | 镜像仓库                   |

---

## 注意事项

1. **执行顺序**: 必须按照本文档的执行顺序执行脚本，跳过或改变顺序可能导致安装失败。

2. **依赖关系**: 部分脚本有严格的依赖关系，请确保前置步骤已完成。

3. **执行机器**: 每个脚本都有明确的执行机器要求，请在正确的节点上执行。

4. **批量执行函数**: 文档中标注了每个脚本应该使用的批量执行函数，具体函数定义见 [api.md](./api.md)：
   - `exec_remote_script "IP/类型" "脚本路径"` - 统一入口函数
   - `exec_script_on_control_plane "脚本路径"` - 所有控制节点
   - `exec_script_on_workers "脚本路径"` - 所有工作节点
   - `exec_script_on_registry "脚本路径"` - 镜像仓库节点
   - `exec_script_on_all_nodes "脚本路径"` - 所有节点

5. **高可用部署**: 如果不需要高可用，可以跳过 20-add-control-nodes.sh 和相关配置。

6. **可选组件**: 部分组件（如 redis 哨兵、SSH 免密登录）为可选，根据实际需求决定是否安装。

7. **定时任务**: 定时任务配置需要 root 权限，请确保有足够的权限。

8. **验证步骤**: 每个脚本执行后，应按照文档中的验证步骤验证安装结果。

9. **日志记录**: 建议记录每个脚本的执行日志，便于问题排查。

10. **文件格式**: 所有脚本都使用 LF 换行符格式，确保在 Linux 环境下正常执行。

11. **kubeadm join 命令**: 集群初始化后生成的 kubeadm join 命令非常重要，请妥善保存用于后续添加节点。

---

## 批量执行函数使用说明

### 函数参考

所有批量执行函数定义在 `scripts/lib/exec_script.sh` 中，详细文档见 [api.md](./api.md)。

### 常用函数

| 函数名 | 适用范围 | 示例 |
|--------|----------|------|
| `exec_remote_script` | 所有节点类型或单个节点 | `exec_remote_script "k8sc1" "script.sh"` |
| `exec_script_on_control_plane` | 所有控制节点 | `exec_script_on_control_plane "script.sh"` |
| `exec_script_on_workers` | 所有工作节点 | `exec_script_on_workers "script.sh"` |
| `exec_script_on_registry` | 镜像仓库节点 | `exec_script_on_registry "script.sh"` |
| `exec_script_on_all_nodes` | 所有节点 | `exec_script_on_all_nodes "script.sh"` |

### 使用建议

1. **单节点脚本**（如 k8sc1）：使用 `exec_remote_script "k8sc1"`
2. **多节点脚本**（控制节点）：使用 `exec_script_on_control_plane`
3. **多节点脚本**（工作节点）：使用 `exec_script_on_workers`
4. **多节点脚本**（所有节点）：使用 `exec_script_on_all_nodes`
5. **本地执行脚本**（管理节点）：直接运行脚本，无需远程执行函数

### 传参方式

```bash
# 无参数
exec_remote_script "k8sc1" "scripts/steps/script.sh"

# 单个参数
exec_remote_script "k8sc1" "scripts/steps/script.sh" "param1=value1"

# 多个参数
exec_remote_script "k8sc1" "scripts/steps/script.sh" \
    "param1=value1" \
    "param2=value2" \
    "param3=value3"
```

---

## 相关文档

- **设计文档**: [doc/design.md](./design.md) - 整体架构和流程设计
- **接口文档**: [doc/api.md](./api.md) - 所有公共函数接口定义
- **命令清单**: [doc/cmdlist.md](./cmdlist.md) - 手动安装命令参考

---

**文档版本**: 1.1.0
**生成日期**: 2026-03-26
**更新日期**: 2026-03-27
**维护团队**: KubeFoundry Team
