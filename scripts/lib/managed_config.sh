#!/bin/bash

#===============================================================================
# 脚本名称：managed_config.sh
# 功能：管理 KubeFoundry 标记块和需整体替换的系统配置
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

KF_MANAGED_STATE_DIR="${KF_MANAGED_STATE_DIR:-/var/lib/kubefoundry/managed-config}"
KF_MANAGED_MANIFEST="${KF_MANAGED_STATE_DIR}/manifest.tsv"

_kf_validate_text() {
    case "$1" in
        *$'\n'*|*$'\r'*|*$'\t'*) return 1 ;;
    esac
}

_kf_validate_target() {
    local target="$1"
    [ "${target#/}" != "${target}" ] || return 1
    _kf_validate_text "${target}" || return 1
    [ ! -L "${target}" ] || return 1
}

_kf_validate_key() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9._-]*$ ]]
}

kf_sha256() {
    sha256sum "$1" | awk '{print $1}'
}

kf_require_owned_or_absent() {
    local target="$1" marker="${2:-# Managed by KubeFoundry v0.3.2}"
    _kf_validate_target "${target}" || return 1
    [ ! -e "${target}" ] && return 0
    [ -f "${target}" ] || return 1
    [ "$(head -n 1 "${target}")" = "${marker}" ]
}

kf_prepare_state_directory() {
    [ ! -L "${KF_MANAGED_STATE_DIR}" ] || return 1
    mkdir -p "${KF_MANAGED_STATE_DIR}/baseline"
    chmod 0700 "${KF_MANAGED_STATE_DIR}" "${KF_MANAGED_STATE_DIR}/baseline"
    if [ ! -e "${KF_MANAGED_MANIFEST}" ]; then
        : > "${KF_MANAGED_MANIFEST}"
    fi
    [ -f "${KF_MANAGED_MANIFEST}" ] && [ ! -L "${KF_MANAGED_MANIFEST}" ] || return 1
    chmod 0600 "${KF_MANAGED_MANIFEST}"
}

_kf_manifest_line() {
    local key="$1"
    awk -F '\t' -v key="${key}" '$1 == key { print; found = 1 } END { exit(found ? 0 : 1) }' \
        "${KF_MANAGED_MANIFEST}"
}

kf_prepare_replacement() {
    local target="$1" key="$2" expected="${3:-}" line original backup managed current
    local original_mode original_uid original_gid
    _kf_validate_target "${target}" || return 1
    _kf_validate_key "${key}" || return 1
    kf_prepare_state_directory || return 1

    if line="$(_kf_manifest_line "${key}")"; then
        IFS=$'\t' read -r _ recorded_target original backup managed \
            original_mode original_uid original_gid <<< "${line}"
        [ "${recorded_target}" = "${target}" ] || return 1
        if [ "${managed}" = "PENDING" ]; then
            [ "${original}" = "ABSENT" ] && [ ! -e "${target}" ] && return 0
            [ -f "${target}" ] || return 1
            current="$(kf_sha256 "${target}")"
            [ "${current}" = "${original}" ] && return 0
            [ -n "${expected}" ] && [ "${current}" = "${expected}" ] && return 0
            return 1
        fi
        [ -f "${target}" ] || return 1
        current="$(kf_sha256 "${target}")"
        [ "${current}" = "${managed}" ] || return 1
        return 0
    fi

    if awk -F '\t' -v target="${target}" '$2 == target { found = 1 } END { exit(found ? 0 : 1) }' \
        "${KF_MANAGED_MANIFEST}"; then
        return 1
    fi

    backup="-"
    original_mode="-"
    original_uid="-"
    original_gid="-"
    if [ -e "${target}" ]; then
        [ -f "${target}" ] || return 1
        original="$(kf_sha256 "${target}")"
        backup="${KF_MANAGED_STATE_DIR}/baseline/${key}"
        original_mode="$(stat -c '%a' "${target}")"
        original_uid="$(stat -c '%u' "${target}")"
        original_gid="$(stat -c '%g' "${target}")"
        [ ! -e "${backup}" ] && [ ! -L "${backup}" ] || return 1
        install -m 0600 "${target}" "${backup}"
    else
        original="ABSENT"
    fi
    printf '%s\t%s\t%s\t%s\tPENDING\t%s\t%s\t%s\n' \
        "${key}" "${target}" "${original}" "${backup}" \
        "${original_mode}" "${original_uid}" "${original_gid}" >> "${KF_MANAGED_MANIFEST}"
    chmod 0600 "${KF_MANAGED_MANIFEST}"
}

kf_record_managed_checksum() {
    local target="$1" key="$2" checksum temporary
    _kf_validate_target "${target}" || return 1
    _kf_validate_key "${key}" || return 1
    [ -f "${target}" ] || return 1
    checksum="$(kf_sha256 "${target}")"
    temporary="${KF_MANAGED_MANIFEST}.tmp.$$"
    awk -F '\t' -v OFS='\t' -v key="${key}" -v target="${target}" -v checksum="${checksum}" '
        $1 == key && $2 == target { $5 = checksum; found = 1 }
        { print }
        END { if (!found) exit 1 }
    ' "${KF_MANAGED_MANIFEST}" > "${temporary}" || { rm -f "${temporary}"; return 1; }
    chmod 0600 "${temporary}"
    mv -f "${temporary}" "${KF_MANAGED_MANIFEST}"
}

kf_install_replacement() {
    local source="$1" target="$2" key="$3" mode="${4:-0644}" directory temporary expected
    [ -f "${source}" ] && [ ! -L "${source}" ] || return 1
    expected="$(kf_sha256 "${source}")"
    kf_prepare_replacement "${target}" "${key}" "${expected}" || return 1
    directory="$(dirname "${target}")"
    mkdir -p "${directory}"
    temporary="${directory}/.kubefoundry-${key}.$$"
    install -m "${mode}" "${source}" "${temporary}" || return 1
    mv -f "${temporary}" "${target}" || { rm -f "${temporary}"; return 1; }
    kf_record_managed_checksum "${target}" "${key}"
}

kf_replace_managed_block() {
    local target="$1" begin="$2" end="$3" content="$4"
    local begin_count end_count directory temporary mode owner group
    _kf_validate_target "${target}" || return 1
    [ -f "${content}" ] && [ ! -L "${content}" ] || return 1
    _kf_validate_text "${begin}" && _kf_validate_text "${end}" || return 1
    directory="$(dirname "${target}")"
    mkdir -p "${directory}"
    [ -e "${target}" ] || : > "${target}"
    [ -f "${target}" ] || return 1
    begin_count="$(grep -Fxc "${begin}" "${target}" || true)"
    end_count="$(grep -Fxc "${end}" "${target}" || true)"
    [ "${begin_count}" -eq "${end_count}" ] && [ "${begin_count}" -le 1 ] || return 1

    temporary="${directory}/.kubefoundry-block.$$"
    awk -v begin="${begin}" -v end="${end}" '
        $0 == begin { inside = 1; next }
        $0 == end && inside { inside = 0; next }
        !inside { print }
        END { if (inside) exit 1 }
    ' "${target}" > "${temporary}" || { rm -f "${temporary}"; return 1; }
    {
        printf '%s\n' "${begin}"
        cat "${content}"
        printf '%s\n' "${end}"
    } >> "${temporary}"
    mode="$(stat -c '%a' "${target}")"
    owner="$(stat -c '%u' "${target}")"
    group="$(stat -c '%g' "${target}")"
    chmod "${mode}" "${temporary}"
    chown "${owner}:${group}" "${temporary}"
    mv -f "${temporary}" "${target}"
}
