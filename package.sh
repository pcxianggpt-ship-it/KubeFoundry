#!/bin/bash

if [ "${KF_PACKAGE_BASH_REEXEC:-0}" != "1" ]; then
    command -v bash >/dev/null 2>&1 || { echo "错误：package.sh 需要 Bash。" >&2; exit 1; }
    KF_PACKAGE_BASH_REEXEC=1 exec bash "$0" "$@"
fi
unset KF_PACKAGE_BASH_REEXEC

#===============================================================================
# 脚本名称：package.sh
# 功能：构建 KubeFoundry v0.3.0 Java 双架构离线部署包
# 作者：KubeFoundry Team
# 版本：2.0.0
#===============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${KF_DIST_DIR:-${PROJECT_ROOT}/dist}"
TARGET_ARCH="${KF_TARGET_ARCH:-}"
TEST_MODE="${KF_PACKAGE_TEST_MODE:-0}"
BUILD_OFFLINE="${KF_BUILD_OFFLINE:-0}"
USE_PREBUILT="${KF_USE_PREBUILT:-0}"
STAGING_ROOT=""
BACKEND_BUILD_ROOT=""
FRONTEND_BUILD_ROOT=""

log_info() { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[SUCCESS] %s\n' "$*"; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }

show_usage() {
    cat <<'EOF'
KubeFoundry v0.3.0 Java 离线包构建脚本

用法:
  KF_TARGET_ARCH=x86_64 bash package.sh
  KF_TARGET_ARCH=aarch64 bash package.sh

输出:
  dist/kubefoundry-web-v0.3.0-{x86_64|aarch64}.tar.gz

说明:
  使用 JDK 17 构建；交叉构建时必须通过 KF_TARGET_JDK_HOME 提供真实目标架构 JDK。
  已有测试通过的 JAR 和前端产物时，可设置 KF_USE_PREBUILT=1 完成离线归档。
EOF
}

cleanup() {
    [ -n "${STAGING_ROOT}" ] && [ -d "${STAGING_ROOT}" ] && rm -rf "${STAGING_ROOT}"
    [ -n "${BACKEND_BUILD_ROOT}" ] && [ -d "${BACKEND_BUILD_ROOT}" ] && rm -rf "${BACKEND_BUILD_ROOT}"
    [ -n "${FRONTEND_BUILD_ROOT}" ] && [ -d "${FRONTEND_BUILD_ROOT}" ] && rm -rf "${FRONTEND_BUILD_ROOT}"
    return 0
}
trap cleanup EXIT

normalize_arch() {
    case "$1" in
        x86_64|amd64) printf 'x86_64\n' ;;
        aarch64|arm64) printf 'aarch64\n' ;;
        *) return 1 ;;
    esac
}

read_version() {
    sed -n '/<artifactId>kubefoundry-backend<\/artifactId>/{n;s/.*<version>\([^<]*\)<\/version>.*/\1/p;q;}' \
        "${PROJECT_ROOT}/web/backend-java/pom.xml"
}

check_environment() {
    TARGET_ARCH="$(normalize_arch "${TARGET_ARCH}")" || {
        log_error "KF_TARGET_ARCH 必须是 x86_64 或 aarch64"
        return 1
    }
    for name in tar sha256sum; do
        command -v "${name}" >/dev/null 2>&1 || { log_error "缺少命令: ${name}"; return 1; }
    done
    for path in web/backend-java/pom.xml web/frontend/package.json deploy.sh scripts/steps scripts/verify/reset/verify-reset-kubernetes-node.sh scripts/steps/reset/reset-kubemate-components.sh scripts/build/build-jre.sh tools/helm-amd tools/helm-arm; do
        [ -e "${PROJECT_ROOT}/${path}" ] || { log_error "项目文件缺失: ${path}"; return 1; }
    done
}

