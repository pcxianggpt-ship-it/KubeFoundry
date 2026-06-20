#!/bin/bash

set -euo pipefail

GIT_COMMAND="git"
if ! command -v "$GIT_COMMAND" >/dev/null 2>&1; then
    GIT_COMMAND="git.exe"
fi

failed=0
while IFS= read -r -d '' file; do
    [ -f "$file" ] || continue
    if LC_ALL=C grep -q $'\r' "$file"; then
        printf 'CRLF detected: %s\n' "$file"
        failed=1
    fi
done < <(
    "$GIT_COMMAND" ls-files -z \
        '*.sh' '*.py' '*.yaml' '*.yml' '*.md' '*.toml' '*.conf' \
        '*.js' '*.json' '*.vue' '*.css' '*.html'
)

exit "$failed"
