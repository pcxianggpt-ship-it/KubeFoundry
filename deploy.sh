#!/bin/bash

if [ "${KF_DEPLOY_BASH_REEXEC:-0}" != "1" ]; then
    command -v bash >/dev/null 2>&1 || { echo "错误：deploy.sh 需要 Bash。" >&2; exit 1; }
    KF_DEPLOY_BASH_REEXEC=1 exec bash "$0" "$@"
fi
unset KF_DEPLOY_BASH_REEXEC

#===============================================================================
# 脚本名称：deploy.sh
# 功能：部署 KubeFoundry v0.2.0 Java Web 服务
# 作者：KubeFoundry Team
# 版本：2.0.0
#===============================================================================

set -euo pipefail

SERVICE_NAME="kubefoundry-web"
DEPLOY_ROOT="$(pwd -P)"
APP_DIR="${DEPLOY_ROOT}/app"
DATA_DIR="${DEPLOY_ROOT}/data"
LOG_DIR="${DEPLOY_ROOT}/logs"
PORT="10001"
PACKAGE_FILE=""
ACTION="deploy"
TEST_MODE="${KF_DEPLOY_TEST_MODE:-0}"
TEMP_DIR=""

log_info() { printf '[INFO] %s\n' "$*" | tee -a "${LOG_DIR}/deploy.log"; }
log_success() { printf '[SUCCESS] %s\n' "$*" | tee -a "${LOG_DIR}/deploy.log"; }
log_error() { printf '[ERROR] %s\n' "$*" | tee -a "${LOG_DIR}/deploy.log" >&2; }

show_usage() {
    cat <<'EOF'
KubeFoundry v0.2.0 Java Web 一键部署脚本

用法:
  sudo bash deploy.sh [--port PORT] kubefoundry-web-v0.2.0-<架构>.tar.gz
  sudo bash deploy.sh --status|--restart|--stop|--uninstall

选项:
  --port PORT     服务监听端口，默认 10001
  --status        查看服务状态
  --restart       重启服务
  --stop          停止服务
  --uninstall     删除 systemd 服务，保留 app、data、logs 和 scripts
EOF
}

cleanup() {
    [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ] && rm -rf "${TEMP_DIR}"
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

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --port) [ "$#" -ge 2 ] || { echo "--port 缺少端口值" >&2; return 1; }; PORT="$2"; shift 2 ;;
            --status|--restart|--stop|--uninstall) ACTION="${1#--}"; shift ;;
            -h|--help) show_usage; exit 0 ;;
            -*) echo "未知选项: $1" >&2; return 1 ;;
            *) [ -z "${PACKAGE_FILE}" ] || { echo "只能指定一个发布包" >&2; return 1; }; PACKAGE_FILE="$1"; shift ;;
        esac
    done
    case "${PORT}" in ''|*[!0-9]*) echo "无效端口: ${PORT}" >&2; return 1 ;; esac
    [ "${PORT}" -ge 1 ] && [ "${PORT}" -le 65535 ] || { echo "无效端口: ${PORT}" >&2; return 1; }
}

run_service_action() {
    if [ "${TEST_MODE}" = "1" ]; then log_info "测试模式跳过 systemd 操作: ${ACTION}"; return; fi
    case "${ACTION}" in
        status) systemctl status "${SERVICE_NAME}" --no-pager ;;
        restart) systemctl restart "${SERVICE_NAME}"; systemctl status "${SERVICE_NAME}" --no-pager ;;
        stop) systemctl stop "${SERVICE_NAME}" ;;
        uninstall)
            systemctl disable --now "${SERVICE_NAME}" 2>/dev/null || true
            rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
            systemctl daemon-reload
            log_success "服务已卸载，业务数据和程序文件已保留"
            ;;
    esac
}

check_environment() {
    [ "${TEST_MODE}" = "1" ] || [ "$(id -u)" -eq 0 ] || { log_error "部署 systemd 服务需要 root 权限"; return 1; }
    for name in tar sha256sum; do command -v "${name}" >/dev/null 2>&1 || { log_error "缺少命令: ${name}"; return 1; }; done
    [ -n "${PACKAGE_FILE}" ] || { log_error "请指定发布包"; return 1; }
    PACKAGE_FILE="$(cd "$(dirname "${PACKAGE_FILE}")" && pwd -P)/$(basename "${PACKAGE_FILE}")"
    [ -f "${PACKAGE_FILE}" ] || { log_error "发布包不存在: ${PACKAGE_FILE}"; return 1; }
}

validate_archive_entries() {
    local entry
    while IFS= read -r entry; do
        case "${entry}" in /*|../*|*/../*|*/..) log_error "压缩包包含不安全路径: ${entry}"; return 1 ;; esac
    done < <(tar -tzf "${PACKAGE_FILE}")
}

