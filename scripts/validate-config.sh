#!/bin/bash
# validate-config.sh - 配置文件验证脚本
# 验证 KubeFoundry 部署配置文件的完整性和正确性

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 加载依赖模块
source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/lib/logger.sh"

# 验证结果统计
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# 显示帮助信息
show_help() {
    cat << EOF
用法: $(basename "$0") [选项]

选项:
    -c, --config FILE        配置文件路径 (默认: config/deploy-config.yaml)
    -s, --schema FILE        JSON Schema 文件路径 (可选)
    -v, --verbose            详细输出
    -q, --quiet              静默模式，只输出错误
    --strict                 严格模式，将警告视为错误
    --fix                   尝试自动修复配置问题
    --generate-schema        生成配置文件的 JSON Schema
    -h, --help              显示此帮助信息

示例:
    $(basename "$0") -c config/deploy-config.yaml
    $(basename "$0") --config my-config.yaml --verbose
    $(basename "$0") --strict --fix
    $(basename "$0") --generate-schema > config/schema.json
EOF
}

# 解析命令行参数
parse_args() {
    CONFIG_FILE="${PROJECT_ROOT}/config/deploy-config.yaml"
    SCHEMA_FILE=""
    VERBOSE=false
    QUIET=false
    STRICT=false
    AUTO_FIX=false
    GENERATE_SCHEMA=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -s|--schema)
                SCHEMA_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --strict)
                STRICT=true
                shift
                ;;
            --fix)
                AUTO_FIX=true
                shift
                ;;
            --generate-schema)
                GENERATE_SCHEMA=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 生成 JSON Schema
