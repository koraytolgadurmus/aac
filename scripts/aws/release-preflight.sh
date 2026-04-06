#!/usr/bin/env bash
set -euo pipefail

# AAC cloud release preflight checks
# Default checks:
#   - infra/cdk build
#   - lambda syntax check
#   - AWS bootstrap secret scan
# Optional checks:
#   --with-firmware : pio run -e <firmware-env>
#   --with-smoke    : scripts/aws/cloud-smoke.sh (requires env vars)
#   --env-file      : source env file before smoke (only with --with-smoke)
#   --strict-prod   : fail on production hard gates (EC/P-256 key + production evidence)
#   --prod-evidence : JSON evidence file proving secure boot + flash encryption
#
# Usage:
#   ./scripts/aws/release-preflight.sh
#   ./scripts/aws/release-preflight.sh --with-firmware
#   ./scripts/aws/release-preflight.sh --with-firmware --firmware-env esp32dev_board_legacy --strict-prod
#   API_BASE_URL=... ACCESS_TOKEN=... DEVICE_ID=... ./scripts/aws/release-preflight.sh --with-smoke

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WITH_FIRMWARE=0
WITH_SMOKE=0
STRICT_PROD=0
FIRMWARE_ENV="esp32dev"
ENV_FILE=""
PROD_EVIDENCE=""
DEFAULT_SECRET_DIR="${AAC_SECRET_DIR:-$HOME/.aac-secrets/aac}"

