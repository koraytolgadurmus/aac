#!/usr/bin/env bash
set -euo pipefail

# List candidate 6-digit device ids from ownership/state tables.
# Usage:
#   ./scripts/aws/list-device-ids.sh
#   ./scripts/aws/list-device-ids.sh aac-dev-device-ownership aac-dev-device-state

OWNERSHIP_TABLE="${1:-aac-dev-device-ownership}"
STATE_TABLE="${2:-aac-dev-device-state}"

tmp1="$(mktemp)"
tmp2="$(mktemp)"
trap 'rm -f "$tmp1" "$tmp2"' EXIT

aws dynamodb scan --table-name "$OWNERSHIP_TABLE" \
  --projection-expression deviceId \
  --max-items 200 --output json > "$tmp1" 2>/dev/null || true

aws dynamodb scan --table-name "$STATE_TABLE" \
  --projection-expression deviceId \
  --max-items 200 --output json > "$tmp2" 2>/dev/null || true

ids="$({
  jq -r '.Items[]?.deviceId.S // empty' "$tmp1" 2>/dev/null || true
  jq -r '.Items[]?.deviceId.S // empty' "$tmp2" 2>/dev/null || true
} | rg '^[0-9]{6}$' | sort -u || true)"

if [[ -z "${ids}" ]]; then
  echo "[INFO] No 6-digit device ids found yet in ${OWNERSHIP_TABLE} or ${STATE_TABLE}" >&2
  exit 0
fi

printf "%s\n" "${ids}"