generate_schema() {
    cat << 'EOF'
{
    "$schema": "http://json-schema.org/draft-07/schema#",
    "title": "KubeFoundry Deployment Configuration",
    "description": "KubeFoundry Kubernetes 集群部署配置文件",
    "type": "object",
    "required": ["global", "hosts", "packages", "networking"],
    "properties": {
        "global": {
            "type": "object",
            "required": ["architecture"],
            "properties": {
                "architecture": {
                    "type": "string",
                    "enum": ["x86_64", "amd64", "arm64", "aarch64"],
                    "description": "系统架构"
                },
                "cluster_name": {
                    "type": "string",
                    "pattern": "^[a-z0-9-]+$",
                    "description": "集群名称"
                },
                "k8s_install_dir": {
                    "type": "string",
                    "description": "Kubernetes 安装目录"
                },
                "media_source": {
                    "type": "string",
                    "description": "介质源目录"
                },
                "timezone": {
                    "type": "string",
                    "description": "时区设置"
                },
                "ssh": {
                    "type": "object",
                    "properties": {
                        "port": {"type": "integer", "minimum": 1, "maximum": 65535},
                        "user": {"type": "string"},
                        "timeout": {"type": "integer", "minimum": 1},
                        "retry_count": {"type": "integer", "minimum": 0}
                    }
                }
            }
        },
        "hosts": {
            "type": "object",
            "required": ["control_plane", "workers"],
            "properties": {
                "control_plane": {
                    "type": "array",
                    "minItems": 1,
                    "items": {
                        "type": "object",
                        "required": ["name", "ip"],
                        "properties": {
                            "name": {"type": "string", "pattern": "^[a-z0-9-]+$"},
                            "ip": {"type": "string", "format": "ipv4"},
                            "ipv6": {"type": "string", "format": "ipv6"},
                            "roles": {"type": "array", "items": {"type": "string"}},
                            "labels": {"type": "object"},
                            "taints": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "required": ["key", "effect"],
                                    "properties": {
                                        "key": {"type": "string"},
                                        "value": {"type": "string"},
                                        "effect": {"type": "string", "enum": ["NoSchedule", "NoExecute", "PreferNoSchedule"]}
                                    }
                                }
                            }
                        }
                    }
                },
                "workers": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "required": ["name", "ip"],
                        "properties": {
                            "name": {"type": "string", "pattern": "^[a-z0-9-]+$"},
                            "ip": {"type": "string", "format": "ipv4"},
                            "ipv6": {"type": "string", "format": "ipv6"},
                            "roles": {"type": "array", "items": {"type": "string"}},
                            "labels": {"type": "object"}
                        }
                    }
                }
            }
        },
        "packages": {
            "type": "object",
            "required": ["kube_version"],
            "properties": {
                "container_runtime": {
                    "type": "string",
                    "enum": ["auto", "docker", "containerd"],
                    "description": "容器运行时类型"
                },
                "kube_version": {
                    "type": "string",
                    "pattern": "^\\d+\\.\\d+\\.\\d+$",
                    "description": "Kubernetes 版本"
                },
                "versions": {
                    "type": "object",
                    "properties": {
                        "kubeadm": {"type": "string"},
                        "kubelet": {"type": "string"},
                        "kubectl": {"type": "string"},
                        "cri_tools": {"type": "string"},
                        "docker_ce": {"type": "string"},
                        "containerd_io": {"type": "string"},
                        "cni_plugins": {"type": "string"}
                    }
                }
            }
        },
        "networking": {
            "type": "object",
            "required": ["dual_stack", "cni"],
            "properties": {
                "dual_stack": {
                    "type": "object",
                    "required": ["enabled"],
                    "properties": {
                        "enabled": {"type": "boolean"},
                        "ipv4_pod_cidr": {"type": "string", "format": "ipv4-cidr"},
                        "ipv6_pod_cidr": {"type": "string", "format": "ipv6-cidr"},
                        "ipv4_service_cidr": {"type": "string", "format": "ipv4-cidr"},
                        "ipv6_service_cidr": {"type": "string", "format": "ipv6-cidr"}
                    }
                },
                "cni": {
                    "type": "object",
                    "required": ["type"],
                    "properties": {
                        "type": {"type": "string", "enum": ["flannel", "calico", "weave"]},
                        "flannel_version": {"type": "string"},
                        "backend": {"type": "string", "enum": ["vxlan", "host-gw", "udp"]},
                        "vni": {"type": "integer", "minimum": 1, "maximum": 16777215},
                        "port_range_min": {"type": "integer", "minimum": 1024, "maximum": 65535},
                        "port_range_max": {"type": "integer", "minimum": 1024, "maximum": 65535}
                    }
                }
            }
        },
        "registry": {
            "type": "object",
            "required": ["type"],
            "properties": {
                "type": {"type": "string", "enum": ["docker-registry", "harbor"]},
                "host": {"type": "string"},
                "port": {"type": "integer", "minimum": 1, "maximum": 65535},
                "certificates": {
                    "type": "object",
                    "properties": {
                        "enabled": {"type": "boolean"},
                        "cert_dir": {"type": "string"},
                        "self_signed": {
                            "type": "object",
                            "properties": {
                                "enabled": {"type": "boolean"},
                                "validity_days": {"type": "integer", "minimum": 1}
                            }
                        }
                    }
                }
            }
        },
        "storage": {
            "type": "object",
            "properties": {
                "nfs": {
                    "type": "object",
                    "required": ["server", "export_path"],
                    "properties": {
                        "server": {"type": "string", "format": "ipv4"},
                        "export_path": {"type": "string"},
                        "mount_path": {"type": "string"},
                        "options": {"type": "string"}
                    }
                }
            }
        },
        "addons": {
            "type": "object",
            "properties": {
                "ingress": {
                    "type": "object",
                    "properties": {
                        "type": {"type": "string", "enum": ["traefik", "nginx", "istio"]},
                        "enabled": {"type": "boolean"},
                        "traefik_version": {"type": "string"}
                    }
                },
                "monitoring": {
                    "type": "object",
                    "properties": {
                        "enabled": {"type": "boolean"},
                        "prometheus_version": {"type": "string"},
                        "grafana_version": {"type": "string"}
                    }
                }
            }
        },
        "backup": {
            "type": "object",
            "properties": {
                "etcd": {
                    "type": "object",
                    "properties": {
                        "enabled": {"type": "boolean"},
                        "backup_path": {"type": "string"},
                        "retention_days": {"type": "integer", "minimum": 1},
                        "interval_hours": {"type": "integer", "minimum": 1}
                    }
                }
            }
        }
    }
}
EOF
}

# 验证 YAML 格式
validate_yaml_format() {
    local config_file="$1"

    if ! command -v yq >/dev/null 2>&1; then
        log_error "yq 命令未找到，无法验证 YAML 格式"
        return 1
    fi

    if ! yq eval '.' "${config_file}" >/dev/null 2>&1; then
        log_error "配置文件 YAML 格式无效: ${config_file}"
        return 1
    fi

    [[ "${VERBOSE}" == "true" ]] && log_info "YAML 格式验证通过"
    return 0
}

