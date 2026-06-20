#!/bin/bash

set -euo pipefail

GIT_COMMAND="git"
if ! command -v "$GIT_COMMAND" >/dev/null 2>&1; then
    GIT_COMMAND="git.exe"
fi

failed=0

if "$GIT_COMMAND" grep -nE 'BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY' -- . \
    ':!scripts/ci/check-secrets.sh'; then
    echo "发现疑似私钥内容"
    failed=1
fi

PASSWORD_PATTERN="^[[:space:]]*(password|sudo_password):[[:space:]]*(\"[^\"]+\"|'[^']+'|[^\"'#[:space:]][^#[:space:]]*)"
if "$GIT_COMMAND" grep -nE "$PASSWORD_PATTERN" \
    -- '*.yaml' '*.yml' ':!scripts/ci/check-secrets.sh'; then
    echo "发现非空 YAML 明文密码"
    failed=1
fi

exit "$failed"
