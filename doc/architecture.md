# KubeFoundry 部署架构设计

## 📋 文档概述

本文档描述 KubeFoundry 自动化部署系统的整体架构，包括目录结构、脚本组织、执行流程和使用方式。

**版本**: 1.0.0
**最后更新**: 2026-01-20
**作者**: KubeFoundry Team

---

## 1. 整体架构

### 1.1 核心设计理念

**中央控制机制**：
- `deploy.sh` 作为中央控制器，在管理节点本地运行
- 通过 SSH 远程执行命令到目标节点
- 实现分布式、自动化的集群部署

**模块化设计**：
- 每个部署步骤封装为独立模块
- 模块遵循统一的生命周期：前置检查 → 安装 → 后置验证 → (失败时) 回滚
- 支持单独执行任意模块

**状态管理**：
- 记录每个阶段的执行状态
- 支持断点续传
- 支持失败重试

### 1.2 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                     管理节点 (Management Node)                    │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    deploy.sh (主控制器)                     │ │
│  │                                                              │ │
│  │  执行流程:                                                    │ │
│  │  1. config_load() - 加载配置                                │ │
│  │  2. state_load() - 加载状态                                 │ │
│  │  3. 根据参数调用对应模块                                     │ │
│  │  4. module_execute() - 执行模块                             │ │
│  │     ├─ module_pre_check() - 前置检查                        │ │
│  │     ├─ module_install() - 执行安装                          │ │
│  │     └─ module_post_check() - 后置验证                       │ │
│  │  5. state_save() - 保存状态                                 │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                    │
│                              │ SSH 连接                            │
├──────────────────────────────┼────────────────────────────────────┤
│                              │                                    │
│         ┌────────────────────┴────────────────────┐              │
│         │                                         │              │
│         ▼                                         ▼              │
│  ┌────────────┐                          ┌────────────┐         │
│  │  k8sc1     │                          │  k8sw1     │         │
│  │ (控制节点)  │                          │ (工作节点)  │         │
│  │            │                          │            │         │
│  │ 接收 SSH   │                          │ 接收 SSH   │         │
│  │ 执行命令   │                          │ 执行命令   │         │
│  │ 返回结果   │                          │ 返回结果   │         │
│  └────────────┘                          └────────────┘         │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. 目录结构

### 2.1 完整目录树

```
KubeFoundry/
├── deploy.sh                          # 主部署脚本
├── README.md                          # 项目说明文档
├── doc/                               # 文档目录
│   ├── cmdlist.md                     # K8S安装命令清单
│   ├── api_reference.md              # 公用方法/API参考
│   ├── architecture.md                # 本文档 - 架构设计
│   └── installscript/                 # 安装脚本文档
│       ├── 01.dns.sh                  # DNS配置脚本说明
│       └── ...                        # 其他脚本说明
├── scripts/                           # 所有部署脚本
│   ├── core/                          # 核心库
│   │   ├── config_parser.sh          # 配置管理（参见api_reference.md）
│   │   ├── module_manager.sh         # 模块管理（参见api_reference.md）
│   │   └── state_manager.sh          # 状态管理（参见api_reference.md）
│   ├── utils/                         # 工具库
│   │   ├── ssh.sh                    # SSH远程执行（参见api_reference.md）
│   │   ├── logger.sh                 # 日志管理（参见api_reference.md）
│   │   ├── validator.sh              # 验证检查（参见api_reference.md）
│   │   ├── retry.sh                  # 重试机制（参见api_reference.md）
│   │   └── common.sh                 # 通用工具（参见api_reference.md）
│   ├── config/                        # 配置文件
│   │   ├── config.yaml               # 主配置文件
│   │   └── nodes.yaml                # 节点配置（可选，可合并到config.yaml）
│   └── modules/                       # 部署模块（按cmdlist.md阶段组织）
│       ├── stage01_precheck/         # 阶段1：前置检查与准备
│       │   ├── step01_init_config.sh
│       │   ├── step02_check_config.sh
│       │   └── step03_check_tools.sh
│       ├── stage02_k8s_base/         # 阶段2：K8S底座安装
│       │   ├── step01_setup_yum_repo.sh
│       │   ├── step02_setup_ssh_key.sh
│       │   ├── step03_install_k8s_deps.sh
│       │   ├── step04_replace_kubeadm.sh
│       │   ├── step05_env_config/
│       │   │   ├── step051_dns_config.sh
│       │   │   ├── step052_ipv6_config.sh
│       │   │   ├── step053_hostname_config.sh
│       │   │   ├── step054_limits_config.sh
│       │   │   └── step055_sysctl_config.sh
│       │   ├── step06_install_containerd.sh
│       │   ├── step07_install_registry.sh
│       │   └── step08_install_k8s/
│       │       ├── step081_init_cluster.sh
│       │       ├── step082_update_cert_duration.sh
│       │       ├── step083_add_control_nodes.sh
│       │       ├── step084_add_worker_nodes.sh
│       │       └── step085_install_cni.sh
│       └── stage03_kubemate/         # 阶段3：Kubemate及生态组件安装
│           ├── step01_create_namespace.sh
│           ├── step02_install_kubemate.sh
│           ├── step03_install_nfs.sh
│           ├── step04_install_elasticsearch.sh
│           ├── step05_install_skywalking.sh
│           ├── step06_install_loki.sh
│           ├── step07_install_traefik.sh
│           ├── step08_install_traefik_mesh.sh
│           ├── step09_install_prometheus.sh
│           ├── step10_update_coredns.sh
│           ├── step11_install_metrics_server.sh
│           ├── step12_config_user_kubectl.sh
│           ├── step13_config_f5_ha.sh
│           ├── step14_install_redis.sh
│           └── step15_setup_crontab/
│               ├── step151_etcd_backup.sh
│               ├── step152_traefik_cleanup.sh
│               └── step153_log_cleanup.sh
└── logs/                             # 日志目录
    ├── deploy_20260120_100000.log
    ├── deploy_20260120_143022.log
    └── state.json                    # 部署状态文件
```

