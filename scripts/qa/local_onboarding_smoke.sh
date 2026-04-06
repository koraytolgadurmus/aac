#!/usr/bin/env bash
set -euo pipefail

# Local onboarding smoke test for AP mode.
# Usage:
#   BASE_URL=http://192.168.4.1 PAIR_TOKEN=... ./scripts/qa/local_onboarding_smoke.sh

BASE_URL="${BASE_URL:-http://192.168.4.1}"
PAIR_TOKEN="${PAIR_TOKEN:-}"
TIMEOUT="${TIMEOUT:-10}"

if [[ -z "$PAIR_TOKEN" ]]; then
  echo "PAIR_TOKEN is required"
  exit 2
fi

auth_headers=(
  -H "Authorization: Bearer ${PAIR_TOKEN}"
  -H "X-QR-Token: ${PAIR_TOKEN}"
)

echo "[1/5] api/ap_info"
curl -fsS --max-time "$TIMEOUT" "${auth_headers[@]}" \
  "${BASE_URL}/api/ap_info" | sed -n '1,120p'

echo "[2/5] api/nonce"
NONCE_JSON="$(curl -fsS --max-time "$TIMEOUT" "${BASE_URL}/api/nonce")"
echo "$NONCE_JSON" | sed -n '1,120p'

echo "[3/5] api/session/open"
SESSION_JSON="$(curl -fsS --max-time "$TIMEOUT" \
  -H "Content-Type: application/json" \
  "${auth_headers[@]}" \
  -d '{"ttl":120}' \
  "${BASE_URL}/api/session/open")"
echo "$SESSION_JSON" | sed -n '1,120p'

SESSION_TOKEN="$(echo "$SESSION_JSON" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
SESSION_NONCE="$(echo "$SESSION_JSON" | sed -n 's/.*"nonce":"\([^"]*\)".*/\1/p')"
if [[ -z "$SESSION_TOKEN" || -z "$SESSION_NONCE" ]]; then
  echo "session open failed: token/nonce not found"
  exit 3
fi

echo "[4/5] api/status (session headers)"
curl -fsS --max-time "$TIMEOUT" \
  -H "X-Session-Token: ${SESSION_TOKEN}" \
  -H "X-Session-Nonce: ${SESSION_NONCE}" \
  "${BASE_URL}/api/status" | sed -n '1,220p'

echo "[5/5] api/scan (owner/provision path)"
curl -fsS --max-time "$TIMEOUT" \
  -H "X-Session-Token: ${SESSION_TOKEN}" \
  -H "X-Session-Nonce: ${SESSION_NONCE}" \
  "${BASE_URL}/api/scan" | sed -n '1,160p'

echo "local onboarding smoke: OK"
