#!/usr/bin/env bash
set -euo pipefail

# Applies main-branch protection policy via GitHub API.
# Requires:
#   GH_REPO=owner/repo
#   GH_TOKEN=token with repo admin permission
# Optional:
#   GH_BRANCH (default: main)

GH_REPO="${GH_REPO:-}"
GH_TOKEN="${GH_TOKEN:-}"
GH_BRANCH="${GH_BRANCH:-main}"

if [[ -z "${GH_REPO}" || -z "${GH_TOKEN}" ]]; then
  echo "[BRANCH][FAIL] GH_REPO and GH_TOKEN are required"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[BRANCH][FAIL] jq not found"
  exit 1
fi

api="https://api.github.com/repos/${GH_REPO}/branches/${GH_BRANCH}/protection"

payload="$(jq -n '{
  required_status_checks: {
    strict: true,
    checks: [
      {context: "quality-gate", app_id: null},
      {context: "cloud-checks", app_id: null}
    ]
  },
  enforce_admins: true,
  required_pull_request_reviews: {
    dismiss_stale_reviews: true,
    require_code_owner_reviews: false,
    required_approving_review_count: 1,
    require_last_push_approval: false
  },
  restrictions: null,
  required_conversation_resolution: true,
  lock_branch: false,
  allow_fork_syncing: false
}')"

echo "[BRANCH] applying protection ${GH_REPO}:${GH_BRANCH}"
curl -fsSL -X PUT \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  "${api}" \
  -d "${payload}" >/dev/null

echo "[BRANCH] applied"