build_application() {
    local release_dir="$1"
    mkdir -p "${release_dir}/app" "${release_dir}/web"
    if [ "${TEST_MODE}" = "1" ]; then
        printf 'test jar\n' > "${release_dir}/app/kubefoundry.jar"
        printf '<!doctype html><html><body>KubeFoundry v0.3.0</body></html>\n' > "${release_dir}/web/index.html"
        return
    fi

    if [ "${USE_PREBUILT}" = "1" ]; then
        local jar="${PROJECT_ROOT}/web/backend-java/target/kubefoundry-backend-0.3.0.jar"
        local web="${PROJECT_ROOT}/web/frontend/dist"
        [ -f "${jar}" ] || { log_error "预构建 JAR 不存在: ${jar}"; return 1; }
        [ -f "${web}/index.html" ] || { log_error "预构建前端不存在: ${web}/index.html"; return 1; }
        cp "${jar}" "${release_dir}/app/kubefoundry.jar"
        cp -a "${web}/." "${release_dir}/web/"
        return
    fi

    command -v mvn >/dev/null 2>&1 || { log_error "缺少 Maven"; return 1; }
    command -v npm >/dev/null 2>&1 || { log_error "缺少 npm"; return 1; }
    if [ -n "${KF_JAVA_HOME:-}" ]; then
        export JAVA_HOME="${KF_JAVA_HOME}"
        export PATH="${JAVA_HOME}/bin:${PATH}"
    fi
    local maven_args=(clean test package)
    local npm_ci_args=(ci)
    if [ "${BUILD_OFFLINE}" = "1" ]; then
        maven_args=(-o "${maven_args[@]}")
        npm_ci_args+=(--offline)
    fi
    log_info "构建并测试 Java 后端..."
    # 在临时目录编译，避免 WSL 与 Windows 共用 target 时无法清理被占用的文件。
    BACKEND_BUILD_ROOT="$(mktemp -d)"
    local backend_project_dir="${BACKEND_BUILD_ROOT}/project"
    local backend_build_dir="${backend_project_dir}/web/backend-java"
    mkdir -p "${backend_build_dir}" "${backend_project_dir}/scripts"
    (
        cd "${PROJECT_ROOT}/web/backend-java"
        tar --exclude='./target' -cf - .
    ) | (
        cd "${backend_build_dir}"
        tar -xf -
    )
    cp -a "${PROJECT_ROOT}/scripts/steps" "${backend_project_dir}/scripts/steps"
    cp -a "${PROJECT_ROOT}/scripts/verify" "${backend_project_dir}/scripts/verify"
    (cd "${backend_build_dir}" && mvn -q "${maven_args[@]}")
    log_info "构建并测试 Vue 前端..."
    # 在临时目录安装依赖，避免 WSL 与 Windows 共用 node_modules 时互相覆盖平台二进制文件。
    FRONTEND_BUILD_ROOT="$(mktemp -d)"
    local frontend_build_dir="${FRONTEND_BUILD_ROOT}/frontend"
    mkdir -p "${frontend_build_dir}"
    (
        cd "${PROJECT_ROOT}/web/frontend"
        tar --exclude='./node_modules' --exclude='./dist' -cf - .
    ) | (
        cd "${frontend_build_dir}"
        tar -xf -
    )
    (cd "${frontend_build_dir}" && npm "${npm_ci_args[@]}" && npm test && npm run build)
    cp "${backend_build_dir}/target/kubefoundry-backend-0.3.0.jar" \
        "${release_dir}/app/kubefoundry.jar"
    cp -a "${frontend_build_dir}/dist/." "${release_dir}/web/"
}

copy_helm_media() {
    local release_dir="$1"
    mkdir -p "${release_dir}/tools"
    if [ "${TEST_MODE}" = "1" ]; then
        printf '%s\n' 'test helm amd64' > "${release_dir}/tools/helm-amd"
        printf '%s\n' 'test helm arm64' > "${release_dir}/tools/helm-arm"
    else
        cp "${PROJECT_ROOT}/tools/helm-amd" "${PROJECT_ROOT}/tools/helm-arm" "${release_dir}/tools/"
    fi
    chmod 0755 "${release_dir}/tools/helm-amd" "${release_dir}/tools/helm-arm"
}

build_runtime() {
    local release_dir="$1"
    KF_TARGET_ARCH="${TARGET_ARCH}" KF_PACKAGE_TEST_MODE="${TEST_MODE}" \
        KF_TARGET_JDK_HOME="${KF_TARGET_JDK_HOME:-${KF_JAVA_HOME:-${JAVA_HOME:-}}}" \
        bash "${PROJECT_ROOT}/scripts/build/build-jre.sh" "${release_dir}/runtime"
}

generate_checksums() {
    local release_dir="$1"
    (cd "${release_dir}" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
}

create_archive() {
    local version="$1"
    local release_name="kubefoundry-web-v${version}-${TARGET_ARCH}"
    local release_dir="${STAGING_ROOT}/${release_name}"
    local archive="${DIST_DIR}/${release_name}.tar.gz"
    mkdir -p "${release_dir}/scripts" "${DIST_DIR}"

    build_application "${release_dir}"
    build_runtime "${release_dir}"
    copy_helm_media "${release_dir}"
    cp -a "${PROJECT_ROOT}/scripts/steps" "${release_dir}/scripts/steps"
    cp -a "${PROJECT_ROOT}/scripts/verify" "${release_dir}/scripts/verify"
    cp "${PROJECT_ROOT}/deploy.sh" "${release_dir}/deploy.sh"
    chmod 0755 "${release_dir}/deploy.sh" "${release_dir}/runtime/bin/java"
    printf '%s\n' "${version}" > "${release_dir}/VERSION"
    printf '%s\n' "${TARGET_ARCH}" > "${release_dir}/ARCHITECTURE"
    generate_checksums "${release_dir}"

    rm -f "${archive}"
    tar -czf "${archive}" -C "${STAGING_ROOT}" "${release_name}"
    tar -tzf "${archive}" >/dev/null
    log_success "发布包已生成: ${archive}"
    log_info "SHA-256: $(sha256sum "${archive}" | awk '{print $1}')"
}

main() {
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then show_usage; return; fi
    [ "$#" -eq 0 ] || { show_usage >&2; return 1; }
    check_environment
    local version
    version="$(read_version)"
    [ "${version}" = "0.3.0" ] || { log_error "后端版本必须为 0.3.0，实际为 ${version:-未知}"; return 1; }
    STAGING_ROOT="$(mktemp -d)"
    create_archive "${version}"
}

main "$@"
