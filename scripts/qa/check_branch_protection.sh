#!/usr/bin/env bash
set -euo pipefail

# Verifies GitHub branch protection includes required status checks.
# Requires: GH_TOKEN and GH_REPO (owner/repo). Optional: GH_BRANCH (default: main)

GH_REPO="${GH_REPO:-}"
GH_TOKEN="${GH_TOKEN:-}"
GH_BRANCH="${GH_BRANCH:-main}"

if [[ -z "${GH_REPO}" || -z "${GH_TOKEN}" ]]; then
  echo "[BRANCH][SKIP] GH_REPO/GH_TOKEN not provided"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[BRANCH][FAIL] jq not found"
  exit 1
fi

api="https://api.github.com/repos/${GH_REPO}/branches/${GH_BRANCH}/protection"
echo "[BRANCH] checking ${GH_REPO}:${GH_BRANCH}"

payload="$(curl -fsSL -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GH_TOKEN}" "${api}")"

required_checks=(
  "quality-gate"
  "cloud-checks"
)

for check in "${required_checks[@]}"; do
  if ! jq -e --arg c "$check" '.required_status_checks.checks[]? | select(.context == $c)' >/dev/null <<<"${payload}"; then
    echo "[BRANCH][FAIL] required status check missing: ${check}"
    exit 1
  fi
done

if ! jq -e '.required_pull_request_reviews != null' >/dev/null <<<"${payload}"; then
  echo "[BRANCH][FAIL] required_pull_request_reviews is not enabled"
  exit 1
fi

if ! jq -e '.enforce_admins.enabled == true' >/dev/null <<<"${payload}"; then
  echo "[BRANCH][FAIL] enforce_admins is not enabled"
  exit 1
fi

echo "[BRANCH] OK"
