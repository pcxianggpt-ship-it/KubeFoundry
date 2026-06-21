#!/bin/bash

#===============================================================================
# 脚本名称：deploy.sh
# 功能：从 KubeFoundry Web 离线包一键部署生产服务
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

set -euo pipefail

DEFAULT_PORT="10001"
SERVICE_NAME="kubefoundry-web"
DEPLOY_ROOT="$(pwd -P)"
APP_DIR="${DEPLOY_ROOT}/app"
DATA_DIR="${DEPLOY_ROOT}/data"
LOG_DIR="${DEPLOY_ROOT}/logs"
PYTHON_BIN=""
PORT="${DEFAULT_PORT}"
PACKAGE_FILE=""
ACTION="deploy"
TEST_MODE="${KF_DEPLOY_TEST_MODE:-0}"
TEMP_DIR=""

log_info() {
    printf '[INFO] %s\n' "$*" | tee -a "${LOG_DIR:-/tmp}/deploy.log"
}

log_success() {
    printf '[SUCCESS] %s\n' "$*" | tee -a "${LOG_DIR:-/tmp}/deploy.log"
}

log_error() {
    printf '[ERROR] %s\n' "$*" | tee -a "${LOG_DIR:-/tmp}/deploy.log" >&2
}

show_usage() {
    cat <<'EOF'
KubeFoundry Web 一键部署脚本

用法:
  sudo bash deploy.sh [选项] <kubefoundry-web-v*.tar.gz>
  sudo bash deploy.sh --status|--restart|--stop|--uninstall

选项:
  --port PORT     服务监听端口，默认 10001
  --status        查看服务状态
  --restart       重启服务
  --stop          停止服务
  --uninstall     删除 systemd 服务，保留 app、data 和 logs
  -h, --help      显示帮助
EOF
}

cleanup() {
    if [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --port)
                [ "$#" -ge 2 ] || {
                    echo "--port 缺少端口值" >&2
                    return 1
                }
                PORT="$2"
                shift 2
                ;;
            --status)
                ACTION="status"
                shift
                ;;
            --restart)
                ACTION="restart"
                shift
                ;;
            --stop)
                ACTION="stop"
                shift
                ;;
            --uninstall)
                ACTION="uninstall"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                echo "未知选项: $1" >&2
                return 1
                ;;
            *)
                [ -z "${PACKAGE_FILE}" ] || {
                    echo "只能指定一个发布压缩包" >&2
                    return 1
                }
                PACKAGE_FILE="$1"
                shift
                ;;
        esac
    done

    [[ "${PORT}" =~ ^[0-9]+$ ]] && [ "${PORT}" -ge 1 ] && [ "${PORT}" -le 65535 ] || {
        echo "无效端口: ${PORT}" >&2
        return 1
    }
}

run_service_action() {
    if [ "${TEST_MODE}" = "1" ]; then
        log_info "测试模式跳过 systemd 操作: ${ACTION}"
        return 0
    fi

    case "${ACTION}" in
        status)
            systemctl status "${SERVICE_NAME}" --no-pager
            ;;
        restart)
            systemctl restart "${SERVICE_NAME}"
            systemctl status "${SERVICE_NAME}" --no-pager
            ;;
        stop)
            systemctl stop "${SERVICE_NAME}"
            ;;
        uninstall)
            systemctl disable --now "${SERVICE_NAME}" 2>/dev/null || true
            rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
            systemctl daemon-reload
            log_success "服务已卸载，app、data 和 logs 已保留"
            ;;
    esac
}

check_environment() {
    if [ "${TEST_MODE}" != "1" ] && [ "$(id -u)" -ne 0 ]; then
        log_error "安装 systemd 服务需要 root 权限，请使用 sudo 执行"
        return 1
    fi

    for command_name in tar sha256sum; do
        command -v "${command_name}" >/dev/null 2>&1 || {
            log_error "缺少命令: ${command_name}"
            return 1
        }
    done

    PYTHON_BIN="$(command -v python3 || true)"
    [ -n "${PYTHON_BIN}" ] || {
        log_error "未找到 python3"
        return 1
    }

    "${PYTHON_BIN}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 7) else 1)' || {
        log_error "Python 版本必须为 3.7 或更高"
        return 1
    }

    [ -n "${PACKAGE_FILE}" ] || {
        log_error "请指定发布压缩包"
        return 1
    }
    PACKAGE_FILE="$(cd "$(dirname "${PACKAGE_FILE}")" && pwd -P)/$(basename "${PACKAGE_FILE}")"
    [ -f "${PACKAGE_FILE}" ] || {
        log_error "发布压缩包不存在: ${PACKAGE_FILE}"
        return 1
    }
}

validate_archive_entries() {
    local entry
    while IFS= read -r entry; do
        case "${entry}" in
            /*|../*|*/../*|*/..)
                log_error "压缩包包含不安全路径: ${entry}"
                return 1
                ;;
        esac
    done < <(tar -tzf "${PACKAGE_FILE}")
}

