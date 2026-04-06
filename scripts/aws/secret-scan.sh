#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

info() {
  echo "[INFO] $*"
}

SCAN_PATHS=(
  "certs"
  "data"
  "app/aws_iot_bootstrap"
)

EXCLUDES=(
  "--glob=!certs/AmazonRootCA1.pem"
  "--glob=!data/AmazonRootCA1.pem"
  "--glob=!**/.pio/**"
  "--glob=!**/build/**"
  "--glob=!**/.git/**"
)

PATTERN='BEGIN (EC |RSA |)?PRIVATE KEY|certificateArn|certificateId|ownedBy|generationId|-----BEGIN CERTIFICATE-----'

info "Scanning repo-managed bootstrap/cert material for live secrets or account-bound artifacts"

set +e
if command -v rg >/dev/null 2>&1; then
  MATCHES="$(
    cd "$ROOT_DIR" &&
      rg -n "${EXCLUDES[@]}" "$PATTERN" "${SCAN_PATHS[@]}"
  )"
  SCAN_STATUS=$?
else
  MATCHES="$(
    cd "$ROOT_DIR" &&
      grep -RInE "$PATTERN" "${SCAN_PATHS[@]}" \
        | grep -vE 'certs/AmazonRootCA1\.pem|data/AmazonRootCA1\.pem'
  )"
  SCAN_STATUS=$?
fi
set -e

if [[ "$SCAN_STATUS" -gt 1 ]]; then
  fail "secret scan errored"
fi

if [[ "$SCAN_STATUS" -eq 0 && -n "${MATCHES}" ]]; then
  echo "$MATCHES" >&2
  fail "live AWS bootstrap material detected in repo paths above"
fi

echo "[PASS] no live AWS bootstrap material in repo-managed cert/data paths"