pass() { echo "[PASS] $*"; }
info() { echo "[INFO] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

resolve_existing_file() {
  local candidate=""
  for candidate in "$@"; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

read_env_or_file() {
  local raw="$1"
  [[ -n "$raw" ]] || return 1
  if [[ -f "$raw" ]]; then
    cat "$raw"
    return 0
  fi
  printf '%s' "$raw"
}

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --with-firmware   Run ESP32 build check (pio run -e <firmware-env>)
  --firmware-env    PlatformIO env for firmware check (default: esp32dev)
  --with-smoke      Run cloud smoke test (requires API_BASE_URL and ACCESS_TOKEN)
  --env-file PATH   Source PATH before smoke (trusted file, bash source)
  --strict-prod     Enable production hard gates
  --prod-evidence   JSON evidence file with secure boot / flash encryption proof
  -h, --help        Show this help
USAGE
}

check_device_key_type() {
  local key_file=""
  local key_text=""
  key_file="$(resolve_existing_file \
    "${AAC_DEVICE_KEY_PATH:-}" \
    "${DEFAULT_SECRET_DIR}/device_private.key" \
    "${DEFAULT_SECRET_DIR}/device-private.key" \
    "${DEFAULT_SECRET_DIR}/private.key" \
    "${ROOT_DIR}/data/device_private.key" \
    "${ROOT_DIR}/certs/device_private.key" \
    "${ROOT_DIR}/data/device-private.key" \
    "${ROOT_DIR}/certs/device-private.key" \
    "${ROOT_DIR}/data/private.key" \
    "${ROOT_DIR}/certs/private.key" || true)"

  if [[ -n "${AWS_IOT_PRIVATE_KEY_PEM:-}" ]]; then
    key_text="$(read_env_or_file "${AWS_IOT_PRIVATE_KEY_PEM}")"
  elif [[ -n "$key_file" ]]; then
    key_text="$(cat "$key_file")"
  fi

  if [[ -z "$key_text" ]]; then
    if [[ "$STRICT_PROD" == "1" ]]; then
      fail "Device private key not found in env, AAC_SECRET_DIR, data/, or certs/."
    fi
    info "Device private key not found in env, AAC_SECRET_DIR, data/, or certs/ (skipping key-type gate)"
    return 0
  fi

  if [[ "$key_text" == *"PLACEHOLDER_SECRET_FILE_USE_AAC_SECRET_DIR_OR_ENV"* ]]; then
    if [[ "$STRICT_PROD" == "1" ]]; then
      fail "Device private key source is a placeholder. Provide a real key via AAC_SECRET_DIR, AAC_DEVICE_KEY_PATH, or AWS_IOT_PRIVATE_KEY_PEM."
    fi
    info "Device private key source is a placeholder; verify a real key is supplied from secret storage."
    return 0
  fi

  if grep -q "BEGIN RSA PRIVATE KEY" <<<"$key_text"; then
    if [[ "$STRICT_PROD" == "1" ]]; then
      fail "RSA device private key detected (${key_file:-env}). Production gate requires EC/P-256 key."
    fi
    info "RSA device private key detected (${key_file:-env}); recommend EC/P-256 for production stability."
    return 0
  fi

  if grep -q "BEGIN EC PRIVATE KEY" <<<"$key_text"; then
    pass "Device private key type: EC (${key_file:-env})"
    return 0
  fi

  if grep -q "BEGIN PRIVATE KEY" <<<"$key_text"; then
    if command -v openssl >/dev/null 2>&1 &&
       openssl pkey -in <(printf '%s\n' "$key_text") -text -noout 2>/dev/null | grep -q "ASN1 OID: prime256v1"; then
      pass "Device private key type: EC/P-256 (${key_file:-env})"
      return 0
    fi
    if [[ "$STRICT_PROD" == "1" ]]; then
      fail "PKCS#8 device private key is not EC/P-256 (${key_file:-env})."
    fi
    info "PKCS#8 device private key detected (${key_file:-env}); verify it is EC/P-256."
    return 0
  fi

  if [[ "$STRICT_PROD" == "1" ]]; then
    fail "Device private key type unknown (${key_file:-env}). Production gate requires explicit EC/P-256 private key."
  fi
  info "Device private key type unknown (${key_file:-env}); verify it is EC/P-256."
  return 0
}

check_board_env_profiles() {
  local ini="${ROOT_DIR}/platformio.ini"
  if [[ ! -f "$ini" ]]; then
    fail "platformio.ini not found"
  fi
  if ! grep -q "^\[env:esp32dev_board_legacy\]" "$ini"; then
    fail "Missing PlatformIO env: esp32dev_board_legacy"
  fi
  if ! grep -q "^\[env:esp32dev_board_aux\]" "$ini"; then
    fail "Missing PlatformIO env: esp32dev_board_aux"
  fi
  pass "Board-specific PlatformIO envs present (legacy + aux)"
}

check_source_config_hygiene() {
  local cfg="${ROOT_DIR}/include/config.h"
  [[ -f "$cfg" ]] || return 0

  local endpoint
  endpoint="$(sed -n 's/^[[:space:]]*#define[[:space:]]\+AWS_IOT_ENDPOINT[[:space:]]\+"\(.*\)".*/\1/p' "$cfg" | head -n 1)"
  if [[ -n "$endpoint" && "$endpoint" != "YOUR_AWS_IOT_ENDPOINT" ]]; then
    fail "include/config.h contains a hardcoded AWS_IOT_ENDPOINT. Move production/stage endpoints to env or AAC_SECRET_DIR."
  fi

  local forbidden_macros=(
    AWS_IOT_DEVICE_CERT_PEM
    AWS_IOT_PRIVATE_KEY_PEM
    AWS_IOT_CLAIM_CERT_PEM
    AWS_IOT_CLAIM_PRIVATE_KEY_PEM
  )
  local macro=""
  for macro in "${forbidden_macros[@]}"; do
    if ! grep -q "^[[:space:]]*#define[[:space:]]\+${macro}[[:space:]]\+\"YOUR_.*\"$" "$cfg"; then
      fail "include/config.h must not carry inline credential material for ${macro}."
    fi
  done

  pass "Source config hygiene"
}

check_strict_prod_env() {
  case "$FIRMWARE_ENV" in
    esp32dev_board_legacy|esp32dev_board_aux)
      pass "Strict production firmware env selected (${FIRMWARE_ENV})"
      ;;
    *)
      fail "Strict production requires board-specific firmware env (esp32dev_board_legacy or esp32dev_board_aux), got: ${FIRMWARE_ENV}"
      ;;
  esac
}