# 验证必需字段
validate_required_fields() {
    local config_file="$1"

    # 检查必需的顶级字段
    local required_fields=("global" "hosts" "packages" "networking")
    local field

    for field in "${required_fields[@]}"; do
        if ! yq eval ".${field}" "${config_file}" | grep -v "^null$" >/dev/null 2>&1; then
            log_error "缺少必需字段: ${field}"
            ((VALIDATION_ERRORS++))
        fi
    done

    # 验证 global.architecture
    local arch
    arch=$(yq eval '.global.architecture // ""' "${config_file}")
    if [[ -z "${arch}" ]]; then
        log_error "global.architecture 字段不能为空"
        ((VALIDATION_ERRORS++))
    elif [[ ! "${arch}" =~ ^(x86_64|amd64|arm64|aarch64)$ ]]; then
        log_error "不支持的架构: ${arch}，支持的架构: x86_64, amd64, arm64, aarch64"
        ((VALIDATION_ERRORS++))
    fi

    # 验证 hosts.control_plane
    local control_plane_count
    control_plane_count=$(yq eval '.hosts.control_plane | length' "${config_file}")
    if [[ ${control_plane_count} -eq 0 ]]; then
        log_error "至少需要一个控制平面节点"
        ((VALIDATION_ERRORS++))
    fi

    # 验证 packages.kube_version
    local kube_version
    kube_version=$(yq eval '.packages.kube_version // ""' "${config_file}")
    if [[ -z "${kube_version}" ]]; then
        log_error "packages.kube_version 字段不能为空"
        ((VALIDATION_ERRORS++))
    elif [[ ! "${kube_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "无效的 Kubernetes 版本格式: ${kube_version}"
        ((VALIDATION_ERRORS++))
    fi

    [[ "${VERBOSE}" == "true" ]] && log_info "必需字段验证完成"
}

# 验证主机配置
validate_hosts() {
    local config_file="$1"

    local host_errors=0

    # 验证控制平面节点
    yq eval '.hosts.control_plane[] | .name + "|" + .ip' "${config_file}" | while IFS='|' read -r name ip; do
        if [[ -z "${name}" ]]; then
            log_error "控制平面节点名称不能为空"
            ((host_errors++))
            continue
        fi

        if [[ -z "${ip}" ]]; then
            log_error "控制平面节点 ${name} 的 IP 地址不能为空"
            ((host_errors++))
            continue
        fi

        if ! validate_ip "${ip}"; then
            log_error "控制平面节点 ${name} 的 IP 地址格式无效: ${ip}"
            ((host_errors++))
        fi

        if [[ ! "${name}" =~ ^[a-z0-9-]+$ ]]; then
            log_error "控制平面节点名称格式无效: ${name}，只能包含小写字母、数字和连字符"
            ((host_errors++))
        fi
    done

    # 验证工作节点
    yq eval '.hosts.workers[]? | .name + "|" + .ip' "${config_file}" | while IFS='|' read -r name ip; do
        if [[ -z "${name}" ]]; then
            log_error "工作节点名称不能为空"
            ((host_errors++))
            continue
        fi

        if [[ -z "${ip}" ]]; then
            log_error "工作节点 ${name} 的 IP 地址不能为空"
            ((host_errors++))
            continue
        fi

        if ! validate_ip "${ip}"; then
            log_error "工作节点 ${name} 的 IP 地址格式无效: ${ip}"
            ((host_errors++))
        fi

        if [[ ! "${name}" =~ ^[a-z0-9-]+$ ]]; then
            log_error "工作节点名称格式无效: ${name}，只能包含小写字母、数字和连字符"
            ((host_errors++))
        fi
    done

    # 检查重复的主机名和 IP
    local duplicate_names
    duplicate_names=$(yq eval '.hosts.control_plane[].name, .hosts.workers[].name?' "${config_file}" | sort | uniq -d)
    if [[ -n "${duplicate_names}" ]]; then
        log_error "发现重复的主机名: ${duplicate_names}"
        ((VALIDATION_ERRORS++))
    fi

    local duplicate_ips
    duplicate_ips=$(yq eval '.hosts.control_plane[].ip, .hosts.workers[].ip?' "${config_file}" | sort | uniq -d)
    if [[ -n "${duplicate_ips}" ]]; then
        log_error "发现重复的 IP 地址: ${duplicate_ips}"
        ((VALIDATION_ERRORS++))
    fi

    VALIDATION_ERRORS=$((VALIDATION_ERRORS + host_errors))
    [[ "${VERBOSE}" == "true" ]] && log_info "主机配置验证完成"
}

# 验证网络配置
validate_networking() {
    local config_file="$1"

    # 验证双栈配置
    local dual_stack_enabled
    dual_stack_enabled=$(yq eval '.networking.dual_stack.enabled // false' "${config_file}")

    if [[ "${dual_stack_enabled}" == "true" ]]; then
        local ipv4_pod_cidr
        local ipv6_pod_cidr
        ipv4_pod_cidr=$(yq eval '.networking.dual_stack.ipv4_pod_cidr // ""' "${config_file}")
        ipv6_pod_cidr=$(yq eval '.networking.dual_stack.ipv6_pod_cidr // ""' "${config_file}")

        if [[ -z "${ipv4_pod_cidr}" ]]; then
            log_error "双栈模式下 ipv4_pod_cidr 不能为空"
            ((VALIDATION_ERRORS++))
        fi

        if [[ -z "${ipv6_pod_cidr}" ]]; then
            log_error "双栈模式下 ipv6_pod_cidr 不能为空"
            ((VALIDATION_ERRORS++))
        fi
    fi

    # 验证 CNI 配置
    local cni_type
    cni_type=$(yq eval '.networking.cni.type // ""' "${config_file}")

    if [[ -z "${cni_type}" ]]; then
        log_error "networking.cni.type 字段不能为空"
        ((VALIDATION_ERRORS++))
    elif [[ ! "${cni_type}" =~ ^(flannel|calico|weave)$ ]]; then
        log_warn "不常见的 CNI 类型: ${cni_type}"
        ((VALIDATION_WARNINGS++))
    fi

    [[ "${VERBOSE}" == "true" ]] && log_info "网络配置验证完成"
}

# 验证存储配置
validate_storage() {
    local config_file="$1"

    # 检查 NFS 配置
    local nfs_server
    local nfs_export_path
    nfs_server=$(yq eval '.storage.nfs.server // ""' "${config_file}")
    nfs_export_path=$(yq eval '.storage.nfs.export_path // ""' "${config_file}")

    if [[ -n "${nfs_server}" ]]; then
        if [[ -z "${nfs_export_path}" ]]; then
            log_error "配置了 NFS 服务器，但 export_path 为空"
            ((VALIDATION_ERRORS++))
        fi

        if ! validate_ip "${nfs_server}"; then
            log_error "NFS 服务器 IP 地址格式无效: ${nfs_server}"
            ((VALIDATION_ERRORS++))
        fi
    fi

    [[ "${VERBOSE}" == "true" ]] && log_info "存储配置验证完成"
}

# 验证路径配置
validate_paths() {
    local config_file="$1"

    # 检查并设置默认值
    local k8s_install_dir
    k8s_install_dir=$(yq eval '.global.k8s_install_dir // "/data"' "${config_file}")

    if [[ "${k8s_install_dir}" == "/data" ]] && [[ "${AUTO_FIX}" == "true" ]]; then
        log_info "设置默认安装目录: ${k8s_install_dir}"
        # 这里可以添加自动修复逻辑
    fi

    local media_source
    media_source=$(yq eval '.global.media_source // "/data/k8s_install"' "${config_file}")

    if [[ "${media_source}" == "/data/k8s_install" ]] && [[ "${AUTO_FIX}" == "true" ]]; then
        log_info "设置默认介质源目录: ${media_source}"
        # 这里可以添加自动修复逻辑
    fi

    local etcd_backup_path
    etcd_backup_path=$(yq eval '.backup.etcd.backup_path // "/data/nfs_root/etcdbackup"' "${config_file}")

    if [[ "${etcd_backup_path}" == "/data/nfs_root/etcdbackup" ]] && [[ "${AUTO_FIX}" == "true" ]]; then
        log_info "设置默认 etcd 备份路径: ${etcd_backup_path}"
        # 这里可以添加自动修复逻辑
    fi

    [[ "${VERBOSE}" == "true" ]] && log_info "路径配置验证完成"
}

# 验证容器运行时配置
validate_container_runtime() {
    local config_file="$1"

    local container_runtime
    container_runtime=$(yq eval '.packages.container_runtime // "auto"' "${config_file}")

    local kube_version
    kube_version=$(yq eval '.packages.kube_version' "${config_file}")

    case "${container_runtime}" in
        "auto")
            # 自动选择逻辑的验证
            if [[ "${kube_version}" =~ ^1\.23\. ]]; then
                log_info "Kubernetes 1.23.x 将自动选择 Docker 作为容器运行时"
            elif [[ "${kube_version}" =~ ^1\.30\. ]]; then
                log_info "Kubernetes 1.30.x 将自动选择 containerd 作为容器运行时"
            else
                log_warn "未知的 Kubernetes 版本: ${kube_version}，容器运行时选择可能不正确"
                ((VALIDATION_WARNINGS++))
            fi
            ;;
        "docker"|"containerd")
            log_info "手动指定容器运行时: ${container_runtime}"
            ;;
        *)
            log_error "不支持的容器运行时: ${container_runtime}"
            ((VALIDATION_ERRORS++))
            ;;
    esac

    [[ "${VERBOSE}" == "true" ]] && log_info "容器运行时配置验证完成"
}