### 2.2 目录说明

#### 根目录
- **deploy.sh**: 主部署脚本，项目入口
- **README.md**: 项目说明文档

#### doc/ 目录
- **cmdlist.md**: K8S安装命令清单，参考文档
- **api_reference.md**: 公用方法/API参考，开发参考文档
- **architecture.md**: 本文档，架构设计说明
- **installscript/**: 各个安装脚本的详细说明

#### scripts/ 目录
核心脚本目录，包含所有部署相关的脚本和配置。

**core/** - 核心库
提供配置管理、模块管理、状态管理等核心功能。

**utils/** - 工具库
提供SSH执行、日志记录、验证检查、重试机制等工具函数。

**config/** - 配置文件
YAML格式的配置文件，定义集群参数。

**modules/** - 部署模块
按照cmdlist.md的阶段组织，每个步骤一个脚本文件。

#### logs/ 目录
- **deploy_*.log**: 部署日志文件
- **state.json**: 部署状态文件，用于断点续传

---

## 3. deploy.sh 主脚本设计

### 3.1 脚本结构

```bash
#!/bin/bash
#
# KubeFoundry K8S 集群一键部署脚本
# 版本: 1.0.0
#

set -e  # 遇到错误立即退出

# ============================================================
# 1. 初始化
# ============================================================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载核心库
source "${SCRIPT_DIR}/scripts/core/config_parser.sh"
source "${SCRIPT_DIR}/scripts/core/module_manager.sh"
source "${SCRIPT_DIR}/scripts/core/state_manager.sh"

# 加载工具库
source "${SCRIPT_DIR}/scripts/utils/logger.sh"
source "${SCRIPT_DIR}/scripts/utils/ssh.sh"
source "${SCRIPT_DIR}/scripts/utils/validator.sh"

# 初始化日志系统
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/deploy_$(get_timestamp).log"
LOG_LEVEL="INFO"

log_init "$LOG_FILE" "$LOG_LEVEL"

# ============================================================
# 2. 加载配置和状态
# ============================================================

# 加载配置文件
config_load "${SCRIPT_DIR}/scripts/config/config.yaml"

# 加载或创建状态文件
if [ -f "${LOG_DIR}/state.json" ]; then
    state_load
else
    state_create
fi

# ============================================================
# 3. 阶段函数定义
# ============================================================

# 阶段1：前置检查与准备
stage01_precheck() {
    log_info "========================================"
    log_info "开始阶段1：前置检查与准备"
    log_info "========================================"
    state_update "current_stage" "stage01_precheck"

    # 检查是否已完成
    if state_is_completed "stage01_precheck"; then
        log_warn "阶段1已完成，跳过执行"
        return 0
    fi

    # 执行各个步骤
    source "${SCRIPT_DIR}/scripts/modules/stage01_precheck/step01_init_config.sh"
    module_execute "$?" "初始化参数配置"

    source "${SCRIPT_DIR}/scripts/modules/stage01_precheck/step02_check_config.sh"
    module_execute "$?" "检查配置文件完整性"

    source "${SCRIPT_DIR}/scripts/modules/stage01_precheck/step03_check_tools.sh"
    module_execute "$?" "检查必要工具安装"

    # 标记完成
    state_set_stage_completed "stage01_precheck"
    log_success "========================================"
    log_success "阶段1：前置检查与准备 完成"
    log_success "========================================"
}

# 阶段2：K8S底座安装
stage02_k8s_base() {
    log_info "========================================"
    log_info "开始阶段2：K8S底座安装"
    log_info "========================================"
    state_update "current_stage" "stage02_k8s_base"

    if state_is_completed "stage02_k8s_base"; then
        log_warn "阶段2已完成，跳过执行"
        return 0
    fi

    # 执行各个步骤
    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step01_setup_yum_repo.sh"
    module_execute "$?" "配置本地yum源"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step02_setup_ssh_key.sh"
    module_execute "$?" "配置SSH免密登录"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step03_install_k8s_deps.sh"
    module_execute "$?" "安装K8s依赖包"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step04_replace_kubeadm.sh"
    module_execute "$?" "替换kubeadm为支持100年证书版本"

    # 环境配置（多个子步骤）
    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step05_env_config/step051_dns_config.sh"
    module_execute "$?" "修改DNS"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step05_env_config/step052_ipv6_config.sh"
    module_execute "$?" "修改网络配置（IPv6）"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step05_env_config/step053_hostname_config.sh"
    module_execute "$?" "修改主机名"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step05_env_config/step054_limits_config.sh"
    module_execute "$?" "修改open files参数"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step05_env_config/step055_sysctl_config.sh"
    module_execute "$?" "配置环境变量"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step06_install_containerd.sh"
    module_execute "$?" "安装containerd"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step07_install_registry.sh"
    module_execute "$?" "安装镜像仓库"

    # K8S安装（多个子步骤）
    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step08_install_k8s/step081_init_cluster.sh"
    module_execute "$?" "初始化K8S集群"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step08_install_k8s/step082_update_cert_duration.sh"
    module_execute "$?" "修改证书有效期"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step08_install_k8s/step083_add_control_nodes.sh"
    module_execute "$?" "添加K8S控制节点"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step08_install_k8s/step084_add_worker_nodes.sh"
    module_execute "$?" "添加K8S工作节点"

    source "${SCRIPT_DIR}/scripts/modules/stage02_k8s_base/step08_install_k8s/step085_install_cni.sh"
    module_execute "$?" "安装CNI插件-Flannel"

    state_set_stage_completed "stage02_k8s_base"
    log_success "========================================"
    log_success "阶段2：K8S底座安装 完成"
    log_success "========================================"
}

# 阶段3：Kubemate及生态组件安装
stage03_kubemate() {
    log_info "========================================"
    log_info "开始阶段3：Kubemate及生态组件安装"
    log_info "========================================"
    state_update "current_stage" "stage03_kubemate"

    if state_is_completed "stage03_kubemate"; then
        log_warn "阶段3已完成，跳过执行"
        return 0
    fi

    # 执行各个步骤
    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step01_create_namespace.sh"
    module_execute "$?" "创建命名空间"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step02_install_kubemate.sh"
    module_execute "$?" "安装kubemate管理界面"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step03_install_nfs.sh"
    module_execute "$?" "安装NFS插件"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step04_install_elasticsearch.sh"
    module_execute "$?" "安装elasticsearch"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step05_install_skywalking.sh"
    module_execute "$?" "安装skywalking"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step06_install_loki.sh"
    module_execute "$?" "安装loki"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step07_install_traefik.sh"
    module_execute "$?" "安装traefik"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step08_install_traefik_mesh.sh"
    module_execute "$?" "安装traefik-mesh"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step09_install_prometheus.sh"
    module_execute "$?" "安装prometheus"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step10_update_coredns.sh"
    module_execute "$?" "更新coredns配置"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step11_install_metrics_server.sh"
    module_execute "$?" "安装metrics-server"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step12_config_user_kubectl.sh"
    module_execute "$?" "配置普通用户kubectl权限"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step13_config_f5_ha.sh"
    module_execute "$?" "配置F5 master高可用"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step14_install_redis.sh"
    module_execute "$?" "安装redis哨兵模式"

    # 定时任务（多个子步骤）
    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step15_setup_crontab/step151_etcd_backup.sh"
    module_execute "$?" "ETCD备份定时任务"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step15_setup_crontab/step152_traefik_cleanup.sh"
    module_execute "$?" "Traefik清理定时任务"

    source "${SCRIPT_DIR}/scripts/modules/stage03_kubemate/step15_setup_crontab/step153_log_cleanup.sh"
    module_execute "$?" "应用日志清理定时任务"

    state_set_stage_completed "stage03_kubemate"
    log_success "========================================"
    log_success "阶段3：Kubemate及生态组件安装 完成"
    log_success "========================================"
}

# ============================================================
# 4. 细粒度控制函数
# ============================================================

# 只执行某个具体步骤
execute_step() {
    local step_name="$1"
    local module_file="${SCRIPT_DIR}/scripts/modules/${step_name}.sh"

    if [ ! -f "$module_file" ]; then
        log_error "未找到模块文件: $module_file"
        return 1
    fi

    log_info "执行模块: $step_name"
    source "$module_file"
    module_execute "$?" "$step_name"
}

# ============================================================
# 5. 主流程
# ============================================================

main() {
    local action="${1:-all}"

    log_info "========================================"
    log_info "K8S 集群一键部署脚本"
    log_info "版本: 1.0.0"
    log_info "开始时间: $(format_datetime)"
    log_info "========================================"

    case "$action" in
        # ============== 阶段级别 ==============
        "precheck"|"stage1"|"stage01")
            stage01_precheck
            ;;

        "k8s"|"k8s-base"|"stage2"|"stage02")
            stage02_k8s_base
            ;;

        "kubemate"|"stage3"|"stage03")
            stage03_kubemate
            ;;

        # ============== 细粒度步骤 - 阶段1 ==============
        "init-config")
            execute_step "stage01_precheck/step01_init_config"
            ;;

        "check-config")
            execute_step "stage01_precheck/step02_check_config"
            ;;

        "check-tools")
            execute_step "stage01_precheck/step03_check_tools"
            ;;

        # ============== 细粒度步骤 - 阶段2 ==============
        "yum-repo")
            execute_step "stage02_k8s_base/step01_setup_yum_repo"
            ;;

        "ssh-key"|"setup-ssh")
            execute_step "stage02_k8s_base/step02_setup_ssh_key"
            ;;

        "k8s-deps")
            execute_step "stage02_k8s_base/step03_install_k8s_deps"
            ;;

        "replace-kubeadm")
            execute_step "stage02_k8s_base/step04_replace_kubeadm"
            ;;

        "dns"|"config-dns")
            execute_step "stage02_k8s_base/step05_env_config/step051_dns_config"
            ;;

        "ipv6"|"config-ipv6")
            execute_step "stage02_k8s_base/step05_env_config/step052_ipv6_config"
            ;;

        "hostname"|"config-hostname")
            execute_step "stage02_k8s_base/step05_env_config/step053_hostname_config"
            ;;

        "limits"|"config-limits")
            execute_step "stage02_k8s_base/step05_env_config/step054_limits_config"
            ;;

        "sysctl"|"config-sysctl")
            execute_step "stage02_k8s_base/step05_env_config/step055_sysctl_config"
            ;;

        "containerd")
            execute_step "stage02_k8s_base/step06_install_containerd"
            ;;

        "registry")
            execute_step "stage02_k8s_base/step07_install_registry"
            ;;

        "init-cluster"|"k8s-init")
            execute_step "stage02_k8s_base/step08_install_k8s/step081_init_cluster"
            ;;

        "cert"|"update-cert")
            execute_step "stage02_k8s_base/step08_install_k8s/step082_update_cert_duration"
            ;;

        "control-nodes"|"add-control")
            execute_step "stage02_k8s_base/step08_install_k8s/step083_add_control_nodes"
            ;;

        "worker-nodes"|"add-worker")
            execute_step "stage02_k8s_base/step08_install_k8s/step084_add_worker_nodes"
            ;;

        "cni"|"flannel")
            execute_step "stage02_k8s_base/step08_install_k8s/step085_install_cni"
            ;;

        # ============== 细粒度步骤 - 阶段3 ==============
        "namespace"|"create-ns")
            execute_step "stage03_kubemate/step01_create_namespace"
            ;;

        "kubemate-ui")
            execute_step "stage03_kubemate/step02_install_kubemate"
            ;;

        "nfs")
            execute_step "stage03_kubemate/step03_install_nfs"
            ;;

        "es"|"elasticsearch")
            execute_step "stage03_kubemate/step04_install_elasticsearch"
            ;;

        "skywalking")
            execute_step "stage03_kubemate/step05_install_skywalking"
            ;;

        "loki")
            execute_step "stage03_kubemate/step06_install_loki"
            ;;

        "traefik")
            execute_step "stage03_kubemate/step07_install_traefik"
            ;;

        "traefik-mesh")
            execute_step "stage03_kubemate/step08_install_traefik_mesh"
            ;;

        "prometheus")
            execute_step "stage03_kubemate/step09_install_prometheus"
            ;;

        "coredns"|"update-coredns")
            execute_step "stage03_kubemate/step10_update_coredns"
            ;;

        "metrics"|"metrics-server")
            execute_step "stage03_kubemate/step11_install_metrics_server"
            ;;

        "user-kubectl"|"kubectl-perm")
            execute_step "stage03_kubemate/step12_config_user_kubectl"
            ;;

        "f5"|"f5-ha")
            execute_step "stage03_kubemate/step13_config_f5_ha"
            ;;

        "redis")
            execute_step "stage03_kubemate/step14_install_redis"
            ;;

        "crontab"|"cron")
            execute_step "stage03_kubemate/step15_setup_crontab/step151_etcd_backup"
            execute_step "stage03_kubemate/step15_setup_crontab/step152_traefik_cleanup"
            execute_step "stage03_kubemate/step15_setup_crontab/step153_log_cleanup"
            ;;

        "etcd-backup")
            execute_step "stage03_kubemate/step15_setup_crontab/step151_etcd_backup"
            ;;

        "traefik-cleanup")
            execute_step "stage03_kubemate/step15_setup_crontab/step152_traefik_cleanup"
            ;;

        "log-cleanup")
            execute_step "stage03_kubemate/step15_setup_crontab/step153_log_cleanup"
            ;;

        # ============== 特殊命令 ==============
        "all")
            stage01_precheck
            stage02_k8s_base
            stage03_kubemate
            ;;

        "reset"|"clean")
            log_warn "重置部署状态"
            state_reset
            log_success "部署状态已重置"
            ;;

        "status")
            log_info "当前部署状态:"
            log_info "  当前阶段: $(state_get 'current_stage')"
            log_info "  部署状态: $(state_get 'status')"
            log_info "  开始时间: $(state_get 'start_time')"
            ;;

        "help"|"-h"|"--help")
            show_help
            ;;

        *)
            log_error "未知的操作: $action"
            echo ""
            show_help
            exit 1
            ;;
    esac

    log_success "========================================"
    log_success "部署完成！"
    log_success "结束时间: $(format_datetime)"
    log_success "========================================"
}

# 显示帮助信息
show_help() {
    cat << EOF
KubeFoundry K8S 集群一键部署脚本

用法:
    $0 [选项]

选项:
    阶段级别:
        all                    完整部署（默认）
        precheck, stage1       阶段1：前置检查与准备
        k8s, stage2            阶段2：K8S底座安装
        kubemate, stage3       阶段3：Kubemate及生态组件安装

    阶段1 - 前置检查:
        init-config            初始化参数配置
        check-config           检查配置文件完整性
        check-tools            检查必要工具安装

    阶段2 - K8S底座:
        yum-repo               配置本地yum源
        ssh-key, setup-ssh     配置SSH免密登录
        k8s-deps               安装K8s依赖包
        replace-kubeadm        替换kubeadm为支持100年证书版本
        dns                    修改DNS
        ipv6                   修改网络配置（IPv6）
        hostname               修改主机名
        limits                 修改open files参数
        sysctl                 配置环境变量
        containerd             安装containerd
        registry               安装镜像仓库
        init-cluster           初始化K8S集群
        cert                   修改证书有效期
        control-nodes          添加K8S控制节点
        worker-nodes           添加K8S工作节点
        cni, flannel           安装CNI插件-Flannel

    阶段3 - Kubemate:
        namespace              创建命名空间
        kubemate-ui            安装kubemate管理界面
        nfs                    安装NFS插件
        es, elasticsearch      安装elasticsearch
        skywalking             安装skywalking
        loki                   安装loki
        traefik                安装traefik
        traefik-mesh           安装traefik-mesh
        prometheus             安装prometheus
        coredns                更新coredns配置
        metrics                安装metrics-server
        user-kubectl           配置普通用户kubectl权限
        f5                     配置F5 master高可用
        redis                  安装redis哨兵模式
        crontab                配置所有定时任务
        etcd-backup            ETCD备份定时任务
        traefik-cleanup        Traefik清理定时任务
        log-cleanup            应用日志清理定时任务

    特殊命令:
        status                 查看当前部署状态
        reset, clean           重置部署状态
        help, -h, --help       显示此帮助信息

示例:
    $0 all                    # 完整部署
    $0 containerd             # 只安装containerd
    $0 ssh-key                # 只配置SSH免密登录
    $0 k8s                    # 只安装K8S底座
    $0 registry               # 只安装镜像仓库
    $0 status                 # 查看部署状态
    $0 reset                  # 重置状态

EOF
}

# 执行主流程
main "$@"
```

### 3.2 使用示例

```bash
# 完整部署
./deploy.sh all

# 只安装containerd
./deploy.sh containerd

# 只安装镜像仓库
./deploy.sh registry

# 只执行K8S底座安装
./deploy.sh k8s

# 只安装某个生态组件
./deploy.sh prometheus

# 查看帮助
./deploy.sh help

# 查看当前状态
./deploy.sh status

# 重置状态（从头开始）
./deploy.sh reset
```

---

## 4. 模块脚本设计

### 4.1 模块标准结构

每个模块脚本必须包含以下标准函数：

```bash
#!/bin/bash

# ============================================================
# 模块元信息
# ============================================================
MODULE_NAME="模块名称"
MODULE_VERSION="1.0.0"
MODULE_STAGE="stage02_k8s_base"
MODULE_DESC="模块描述信息"

# ============================================================
# 前置检查
# ============================================================
module_pre_check() {
    log_info "【${MODULE_NAME}】前置检查..."

    # 1. 检查执行节点是否正确
    # 2. 检查依赖条件是否满足
    # 3. 检查必需文件是否存在
    # 4. 检查必需工具是否可用

    log_success "【${MODULE_NAME}】前置检查通过"
    return 0
}

# ============================================================
# 执行安装
# ============================================================
module_install() {
    log_info "【${MODULE_NAME}】开始安装..."

    # 1. 获取目标节点IP
    # 2. 通过SSH执行安装命令
    # 3. 检查返回值
    # 4. 记录日志

    if [ $? -eq 0 ]; then
        log_success "【${MODULE_NAME}】安装成功"
        return 0
    else
        log_error "【${MODULE_NAME}】安装失败"
        return 1
    fi
}

# ============================================================
# 后置验证
# ============================================================
module_post_check() {
    log_info "【${MODULE_NAME}】后置验证..."

    # 1. 验证服务是否运行
    # 2. 验证配置是否正确
    # 3. 验证功能是否正常

    log_success "【${MODULE_NAME}】后置验证通过"
    return 0
}

# ============================================================
# 回滚操作
# ============================================================
module_rollback() {
    log_warn "【${MODULE_NAME}】开始回滚..."

    # 1. 停止服务
    # 2. 删除配置
    # 3. 清理文件
    # 4. 恢复环境

    log_success "【${MODULE_NAME}】回滚完成"
    return 0
}

# ============================================================
# 模块信息
# ============================================================
module_info() {
    echo "模块: ${MODULE_NAME}"
    echo "版本: ${MODULE_VERSION}"
    echo "阶段: ${MODULE_STAGE}"
    echo "描述: ${MODULE_DESC}"
}
```

### 4.2 模块示例：安装Containerd

```bash
#!/bin/bash

# 模块元信息
MODULE_NAME="安装Containerd"
MODULE_VERSION="1.0.0"
MODULE_STAGE="stage02_k8s_base"
MODULE_DESC="在所有节点上安装Containerd容器运行时"

# 前置检查
module_pre_check() {
    log_info "【${MODULE_NAME}】前置检查..."

    # 获取所有节点
    local all_nodes=$(config_get_all_nodes)

    # 检查每个节点的SSH连接
    for node in $all_nodes; do
        local node_ip=$(config_get_node "$node" "ip")

        if ! ssh_check_connection "$node_ip"; then
            log_error "节点 $node ($node_ip) SSH连接失败"
            return 1
        fi

        log_info "节点 $node ($node_ip) SSH连接正常"
    done

    log_success "【${MODULE_NAME}】前置检查通过"
    return 0
}

# 安装
module_install() {
    log_info "【${MODULE_NAME}】开始安装..."

    # 获取所有节点
    local all_nodes=$(config_get_all_nodes)

    # 在每个节点上执行安装
    for node in $all_nodes; do
        local node_ip=$(config_get_node "$node" "ip")

        log_node_info "$node" "开始安装Containerd"

        # 通过SSH执行安装命令
        ssh_execute "$node_ip" "
            cd /tmp/k8s/02.container_runtime

            # 解压containerd
            tar Cxzvf /usr/local containerd-1.7.18-linux-amd64.tar.gz

            # 创建systemd服务
            cp containerd.service /etc/systemd/system/containerd.service

            # 安装runc
            install -m 755 runcv1.3.3.amd64 /usr/local/sbin/runc

            # 安装cni-plugins
            mkdir -p /opt/cni/bin
            tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.8.0.tgz

            # 生成配置文件
            mkdir -p /etc/containerd
            cp config-1.7.18.toml /etc/containerd/config.toml

            # 安装buildkit
            tar Cxzvf /usr/local buildkit-v0.25.2.linux-amd64.tar.gz
            cp buildkit.s* /etc/systemd/system/
            systemctl daemon-reload
            systemctl enable buildkit.service --now

            # 安装nerdctl
            tar -zxf nerdctl-2.2.0-linux-amd64.tar.gz
            chmod +x nerdctl
            mv nerdctl /usr/local/bin/

            # 配置镜像仓库
            mkdir -p /etc/containerd/certs.d/registry:5000
            cat > /etc/containerd/certs.d/registry:5000/hosts.toml <<'EOF'
server = \"http://registry:5000\"

[host.\"http://registry:5000\"]
  capabilities = [\"pull\", \"resolve\", \"push\"]
EOF

            # 启动containerd
            systemctl daemon-reload
            systemctl enable --now containerd

            echo '【SUCCESS】: Containerd安装完成'
        "

        if [ $? -eq 0 ]; then
            log_success "节点 $node Containerd安装成功"
        else
            log_error "节点 $node Containerd安装失败"
            return 1
        fi
    done

    log_success "【${MODULE_NAME}】安装成功"
    return 0
}

# 后置验证
module_post_check() {
    log_info "【${MODULE_NAME}】后置验证..."

    # 获取所有节点
    local all_nodes=$(config_get_all_nodes)

    # 检查每个节点的containerd服务
    for node in $all_nodes; do
        local node_ip=$(config_get_node "$node" "ip")

        # 验证服务状态
        if ! validate_service "$node_ip" "containerd"; then
            log_error "节点 $node Containerd服务未运行"
            return 1
        fi

        # 验证命令可用
        if ! validate_command "$node_ip" "ctr"; then
            log_error "节点 $node ctr命令不可用"
            return 1
        fi

        log_success "节点 $node Containerd验证通过"
    done

    log_success "【${MODULE_NAME}】后置验证通过"
    return 0
}

# 回滚
module_rollback() {
    log_warn "【${MODULE_NAME}】开始回滚..."

    local all_nodes=$(config_get_all_nodes)

    for node in $all_nodes; do
        local node_ip=$(config_get_node "$node" "ip")

        log_node_info "$node" "开始回滚Containerd"

        ssh_execute "$node_ip" "
            systemctl stop containerd
            systemctl disable containerd
            rm -f /etc/systemd/system/containerd.service
            rm -f /usr/local/bin/ctr
            rm -f /usr/local/bin/nerdctl
            rm -f /usr/local/sbin/runc
            rm -rf /etc/containerd
            rm -rf /opt/cni/bin
        "

        log_success "节点 $node Containerd回滚完成"
    done

    log_success "【${MODULE_NAME}】回滚完成"
    return 0
}

# 模块信息
module_info() {
    echo "模块: ${MODULE_NAME}"
    echo "版本: ${MODULE_VERSION}"
    echo "阶段: ${MODULE_STAGE}"
    echo "描述: ${MODULE_DESC}"
}
```

---

## 5. 配置文件设计

### 5.1 config.yaml 结构

```yaml
# K8S 版本配置
k8s:
  version: "1.28.2"

# 网络配置
network:
  # 集群网络
  cluster:
    pod_subnet: "10.244.0.0/16"
    service_subnet: "10.96.0.0/12"
  # 控制平面端点
  control_plane:
    endpoint: "k8sc1:6443"
  # API Server端口
  api_server_port: 6443

# 仓库源配置
repo:
  source_path: "/data/rpm/repo.tar.gz"

# 节点配置
nodes:
  # 控制节点
  control:
    - hostname: k8sc1
      ip: 10.3.66.18
      ipv6: fd00:42::18
      role: "master,reposerver"
    - hostname: k8sc2
      ip: 10.3.66.19
      ipv6: fd00:42::19
      role: "master"
    - hostname: k8sc3
      ip: 10.3.66.20
      ipv6: fd00:42::20
      role: "master,registry"

  # 工作节点
  worker:
    - hostname: k8sw1
      ip: 10.3.66.21
      ipv6: fd00:42::21
      role: "worker,nfs"
    - hostname: k8sw2
      ip: 10.3.66.22
      ipv6: fd00:42::22
      role: "worker"
    - hostname: k8sw3
      ip: 10.3.66.23
      ipv6: fd00:42::23
      role: "worker"
    - hostname: k8sw4
      ip: 10.3.66.24
      ipv6: fd00:42::24
      role: "worker"
    - hostname: k8sw5
      ip: 10.3.66.25
      ipv6: fd00:42::25
      role: "worker"
    - hostname: k8sw6
      ip: 10.3.66.26
      ipv6: fd00:42::26
      role: "worker"

# 工具路径配置
tools:
  helm_path: "/usr/local/bin/helm"
  kubectl_path: "/usr/local/bin/kubectl"

# NFS配置
nfs:
  server: "10.3.5.221"
  path: "/kvmdata/nfsdata/xdnfs"
  local_path: "/data/nas_root"
```

---

## 6. 状态管理设计

### 6.1 state.json 结构

```json
{
  "deployment_id": "20260120_100000",
  "start_time": "2026-01-20T10:00:00Z",
  "end_time": null,
  "status": "running",
  "current_stage": "stage02_k8s_base",
  "completed_stages": [
    "stage01_precheck"
  ],
  "failed_stages": [],
  "last_update": "2026-01-20T14:30:22Z",
  "progress": {
    "total_steps": 50,
    "completed_steps": 10,
    "percentage": 20
  }
}
```

### 6.2 状态转换

```
pending → running → completed
              ↓
           failed
              ↓
           rollback → (pending | completed)
```

---

## 7. 执行流程示例

### 7.1 完整部署流程

```
1. 初始化
   ├─ 加载配置文件
   ├─ 初始化日志系统
   ├─ 加载/创建状态文件
   └─ 验证环境

2. 阶段1：前置检查与准备
   ├─ step01: 初始化参数配置
   ├─ step02: 检查配置文件完整性
   └─ step03: 检查必要工具安装

3. 阶段2：K8S底座安装
   ├─ step01: 配置本地yum源
   ├─ step02: 配置SSH免密登录
   ├─ step03: 安装K8s依赖包
   ├─ step04: 替换kubeadm
   ├─ step05: 环境配置
   │   ├─ 修改DNS
   │   ├─ 配置IPv6
   │   ├─ 修改主机名
   │   ├─ 配置limits
   │   └─ 配置sysctl
   ├─ step06: 安装containerd
   ├─ step07: 安装镜像仓库
   └─ step08: 安装Kubernetes
       ├─ 初始化集群
       ├─ 修改证书有效期
       ├─ 添加控制节点
       ├─ 添加工作节点
       └─ 安装CNI

4. 阶段3：Kubemate及生态组件
   ├─ step01-14: 安装各组件
   └─ step15: 配置定时任务

5. 完成
   ├─ 保存状态
   ├─ 生成报告
   └─ 退出
```

### 7.2 单独安装Containerd流程

```
1. 初始化（同上）

2. 加载模块
   └─ source scripts/modules/stage02_k8s_base/step05_install_containerd.sh

3. 执行模块
   ├─ module_pre_check()
   │   ├─ 检查SSH连接
   │   └─ 检查节点可达性
   ├─ module_install()
   │   ├─ 获取所有节点
   │   ├─ 循环节点执行安装
   │   └─ 检查返回值
   └─ module_post_check()
       ├─ 验证服务运行
       └─ 验证命令可用

4. 完成
```

---

## 8. 错误处理和重试

### 8.1 错误处理策略

1. **立即失败**: 配置错误、文件缺失等致命错误
2. **重试机制**: 网络超时、资源临时不可用等可恢复错误
3. **回滚机制**: 安装失败时自动回滚
4. **断点续传**: 支持从失败点继续执行

### 8.2 重试配置

```bash
# 默认重试配置
RETRY_MAX_ATTEMPTS=3        # 最大重试次数
RETRY_INTERVAL=5            # 重试间隔（秒）
RETRY_TIMEOUT=300           # 命令超时（秒）

# 使用示例
retry_execute "$node_ip" "yum install -y containerd" 3 10
```

---

## 9. 日志管理

### 9.1 日志级别

- **DEBUG**: 调试信息（详细）
- **INFO**: 一般信息
- **WARN**: 警告信息
- **ERROR**: 错误信息
- **CRITICAL**: 严重错误

### 9.2 日志格式

```
[2026-01-20 10:00:00] [INFO] [k8sc1] 开始安装Containerd
[2026-01-20 10:00:05] [SUCCESS] [k8sc1] Containerd安装成功
[2026-01-20 10:00:06] [ERROR] [k8sw2] Containerd安装失败
```

---

## 10. 开发指南

### 10.1 开发新模块

1. 在对应阶段的目录下创建新脚本
2. 按照模块标准结构编写代码
3. 在 deploy.sh 中添加对应的 case 分支
4. 测试模块功能
5. 更新文档

### 10.2 测试建议

1. 单元测试：测试每个函数
2. 集成测试：测试模块执行流程
3. 端到端测试：测试完整部署流程

### 10.3 代码规范

1. 使用 4 空格缩进
2. 函数名使用小写字母和下划线
3. 变量名使用大写字母（全局）或小写字母（局部）
4. 添加详细注释
5. 遵循 ShellCheck 规范

---

## 11. 总结

### 11.1 核心优势

1. **模块化**: 每个步骤独立模块，易于维护
2. **可恢复**: 支持断点续传和失败重试
3. **可扩展**: 易于添加新组件和功能
4. **细粒度控制**: 支持单独执行任意步骤
5. **自动化**: 完全自动化部署，减少人工干预

### 11.2 使用场景

1. **全新部署**: 从零开始部署K8S集群
2. **组件安装**: 单独安装某个组件
3. **故障恢复**: 从失败点继续部署
4. **扩容缩容**: 添加或删除节点
5. **升级维护**: 更新组件版本

---

**文档版本**: 1.0.0
**最后更新**: 2026-01-20
**作者**: KubeFoundry Team
