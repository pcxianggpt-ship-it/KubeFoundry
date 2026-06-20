#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log_info() { :; }
log_success() { :; }
log_error() { :; }
get_all_control_plane_ips() {
    printf '%s\n' "10.0.0.10" "10.0.0.11" "10.0.0.12"
}
config_get_node() {
    if [ "$1" = "control_plane" ] && [ "$2" = "0" ] && [ "$3" = "ip" ]; then
        printf '%s\n' "10.0.0.10"
        return 0
    fi
    return 1
}

source <(sed 's/\r$//' "${PROJECT_ROOT}/scripts/lib/exec_script.sh")

declare -a EXECUTED_NODES=()
exec_script_on_single_node() {
    EXECUTED_NODES+=("$1")
}

exec_script_on_primary_control_plane "/tmp/test-step.sh"
if [ "${EXECUTED_NODES[*]}" != "10.0.0.10" ]; then
    echo "primary control plane routing failed: ${EXECUTED_NODES[*]}" >&2
    exit 1
fi

EXECUTED_NODES=()
exec_script_on_other_control_planes "/tmp/test-step.sh"
if [ "${EXECUTED_NODES[*]}" != "10.0.0.11 10.0.0.12" ]; then
    echo "other control planes routing failed: ${EXECUTED_NODES[*]}" >&2
    exit 1
fi

dry_run_block="$(
    sed 's/\r$//' "${PROJECT_ROOT}/scripts/main.sh" |
        sed -n '/if \[ "\$DRY_RUN" = true \]; then/,/^[[:space:]]*fi$/p' |
        head -n 8
)"
if ! grep -q "print_execution_plan" <<< "$dry_run_block" ||
    ! grep -q "return 0" <<< "$dry_run_block"; then
    echo "dry-run does not exit before real execution" >&2
    printf '%s\n' "$dry_run_block" >&2
    exit 1
fi

echo "CLI routing tests passed"