# 使用 JSON Schema 验证
validate_with_schema() {
    local config_file="$1"
    local schema_file="$2"

    if [[ -z "${schema_file}" ]]; then
        [[ "${VERBOSE}" == "true" ]] && log_info "未提供 Schema 文件，跳过 Schema 验证"
        return 0
    fi

    if ! command -v ajv >/dev/null 2>&1; then
        log_warn "ajv 命令未找到，无法进行 JSON Schema 验证"
        return 0
    fi

    # 将 YAML 转换为 JSON
    local json_config
    json_config=$(yq eval -o json "${config_file}")

    if ajv validate -s "${schema_file}" -d <<< "${json_config}"; then
        log_info "JSON Schema 验证通过"
        return 0
    else
        log_error "JSON Schema 验证失败"
        ((VALIDATION_ERRORS++))
        return 1
    fi
}

# 显示验证摘要
show_validation_summary() {
    echo ""
    echo "=== 配置验证摘要 ==="

    if [[ ${VALIDATION_ERRORS} -eq 0 ]] && [[ ${VALIDATION_WARNINGS} -eq 0 ]]; then
        print_success "✅ 配置文件验证通过"
        return 0
    elif [[ ${VALIDATION_ERRORS} -eq 0 ]]; then
        print_warning "⚠️  配置文件验证通过，但有 ${VALIDATION_WARNINGS} 个警告"
        return 0
    else
        print_error "❌ 配置文件验证失败，发现 ${VALIDATION_ERRORS} 个错误"
        if [[ ${VALIDATION_WARNINGS} -gt 0 ]]; then
            print_warning "和 ${VALIDATION_WARNINGS} 个警告"
        fi
        return 1
    fi
}

