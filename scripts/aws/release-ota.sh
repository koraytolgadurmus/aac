#!/usr/bin/env bash
set -euo pipefail

# AAC OTA release helper
#
# Single command flow:
#   1) Build firmware (optional)
#   2) Compute SHA256
#   3) Upload .bin to S3
#   4) Create OTA job (single device or campaign)
#
# Environment variables (can be used instead of flags):
#   API_BASE_URL, ACCESS_TOKEN, AWS_REGION, AWS_PROFILE, S3_BUCKET
#
# Examples:
#   ./scripts/aws/release-ota.sh --version 1.0.2 --device-id 709373
#   ./scripts/aws/release-ota.sh --version 1.0.2 --campaign
#   API_BASE_URL=... ACCESS_TOKEN=... ./scripts/aws/release-ota.sh --version 1.0.2 --campaign --dry-run

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIO_ENV="esp32dev"
FW_VERSION=""
DEVICE_ID=""
MODE="device" # device | campaign
DO_BUILD=1
DRY_RUN=0
REQUIRES_USER_APPROVAL=1
FORCE=0
PRESIGN_EXPIRES=604800
STRICT_PROD=0
PROD_EVIDENCE=""

PRODUCT="aac"
HW_REV="v1"
BOARD_REV="esp32dev"
FW_CHANNEL="stable"
MIN_VERSION=""

API_BASE_URL="${API_BASE_URL:-https://3wl1he0yj3.execute-api.eu-central-1.amazonaws.com}"
ACCESS_TOKEN="${ACCESS_TOKEN:-}"
AWS_REGION_VAL="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
S3_BUCKET="${S3_BUCKET:-}"
S3_KEY=""

pass() { echo "[PASS] $*"; }
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }
to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