extract_and_validate_package() {
    TEMP_DIR="$(mktemp -d)"
    tar -xzf "${PACKAGE_FILE}" -C "${TEMP_DIR}"

    local release_dir
    release_dir="$(find "${TEMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "${release_dir}" ] || {
        log_error "压缩包中未找到发布目录"
        return 1
    }

    for path in backend frontend-dist vendor requirements.txt VERSION SHA256SUMS; do
        [ -e "${release_dir}/${path}" ] || {
            log_error "发布包缺少: ${path}"
            return 1
        }
    done

    (
        cd "${release_dir}"
        sha256sum -c SHA256SUMS >/dev/null
    ) || {
        log_error "发布包文件校验失败"
        return 1
    }

    printf '%s\n' "${release_dir}"
}

write_production_wsgi() {
    cat > "${APP_DIR}/backend/production_wsgi.py" <<'PYTHON'
import mimetypes
import os

from flask import jsonify, send_from_directory

from kubefoundry.api.routes import create_app


FRONTEND_DIST = os.environ["KF_FRONTEND_DIST"]
application = create_app()


@application.route("/", defaults={"path": ""})
@application.route("/<path:path>")
def frontend(path):
    if path.startswith("api/"):
        return jsonify({"error": "not found"}), 404
    candidate = os.path.join(FRONTEND_DIST, path)
    if path and os.path.isfile(candidate):
        mimetypes.add_type("application/javascript", ".js")
        return send_from_directory(FRONTEND_DIST, path)
    index_path = os.path.join(FRONTEND_DIST, "index.html")
    if os.path.isfile(index_path):
        return send_from_directory(FRONTEND_DIST, "index.html")
    return jsonify({"error": "frontend assets not found"}), 404
PYTHON
}

install_release() {
    local release_dir="$1"
    local new_app="${DEPLOY_ROOT}/.app.new.$$"

    rm -rf "${new_app}"
    mkdir -p "${new_app}" "${DATA_DIR}" "${LOG_DIR}"
    cp -a "${release_dir}/backend" "${new_app}/backend"
    cp -a "${release_dir}/frontend-dist" "${new_app}/frontend-dist"
    cp -a "${release_dir}/vendor" "${new_app}/vendor"
    cp "${release_dir}/requirements.txt" "${release_dir}/VERSION" "${new_app}/"

    if [ -d "${release_dir}/scripts" ]; then
        rm -rf "${DEPLOY_ROOT}/scripts.new"
        cp -a "${release_dir}/scripts" "${DEPLOY_ROOT}/scripts.new"
        rm -rf "${DEPLOY_ROOT}/scripts"
        mv "${DEPLOY_ROOT}/scripts.new" "${DEPLOY_ROOT}/scripts"
    fi

    rm -rf "${APP_DIR}"
    mv "${new_app}" "${APP_DIR}"
    write_production_wsgi

    PYTHONPATH="${APP_DIR}/vendor:${APP_DIR}/backend" \
        KF_DB_PATH="${DATA_DIR}/kubefoundry.db" \
        KF_DATA_DIR="${DATA_DIR}" \
        "${PYTHON_BIN}" "${APP_DIR}/backend/app.py" --init-db
}

write_service_file() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    if [ "${TEST_MODE}" = "1" ]; then
        service_file="${LOG_DIR}/${SERVICE_NAME}.service.test"
    fi

    cat > "${service_file}" <<EOF
[Unit]
Description=KubeFoundry Web Wizard
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}/backend
Environment=PYTHONPATH=${APP_DIR}/vendor:${APP_DIR}/backend
Environment=KF_DB_PATH=${DATA_DIR}/kubefoundry.db
Environment=KF_DATA_DIR=${DATA_DIR}
Environment=KF_FRONTEND_DIST=${APP_DIR}/frontend-dist
ExecStart=${PYTHON_BIN} -m gunicorn --workers 1 --threads 4 --bind 0.0.0.0:${PORT} --access-logfile ${LOG_DIR}/access.log --error-logfile ${LOG_DIR}/error.log production_wsgi:application
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

start_service() {
    if [ "${TEST_MODE}" = "1" ]; then
        log_info "测试模式跳过服务启动和健康检查"
        return 0
    fi

    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}"
    systemctl restart "${SERVICE_NAME}"

    local attempt
    for attempt in $(seq 1 30); do
        if "${PYTHON_BIN}" -c \
            "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${PORT}/api/health', timeout=2).read()" \
            >/dev/null 2>&1; then
            log_success "KubeFoundry Web 已启动: http://$(hostname -I | awk '{print $1}'):${PORT}/"
            return 0
        fi
        sleep 1
    done

    log_error "服务健康检查超时"
    systemctl status "${SERVICE_NAME}" --no-pager || true
    return 1
}

main() {
    parse_arguments "$@"
    mkdir -p "${LOG_DIR}"

    if [ "${ACTION}" != "deploy" ]; then
        run_service_action
        return $?
    fi

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