# 主函数
main() {
    # 初始化日志系统
    init_logger

    # 解析参数
    parse_args "$@"

    # 生成 Schema 模式
    if [[ "${GENERATE_SCHEMA}" == "true" ]]; then
        generate_schema
        exit 0
    fi

    # 检查配置文件是否存在
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "配置文件不存在: ${CONFIG_FILE}"
        exit 1
    fi

    log_info "开始验证配置文件: ${CONFIG_FILE}"

    # 执行验证步骤
    validate_yaml_format "${CONFIG_FILE}"
    validate_required_fields "${CONFIG_FILE}"
    validate_hosts "${CONFIG_FILE}"
    validate_networking "${CONFIG_FILE}"
    validate_storage "${CONFIG_FILE}"
    validate_paths "${CONFIG_FILE}"
    validate_container_runtime "${CONFIG_FILE}"
    validate_with_schema "${CONFIG_FILE}" "${SCHEMA_FILE}"

    # 显示摘要
    show_validation_summary

    # 在严格模式下，警告也视为错误
    if [[ "${STRICT}" == "true" ]] && [[ ${VALIDATION_WARNINGS} -gt 0 ]]; then
        exit 1
    fi

    # 如果有错误，退出码为 1
    [[ ${VALIDATION_ERRORS} -eq 0 ]]
}

# 执行主函数
main "$@"