usage() {
  cat <<USAGE
Usage: $(basename "$0") --version <x.y.z> [options]

Required:
  --version VER               Firmware version (e.g. 1.0.2)
  --device-id ID6 | --campaign

Auth/API:
  --api-base URL              API base URL (default: ${API_BASE_URL})
  --token JWT                 Owner access token (or ACCESS_TOKEN env)

Firmware/build:
  --pio-env ENV               PlatformIO env (default: ${PIO_ENV})
  --no-build                  Skip pio run (use existing .pio/build/<env>/firmware.bin)
  --min-version VER           Optional minVersion field for OTA job

Target filters:
  --product NAME              default: ${PRODUCT}
  --hw-rev REV                default: ${HW_REV}
  --board-rev REV             default: ${BOARD_REV}
  --fw-channel CH             default: ${FW_CHANNEL}

S3/upload:
  --bucket NAME               S3 bucket (default: aac-dev-ota-artifacts-<account>-<region>)
  --key PATH                  S3 key (default: firmware/<product>/<hwRev>/<fwChannel>/<version>/firmware.bin)

Behavior:
  --dry-run                   Create dryRun OTA request
  --no-user-approval          requiresUserApproval=false
  --force                     force=true (single-device endpoint)
  --presign-expires SEC       Presigned URL TTL in seconds (default: ${PRESIGN_EXPIRES}, max AWS CLI limit applies)
  --strict-prod               Run strict production gates before release
  --prod-evidence PATH        JSON evidence file with secure boot / flash encryption proof
  -h, --help                  Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || fail "--version requires a value"
      FW_VERSION="$2"
      shift 2
      ;;
    --device-id)
      [[ $# -ge 2 ]] || fail "--device-id requires a value"
      DEVICE_ID="$2"
      MODE="device"
      shift 2
      ;;
    --campaign)
      MODE="campaign"
      DEVICE_ID=""
      shift
      ;;
    --api-base)
      [[ $# -ge 2 ]] || fail "--api-base requires a value"
      API_BASE_URL="$2"
      shift 2
      ;;
    --token)
      [[ $# -ge 2 ]] || fail "--token requires a value"
      ACCESS_TOKEN="$2"
      shift 2
      ;;
    --pio-env)
      [[ $# -ge 2 ]] || fail "--pio-env requires a value"
      PIO_ENV="$2"
      shift 2
      ;;
    --no-build)
      DO_BUILD=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-user-approval)
      REQUIRES_USER_APPROVAL=0
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --presign-expires)
      [[ $# -ge 2 ]] || fail "--presign-expires requires a value"
      PRESIGN_EXPIRES="$2"
      shift 2
      ;;
    --strict-prod)
      STRICT_PROD=1
      shift
      ;;
    --prod-evidence)
      [[ $# -ge 2 ]] || fail "--prod-evidence requires a value"
      PROD_EVIDENCE="$2"
      shift 2
      ;;
    --product)
      [[ $# -ge 2 ]] || fail "--product requires a value"
      PRODUCT="$2"
      shift 2
      ;;
    --hw-rev)
      [[ $# -ge 2 ]] || fail "--hw-rev requires a value"
      HW_REV="$2"
      shift 2
      ;;
    --board-rev)
      [[ $# -ge 2 ]] || fail "--board-rev requires a value"
      BOARD_REV="$2"
      shift 2
      ;;
    --fw-channel)
      [[ $# -ge 2 ]] || fail "--fw-channel requires a value"
      FW_CHANNEL="$2"
      shift 2
      ;;
    --min-version)
      [[ $# -ge 2 ]] || fail "--min-version requires a value"
      MIN_VERSION="$2"
      shift 2
      ;;
    --bucket)
      [[ $# -ge 2 ]] || fail "--bucket requires a value"
      S3_BUCKET="$2"
      shift 2
      ;;
    --key)
      [[ $# -ge 2 ]] || fail "--key requires a value"
      S3_KEY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

[[ -n "$FW_VERSION" ]] || fail "--version is required"
if [[ "$MODE" == "device" ]]; then
  [[ "$DEVICE_ID" =~ ^[0-9]{6}$ ]] || fail "--device-id must be 6 digits"
fi
[[ -n "$ACCESS_TOKEN" ]] || fail "ACCESS_TOKEN / --token is required"

if ! command -v aws >/dev/null 2>&1; then fail "aws CLI is required"; fi
if ! command -v curl >/dev/null 2>&1; then fail "curl is required"; fi
if ! command -v jq >/dev/null 2>&1; then fail "jq is required"; fi
if [[ "$DO_BUILD" == "1" ]] && ! command -v pio >/dev/null 2>&1; then
  fail "pio is required unless --no-build is used"
fi

if [[ -z "$AWS_REGION_VAL" ]]; then
  AWS_REGION_VAL="$(aws configure get region 2>/dev/null || true)"
fi
[[ -n "$AWS_REGION_VAL" ]] || fail "AWS region not set (set AWS_REGION or aws configure region)"

info "Repo root: ${ROOT_DIR}"
info "Mode: ${MODE}"

if [[ "$DRY_RUN" != "1" && "$FW_CHANNEL" == "stable" ]]; then
  STRICT_PROD=1
fi

if [[ "$STRICT_PROD" == "1" ]]; then
  info "0/4 Running strict production preflight"
  PREFLIGHT_CMD=( "${ROOT_DIR}/scripts/aws/release-preflight.sh" --with-firmware --firmware-env "$PIO_ENV" --strict-prod )
  if [[ -n "$PROD_EVIDENCE" ]]; then
    PREFLIGHT_CMD+=( --prod-evidence "$PROD_EVIDENCE" )
  fi
  "${PREFLIGHT_CMD[@]}"
  pass "Strict production preflight"
fi

if [[ "$DO_BUILD" == "1" ]]; then
  info "1/4 Building firmware (env=${PIO_ENV})"
  if [[ "$STRICT_PROD" != "1" ]]; then
    (
      cd "$ROOT_DIR"
      pio run -e "$PIO_ENV"
    )
    pass "Firmware build"
  else
    info "Firmware build already completed by strict production preflight"
  fi
else
  info "1/4 Build skipped (--no-build)"
fi

BIN_PATH="${ROOT_DIR}/.pio/build/${PIO_ENV}/firmware.bin"
[[ -f "$BIN_PATH" ]] || fail "firmware not found: $BIN_PATH"

info "2/4 Calculating SHA256"
SHA256="$(shasum -a 256 "$BIN_PATH" | awk '{print $1}')"
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "failed to compute valid SHA256"
pass "SHA256: ${SHA256}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
if [[ -z "$S3_BUCKET" ]]; then
  S3_BUCKET="aac-dev-ota-artifacts-${ACCOUNT_ID}-${AWS_REGION_VAL}"
fi
if [[ -z "$S3_KEY" ]]; then
  S3_KEY="firmware/${PRODUCT}/${HW_REV}/${FW_CHANNEL}/${FW_VERSION}/firmware.bin"
fi

info "3/4 Uploading firmware to s3://${S3_BUCKET}/${S3_KEY}"
aws s3 cp "$BIN_PATH" "s3://${S3_BUCKET}/${S3_KEY}" --region "$AWS_REGION_VAL"
pass "S3 upload"

info "Generating presigned firmware URL (ttl=${PRESIGN_EXPIRES}s)"
FIRMWARE_URL="$(aws s3 presign "s3://${S3_BUCKET}/${S3_KEY}" --region "$AWS_REGION_VAL" --expires-in "$PRESIGN_EXPIRES")"
[[ "$FIRMWARE_URL" =~ ^https:// ]] || fail "failed to generate presigned firmware URL"
pass "Presigned firmware URL ready"
API_BASE_URL="${API_BASE_URL%/}"
PRODUCT_LC="$(to_lower "$PRODUCT")"
HW_REV_LC="$(to_lower "$HW_REV")"
BOARD_REV_LC="$(to_lower "$BOARD_REV")"
FW_CHANNEL_LC="$(to_lower "$FW_CHANNEL")"

TMP_BODY="$(mktemp)"
if [[ "$MODE" == "device" ]]; then
  jq -n \
    --arg firmwareUrl "$FIRMWARE_URL" \
    --arg sha256 "$SHA256" \
    --arg version "$FW_VERSION" \
    --arg minVersion "$MIN_VERSION" \
    --arg product "$PRODUCT_LC" \
    --arg hwRev "$HW_REV_LC" \
    --arg boardRev "$BOARD_REV_LC" \
    --arg fwChannel "$FW_CHANNEL_LC" \
    --argjson dryRun "$DRY_RUN" \
    --argjson requiresUserApproval "$REQUIRES_USER_APPROVAL" \
    --argjson force "$FORCE" \
    '{
      firmwareUrl: $firmwareUrl,
      sha256: $sha256,
      version: $version,
      dryRun: $dryRun,
      requiresUserApproval: $requiresUserApproval,
      force: $force,
      target: {
        product: $product,
        hwRev: $hwRev,
        boardRev: $boardRev,
        fwChannel: $fwChannel
      }
    }
    | if ($minVersion|length)>0 then . + {minVersion:$minVersion} else . end' > "$TMP_BODY"
  ENDPOINT="${API_BASE_URL}/device/${DEVICE_ID}/ota/job"
else
  jq -n \
    --arg firmwareUrl "$FIRMWARE_URL" \
    --arg sha256 "$SHA256" \
    --arg version "$FW_VERSION" \
    --arg minVersion "$MIN_VERSION" \
    --arg product "$PRODUCT_LC" \
    --arg hwRev "$HW_REV_LC" \
    --arg boardRev "$BOARD_REV_LC" \
    --arg fwChannel "$FW_CHANNEL_LC" \
    --argjson dryRun "$DRY_RUN" \
    --argjson requiresUserApproval "$REQUIRES_USER_APPROVAL" \
    '{
      firmwareUrl: $firmwareUrl,
      sha256: $sha256,
      version: $version,
      dryRun: $dryRun,
      requiresUserApproval: $requiresUserApproval,
      target: {
        product: $product,
        hwRev: $hwRev,
        boardRev: $boardRev,
        fwChannel: $fwChannel
      }
    }
    | if ($minVersion|length)>0 then . + {minVersion:$minVersion} else . end' > "$TMP_BODY"
  ENDPOINT="${API_BASE_URL}/ota/campaign"
fi

info "4/4 Creating OTA ${MODE}"
TMP_RESP="$(mktemp)"
HTTP_CODE="$(curl -sS -o "$TMP_RESP" -w "%{http_code}" \
  -X POST "$ENDPOINT" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary "@$TMP_BODY")"

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "[ERROR] endpoint=${ENDPOINT} status=${HTTP_CODE}" >&2
  echo "[ERROR] response:" >&2
  cat "$TMP_RESP" >&2
  rm -f "$TMP_BODY" "$TMP_RESP"
  exit 1
fi

JOB_ID="$(jq -r '.jobId // empty' "$TMP_RESP" 2>/dev/null || true)"
pass "OTA request accepted (HTTP ${HTTP_CODE})"
if [[ -n "$JOB_ID" ]]; then
  pass "jobId: ${JOB_ID}"
fi

info "Summary"
echo "  mode:                ${MODE}"
echo "  product/hw/board/ch: ${PRODUCT}/${HW_REV}/${BOARD_REV}/${FW_CHANNEL}"
echo "  version:             ${FW_VERSION}"
echo "  firmwareUrl:         ${FIRMWARE_URL}"
echo "  sha256:              ${SHA256}"
echo "  endpoint:            ${ENDPOINT}"
echo "  requiresApproval:    ${REQUIRES_USER_APPROVAL}"
echo "  dryRun:              ${DRY_RUN}"

echo
cat "$TMP_RESP"
echo

rm -f "$TMP_BODY" "$TMP_RESP"
pass "Done"
