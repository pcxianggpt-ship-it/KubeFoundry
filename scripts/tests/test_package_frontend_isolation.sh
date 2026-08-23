#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_SCRIPT="${PROJECT_ROOT}/package.sh"

grep -Fq 'BACKEND_BUILD_ROOT="$(mktemp -d)"' "${PACKAGE_SCRIPT}"
grep -Fq "tar --exclude='./target' -cf - ." "${PACKAGE_SCRIPT}"
grep -Fq 'cp -a "${PROJECT_ROOT}/scripts/steps" "${backend_project_dir}/scripts/steps"' "${PACKAGE_SCRIPT}"
grep -Fq 'cp -a "${PROJECT_ROOT}/scripts/verify" "${backend_project_dir}/scripts/verify"' "${PACKAGE_SCRIPT}"
grep -Fq 'cd "${backend_build_dir}" && mvn -q "${maven_args[@]}"' "${PACKAGE_SCRIPT}"
grep -Fq 'cp "${backend_build_dir}/target/kubefoundry-backend-0.3.2.jar"' "${PACKAGE_SCRIPT}"
grep -Fq 'FRONTEND_BUILD_ROOT="$(mktemp -d)"' "${PACKAGE_SCRIPT}"
grep -Fq "tar --exclude='./node_modules' --exclude='./dist' -cf - ." "${PACKAGE_SCRIPT}"
grep -Fq 'cd "${frontend_build_dir}" && npm "${npm_ci_args[@]}" && npm test && npm run build' "${PACKAGE_SCRIPT}"
grep -Fq 'cp -a "${frontend_build_dir}/dist/." "${release_dir}/web/"' "${PACKAGE_SCRIPT}"

echo "前端构建隔离测试通过"
