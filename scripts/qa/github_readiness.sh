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
          ".github/workflows/cloud-ci.yml" \
          ".github/workflows/release-checklist.yml"; do
  if [[ -f "$wf" ]]; then
    ok "Workflow present: $wf"
  else
    fail "Workflow missing: $wf"
  fi
done

if [[ -f ".github/CODEOWNERS" ]]; then
  ok "CODEOWNERS present"
else
  fail "CODEOWNERS missing (.github/CODEOWNERS)"
fi

if [[ -f "docs/ops/release_versioning_standard.md" ]]; then
  ok "Release versioning standard present"
else
  fail "Missing docs/ops/release_versioning_standard.md"
fi

if [[ -f "docs/ops/github_security_standard.md" ]]; then
  ok "GitHub security standard present"
else
  fail "Missing docs/ops/github_security_standard.md"
fi

if [[ -x "scripts/qa/quality_gate.sh" ]]; then
  ok "Quality gate script is executable"
else
  warn "Quality gate script is not executable"
fi

if [[ -x "scripts/qa/version_policy_check.sh" ]]; then
  ok "Version policy script is executable"
else
  fail "Version policy script is not executable"
fi

if [[ $failures -gt 0 ]]; then
  echo "[SUMMARY] GitHub readiness failed with $failures blocking issue(s)."
  exit 1
fi

echo "[SUMMARY] GitHub readiness checks passed."
