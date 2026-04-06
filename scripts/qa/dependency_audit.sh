#!/usr/bin/env bash
set -euo pipefail

# Dependency security audit gate.
# Default: fail on critical findings in npm audit.
# Override severity with AUDIT_FAIL_LEVEL=high|moderate|low|critical.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FAIL_LEVEL="${AUDIT_FAIL_LEVEL:-critical}"
REPORT_PATH="${ROOT_DIR}/docs/audit/dependency-audit-latest.txt"

echo "[AUDIT] repo: ${ROOT_DIR}"
echo "[AUDIT] fail level: ${FAIL_LEVEL}"

if ! command -v npm >/dev/null 2>&1; then
  echo "[AUDIT][FAIL] npm not found"
  exit 1
fi

pushd "${ROOT_DIR}/infra/cdk" >/dev/null
if [[ ! -d node_modules ]]; then
  echo "[AUDIT] node_modules missing, running npm ci"
  npm ci
fi
echo "[AUDIT] npm audit --audit-level=${FAIL_LEVEL}"
npm audit --audit-level="${FAIL_LEVEL}" | tee "${REPORT_PATH}"
popd >/dev/null

echo "[AUDIT] report: ${REPORT_PATH}"
echo "[AUDIT] OK"
