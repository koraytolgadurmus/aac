#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[VERSION][FAIL] $*" >&2
  exit 1
}

pass() {
  echo "[VERSION][OK] $*"
}

SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
FLUTTER_VER_RE='^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$'

fw_version="$(
  rg -n '^[[:space:]]*#define[[:space:]]+FW_VERSION[[:space:]]+"[^"]+"' src/main.cpp \
    | head -n1 \
    | sed -E 's/.*FW_VERSION[[:space:]]+"([^"]+)".*/\1/'
)"
[[ -n "$fw_version" ]] || fail "FW_VERSION not found in src/main.cpp"
if [[ ! "$fw_version" =~ $SEMVER_RE ]]; then
  fail "FW_VERSION is not semver-compatible: '$fw_version'"
fi
pass "FW_VERSION format valid: $fw_version"

app_version="$(sed -n "s/^version:[[:space:]]*\\(.*\\)$/\\1/p" app/pubspec.yaml | head -n1 | tr -d '[:space:]')"
[[ -n "$app_version" ]] || fail "version not found in app/pubspec.yaml"
if [[ ! "$app_version" =~ $FLUTTER_VER_RE ]]; then
  fail "app/pubspec.yaml version must match x.y.z+build: '$app_version'"
fi
pass "Flutter app version format valid: $app_version"

echo "[VERSION] policy check passed"
