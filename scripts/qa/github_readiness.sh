#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

failures=0

ok() { echo "[OK] $*"; }
warn() { echo "[WARN] $*"; }
fail() {
  echo "[FAIL] $*"
  failures=$((failures + 1))
}

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ok "Git repo initialized"
else
  fail "Not a git repository"
fi

branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
if [[ "$branch" == "main" ]]; then
  ok "Default branch is main"
else
  warn "Current branch is '$branch' (recommended: main)"
fi

if git remote get-url origin >/dev/null 2>&1; then
  ok "Origin remote configured: $(git remote get-url origin)"
else
  fail "Origin remote is missing"
fi

if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    ok "GitHub CLI authenticated"
  else
    fail "GitHub CLI installed but not authenticated"
  fi
else
  fail "GitHub CLI (gh) not installed"
fi

for wf in ".github/workflows/quality-gate.yml" \
          ".github/workflows/release-attestation.yml" \
          ".github/workflows/cloud-ci.yml"; do
  if [[ -f "$wf" ]]; then
    ok "Workflow present: $wf"
  else
    fail "Workflow missing: $wf"
  fi
done

if [[ -x "scripts/qa/quality_gate.sh" ]]; then
  ok "Quality gate script is executable"
else
  warn "Quality gate script is not executable"
fi

if [[ $failures -gt 0 ]]; then
  echo "[SUMMARY] GitHub readiness failed with $failures blocking issue(s)."
  exit 1
fi

echo "[SUMMARY] GitHub readiness checks passed."
