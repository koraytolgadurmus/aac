#!/usr/bin/env bash
set -euo pipefail

# Seed a device row into ownership table so /device/{id6}/claim does not return device_not_found.
# Usage:
#   ./scripts/aws/seed-device.sh <id6> [ownership_table] [claim_secret_plaintext]
# Examples:
#   ./scripts/aws/seed-device.sh 594009
#   ./scripts/aws/seed-device.sh 594009 aac-dev-device-ownership
#   ./scripts/aws/seed-device.sh 594009 aac-dev-device-ownership "MY-CLAIM-SECRET"

ID6="${1:-}"
TABLE="${2:-aac-dev-device-ownership}"
CLAIM_SECRET="${3:-}"

if [[ ! "$ID6" =~ ^[0-9]{6}$ ]]; then
  echo "[ERR] id6 must be 6 digits" >&2
  exit 1
fi

NOW_MS="$(($(date +%s) * 1000))"

CLAIM_HASH=""
if [[ -n "$CLAIM_SECRET" ]]; then
  if command -v shasum >/dev/null 2>&1; then
    CLAIM_HASH="$(printf "%s" "$CLAIM_SECRET" | shasum -a 256 | awk '{print $1}')"
  else
    CLAIM_HASH="$(printf "%s" "$CLAIM_SECRET" | openssl dgst -sha256 -r | awk '{print $1}')"
  fi
fi

if [[ -n "$CLAIM_HASH" ]]; then
  ITEM_JSON="{\"deviceId\":{\"S\":\"$ID6\"},\"status\":{\"S\":\"active\"},\"createdAt\":{\"N\":\"$NOW_MS\"},\"claimSecretHash\":{\"S\":\"$CLAIM_HASH\"}}"
else
  ITEM_JSON="{\"deviceId\":{\"S\":\"$ID6\"},\"status\":{\"S\":\"active\"},\"createdAt\":{\"N\":\"$NOW_MS\"}}"
fi

echo "[INFO] seeding deviceId=$ID6 table=$TABLE claimHash=$([[ -n "$CLAIM_HASH" ]] && echo yes || echo no)"

aws dynamodb put-item \
  --table-name "$TABLE" \
  --item "$ITEM_JSON" \
  --condition-expression "attribute_not_exists(deviceId)"

echo "[OK] seeded: $ID6"
