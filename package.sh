#!/bin/bash

if [ "${KF_PACKAGE_BASH_REEXEC:-0}" != "1" ]; then
    if ! command -v bash >/dev/null 2>&1; then
        echo "错误：package.sh 需要 Bash，请安装 Bash 后执行。" >&2
        exit 1
    fi
    KF_PACKAGE_BASH_REEXEC=1
    export KF_PACKAGE_BASH_REEXEC
    exec bash "$0" "$@"
fi
unset KF_PACKAGE_BASH_REEXEC

#===============================================================================
# 脚本名称：package.sh
# 功能：构建 KubeFoundry Web 前后端并生成离线部署压缩包
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
DIST_DIR="${PROJECT_ROOT}/dist"
TEST_MODE="${KF_PACKAGE_TEST_MODE:-0}"
STAGING_ROOT=""

log_info() {
    printf '[INFO] %s\n' "$*"
}

log_success() {
    printf '[SUCCESS] %s\n' "$*"
}

log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

show_usage() {
    cat <<'EOF'
KubeFoundry Web 一键打包脚本

用法:
  bash package.sh

输出:
  dist/kubefoundry-web-v<版本>.tar.gz

打包内容:
  已构建前端、Python 后端、纯 Python 离线依赖、deploy.sh 和安装步骤脚本
EOF
}

cleanup() {
    if [ -n "${STAGING_ROOT}" ] && [ -d "${STAGING_ROOT}" ]; then
        rm -rf "${STAGING_ROOT}"
    fi
}
trap cleanup EXIT

read_version() {
    sed -n 's/^__version__ = "\([^"]*\)"/\1/p' \
        "${PROJECT_ROOT}/web/backend/kubefoundry/__init__.py"
}

check_project() {
    for path in \
        web/backend/app.py \
        web/backend/requirements.txt \
        web/frontend/package.json \
        deploy.sh \
        scripts/steps; do
        [ -e "${PROJECT_ROOT}/${path}" ] || {
            log_error "项目文件缺失: ${path}"
            return 1
        }
    done
}

check_commands() {
    local commands=(tar sha256sum)
    if [ "${TEST_MODE}" != "1" ]; then
        commands+=(python3)
    fi
    local command_name
    for command_name in "${commands[@]}"; do
        command -v "${command_name}" >/dev/null 2>&1 || {
            log_error "缺少命令: ${command_name}"
            return 1
        }
    done
}

build_frontend() {
    local release_dir="$1"
    if [ "${TEST_MODE}" = "1" ]; then
        mkdir -p "${release_dir}/frontend-dist"
        printf '<html>KubeFoundry test package</html>\n' \
            > "${release_dir}/frontend-dist/index.html"
        return 0
    fi

    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        log_info "安装前端依赖并执行测试..."
        (
            cd "${PROJECT_ROOT}/web/frontend"
            npm ci
            npm test
            npm run build
        )
    elif [ -f "${PROJECT_ROOT}/web/frontend/dist/index.html" ]; then
        log_info "未找到 Node.js/npm，使用已有前端构建产物"
    else
        log_error "未找到 Node.js/npm，且 web/frontend/dist 不存在"
        return 1
    fi
    cp -a "${PROJECT_ROOT}/web/frontend/dist" "${release_dir}/frontend-dist"
}

collect_backend() {
    local release_dir="$1"
    if [ "${TEST_MODE}" = "1" ]; then
        mkdir -p "${release_dir}/backend/kubefoundry"
        printf '%s\n' '#!/usr/bin/env python3' > "${release_dir}/backend/app.py"
        printf '%s\n' '__version__ = "0.1.0"' \
            > "${release_dir}/backend/kubefoundry/__init__.py"
    else
        cp -a "${PROJECT_ROOT}/web/backend" "${release_dir}/backend"
        find "${release_dir}/backend" -type d -name __pycache__ -prune -exec rm -rf {} +
        find "${release_dir}/backend" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
    fi

    cp "${PROJECT_ROOT}/web/backend/requirements.txt" "${release_dir}/requirements.txt"
    cp "${PROJECT_ROOT}/deploy.sh" "${release_dir}/deploy.sh"
    cp -a "${PROJECT_ROOT}/scripts" "${release_dir}/scripts"
}

collect_python_dependencies() {
    local release_dir="$1"
    mkdir -p "${release_dir}/vendor"
    if [ "${TEST_MODE}" = "1" ]; then
        : > "${release_dir}/vendor/.keep"
        return 0
    fi

    log_info "收集纯 Python 后端依赖..."
    PYYAML_FORCE_LIBYAML=0 PIP_ROOT_USER_ACTION=ignore python3 -m pip install \
        --disable-pip-version-check \
        --ignore-installed \
        --no-warn-conflicts \
        --target "${release_dir}/vendor" \
        --requirement "${PROJECT_ROOT}/web/backend/requirements.txt"

    find "${release_dir}/vendor" -type d -name __pycache__ -prune -exec rm -rf {} +
    find "${release_dir}/vendor" -type f \
        \( -name '*.pyc' -o -name '*.pyo' -o -name '*.so' -o -name '*.pyd' -o -name '*.dll' \) \
        -delete

    if find "${release_dir}/vendor" -type f \
        \( -name '*.so' -o -name '*.pyd' -o -name '*.dll' \) |
        grep -q .; then
        log_error "vendor 目录仍包含架构相关二进制文件"
        return 1
    fi
}

generate_checksums() {
    local release_dir="$1"
    (
        cd "${release_dir}"
        find . -type f ! -name SHA256SUMS -print0 |
            sort -z |
            xargs -0 sha256sum > SHA256SUMS
    )
}

create_archive() {
    local version="$1"
    local release_name="kubefoundry-web-v${version}"
    local release_dir="${STAGING_ROOT}/${release_name}"
    local archive="${DIST_DIR}/${release_name}.tar.gz"

    mkdir -p "${release_dir}" "${DIST_DIR}"
    build_frontend "${release_dir}"
    collect_backend "${release_dir}"
    collect_python_dependencies "${release_dir}"
    printf '%s\n' "${version}" > "${release_dir}/VERSION"
    generate_checksums "${release_dir}"

    rm -f "${archive}"
    tar -czf "${archive}" -C "${STAGING_ROOT}" "${release_name}"
    tar -tzf "${archive}" >/dev/null

    log_success "发布包已生成: ${archive}"
    log_info "SHA-256: $(sha256sum "${archive}" | awk '{print $1}')"
}

main() {
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        show_usage
        return 0
    fi
    [ "$#" -eq 0 ] || {
        show_usage >&2
        return 1
    }

    check_project
    check_commands

    local version
    version="$(read_version)"
    [ -n "${version}" ] || {
        log_error "无法读取版本号"
        return 1
    }

    STAGING_ROOT="$(mktemp -d)"
    create_archive "${version}"
}

main "$@"