check_prod_evidence() {
  [[ -n "$PROD_EVIDENCE" ]] || fail "--prod-evidence is required with --strict-prod"
  [[ -f "$PROD_EVIDENCE" ]] || fail "Production evidence file not found: ${PROD_EVIDENCE}"
  if ! command -v jq >/dev/null 2>&1; then
    fail "jq is required for production evidence validation"
  fi

  local jq_script='
    .schemaVersion == 1 and
    (.secureBoot.enabled == true) and
    ((.secureBoot.version // "") == "v2") and
    (.flashEncryption.enabled == true) and
    ((.deviceIdentity.keyType // "" | ascii_downcase) == "ec-p256") and
    ((.evidence.generatedAt // "") | length > 0) and
    ((.evidence.verifiedBy // "") | length > 0)
  '
  if ! jq -e "$jq_script" "$PROD_EVIDENCE" >/dev/null; then
    fail "Production evidence file failed validation: ${PROD_EVIDENCE}"
  fi

  local secure_boot_digest flash_mode key_type verified_by generated_at
  secure_boot_digest="$(jq -r '.secureBoot.digest // "unknown"' "$PROD_EVIDENCE")"
  flash_mode="$(jq -r '.flashEncryption.mode // "unknown"' "$PROD_EVIDENCE")"
  key_type="$(jq -r '.deviceIdentity.keyType // "unknown"' "$PROD_EVIDENCE")"
  verified_by="$(jq -r '.evidence.verifiedBy // "unknown"' "$PROD_EVIDENCE")"
  generated_at="$(jq -r '.evidence.generatedAt // "unknown"' "$PROD_EVIDENCE")"
  pass "Production evidence valid (secureBootDigest=${secure_boot_digest} flashMode=${flash_mode} keyType=${key_type} verifiedBy=${verified_by} generatedAt=${generated_at})"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-firmware)
      WITH_FIRMWARE=1
      shift
      ;;
    --firmware-env)
      [[ $# -ge 2 ]] || fail "--firmware-env requires a value"
      FIRMWARE_ENV="$2"
      shift 2
      ;;
    --with-smoke)
      WITH_SMOKE=1
      shift
      ;;
    --env-file)
      [[ $# -ge 2 ]] || fail "--env-file requires a value"
      ENV_FILE="$2"
      shift 2
      ;;
    --prod-evidence)
      [[ $# -ge 2 ]] || fail "--prod-evidence requires a value"
      PROD_EVIDENCE="$2"
      shift 2
      ;;
    --strict-prod)
      STRICT_PROD=1
      shift
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

if ! command -v node >/dev/null 2>&1; then
  fail "node is required"
fi

if ! command -v npm >/dev/null 2>&1; then
  fail "npm is required"
fi

if [[ "$WITH_FIRMWARE" == "1" ]] && ! command -v pio >/dev/null 2>&1; then
  fail "pio is required for --with-firmware"
fi

if [[ "$WITH_SMOKE" == "1" ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    fail "curl is required for --with-smoke"
  fi
  if ! command -v jq >/dev/null 2>&1; then
    fail "jq is required for --with-smoke"
  fi
fi

info "Repo root: ${ROOT_DIR}"

info "0/6 Production profile checks"
check_board_env_profiles
check_source_config_hygiene
if [[ "$STRICT_PROD" == "1" ]]; then
  check_strict_prod_env
  check_device_key_type
  check_prod_evidence
else
  check_device_key_type
fi

info "1/6 CDK build"
(
  cd "${ROOT_DIR}/infra/cdk"
  npm run -s build
)
pass "CDK build"

info "2/6 Lambda syntax"
node --check "${ROOT_DIR}/scripts/aws/aac-cloud-api.js"
pass "Lambda syntax"

info "3/6 AWS secret scan"
"${ROOT_DIR}/scripts/aws/secret-scan.sh"
pass "AWS secret scan"

if [[ "$WITH_FIRMWARE" == "1" ]]; then
  info "4/6 Firmware build (${FIRMWARE_ENV})"
  (
    cd "${ROOT_DIR}"
    pio run -e "${FIRMWARE_ENV}"
  )
  pass "Firmware build"
else
  info "4/6 Firmware build skipped (use --with-firmware)"
fi

if [[ "$WITH_SMOKE" == "1" ]]; then
  if [[ -n "$ENV_FILE" ]]; then
    [[ -f "$ENV_FILE" ]] || fail "env file not found: $ENV_FILE"
    info "Loading env file: $ENV_FILE"
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
  fi
  : "${API_BASE_URL:?API_BASE_URL is required for --with-smoke}"
  : "${ACCESS_TOKEN:?ACCESS_TOKEN is required for --with-smoke}"
  info "5/6 Cloud smoke"
  (
    cd "${ROOT_DIR}"
    ./scripts/aws/cloud-smoke.sh
  )
  pass "Cloud smoke"
else
  info "5/6 Cloud smoke skipped (use --with-smoke)"
fi

pass "Preflight completed"