extract_and_validate_package() {
    TEMP_DIR="$(mktemp -d)"
    tar -xzf "${PACKAGE_FILE}" -C "${TEMP_DIR}"
    local release_dir package_arch host_arch
    release_dir="$(find "${TEMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "${release_dir}" ] || { log_error "发布包中未找到发布目录"; return 1; }
    for path in runtime/bin/java runtime/.architecture app/kubefoundry.jar web/index.html scripts/steps deploy.sh VERSION ARCHITECTURE SHA256SUMS; do
        [ -e "${release_dir}/${path}" ] || { log_error "发布包缺少: ${path}"; return 1; }
    done
    (cd "${release_dir}" && sha256sum -c SHA256SUMS >/dev/null) || { log_error "发布包文件校验失败"; return 1; }
    package_arch="$(normalize_arch "$(cat "${release_dir}/ARCHITECTURE")")" || { log_error "发布包架构无效"; return 1; }
    [ "$(cat "${release_dir}/runtime/.architecture")" = "${package_arch}" ] || { log_error "运行时架构标记不一致"; return 1; }
    host_arch="$(normalize_arch "${KF_TEST_HOST_ARCH:-$(uname -m)}")" || { log_error "不支持当前服务器架构"; return 1; }
    [ "${package_arch}" = "${host_arch}" ] || { log_error "发布包与服务器架构不匹配: ${package_arch} != ${host_arch}"; return 1; }
    if [ -f "${release_dir}/runtime/.test-runtime" ] && [ "${TEST_MODE}" != "1" ]; then
        log_error "测试运行时不能用于生产部署"
        return 1
    fi
    printf '%s\n' "${release_dir}"
}

install_release() {
    local release_dir="$1" new_app="${DEPLOY_ROOT}/.app.new.$$"
    rm -rf "${new_app}"
    mkdir -p "${new_app}" "${DATA_DIR}" "${LOG_DIR}"
    chmod 0700 "${DATA_DIR}" "${LOG_DIR}"
    cp -a "${release_dir}/runtime" "${release_dir}/app" "${release_dir}/web" "${new_app}/"
    cp "${release_dir}/VERSION" "${release_dir}/ARCHITECTURE" "${new_app}/"
    rm -rf "${DEPLOY_ROOT}/scripts.new"
    cp -a "${release_dir}/scripts" "${DEPLOY_ROOT}/scripts.new"
    rm -rf "${DEPLOY_ROOT}/scripts"
    mv "${DEPLOY_ROOT}/scripts.new" "${DEPLOY_ROOT}/scripts"
    rm -rf "${APP_DIR}"
    mv "${new_app}" "${APP_DIR}"
}

write_service_file() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    [ "${TEST_MODE}" = "1" ] && service_file="${LOG_DIR}/${SERVICE_NAME}.service.test"
    cat > "${service_file}" <<EOF
[Unit]
Description=KubeFoundry v0.2.0 Web Wizard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
Environment=KF_DATA_DIR=${DATA_DIR}
Environment=KF_LOG_DIR=${LOG_DIR}
Environment=KF_WEB_DIR=${APP_DIR}/web
ExecStart=${APP_DIR}/runtime/bin/java -jar ${APP_DIR}/app/kubefoundry.jar --server.port=${PORT}
Restart=on-failure
RestartSec=5
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF
}

start_service() {
    if [ "${TEST_MODE}" = "1" ]; then log_info "测试模式跳过服务启动和健康检查"; return; fi
    command -v curl >/dev/null 2>&1 || { log_error "健康检查需要 curl"; return 1; }
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}" >/dev/null
    systemctl restart "${SERVICE_NAME}"
    local attempt
    for attempt in $(seq 1 60); do
        if curl -fsS "http://127.0.0.1:${PORT}/api/health" | grep -q '"status":"ok"'; then
            log_success "KubeFoundry Web 已启动，监听端口 ${PORT}"
            return
        fi
        sleep 1
    done
    log_error "服务健康检查超时"
    journalctl -u "${SERVICE_NAME}" -n 100 --no-pager >&2 || true
    systemctl status "${SERVICE_NAME}" --no-pager >&2 || true
    return 1
}

main() {
    parse_arguments "$@"
    mkdir -p "${LOG_DIR}"
    if [ "${ACTION}" != "deploy" ]; then run_service_action; return; fi
    check_environment
    validate_archive_entries
    local release_dir
    release_dir="$(extract_and_validate_package)"
    log_info "部署目录: ${DEPLOY_ROOT}"
    log_info "发布版本: $(cat "${release_dir}/VERSION")"
    install_release "${release_dir}"
    write_service_file
    start_service
}

main "$@"
