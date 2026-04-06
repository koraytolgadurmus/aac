#!/usr/bin/env bash
set -euo pipefail

# AAC Cloud API smoke test
# Required:
#   API_BASE_URL   e.g. https://xxxx.execute-api.eu-central-1.amazonaws.com
#   ACCESS_TOKEN   Cognito access token
# Optional:
#   DEVICE_ID      6-digit device id for device endpoints
#   CLAIM_SECRET   claim secret for claim flow
#   SMOKE_EXPECT_OWNER  1 ise owner-only route'larda 200 beklenir
#   SMOKE_TEST_SHARE    1 ise sharing route'ları da test edilir

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

API_BASE_URL="${API_BASE_URL:-}"
ACCESS_TOKEN="${ACCESS_TOKEN:-}"
DEVICE_ID="${DEVICE_ID:-}"
CLAIM_SECRET="${CLAIM_SECRET:-}"
SMOKE_STRICT_DESIRED="${SMOKE_STRICT_DESIRED:-0}"
SMOKE_EXPECT_OWNER="${SMOKE_EXPECT_OWNER:-0}"
SMOKE_TEST_SHARE="${SMOKE_TEST_SHARE:-1}"

if [[ -z "${API_BASE_URL}" || -z "${ACCESS_TOKEN}" ]]; then
  echo "Missing required env vars: API_BASE_URL, ACCESS_TOKEN" >&2
  exit 1
fi

API_BASE_URL="${API_BASE_URL%/}"

pass() { echo "[PASS] $*"; }
info() { echo "[INFO] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

auth_header=("Authorization: Bearer ${ACCESS_TOKEN}")
json_header=("Content-Type: application/json")

call_api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local tmp
  tmp="$(mktemp)"
  local code
  if [[ -n "${body}" ]]; then
    code="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "${auth_header[0]}" \
      -H "${json_header[0]}" \
      --data "${body}" \
      "${API_BASE_URL}${path}")"
  else
    code="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "${auth_header[0]}" \
      "${API_BASE_URL}${path}")"
  fi
  printf "%s\n" "${code}"
  cat "${tmp}"
  rm -f "${tmp}"
}

assert_status_2xx_or_404() {
  local status="$1"
  if [[ "${status}" =~ ^2[0-9][0-9]$ || "${status}" == "404" ]]; then
    return 0
  fi
  return 1
}

assert_status_owner_or_forbidden() {
  local status="$1"
  if [[ "${SMOKE_EXPECT_OWNER}" == "1" ]]; then
    [[ "${status}" =~ ^2[0-9][0-9]$ ]]
    return
  fi
  [[ "${status}" =~ ^2[0-9][0-9]$ || "${status}" == "403" || "${status}" == "404" ]]
}

info "Checking /health"
health="$(curl -sS "${API_BASE_URL}/health")"
echo "${health}" | jq . >/dev/null || fail "/health is not valid JSON"
echo "${health}" | jq -e '.ok == true' >/dev/null || fail "/health ok != true"
pass "/health"

info "Checking /me"
me_out="$(call_api GET /me)"
me_status="$(echo "${me_out}" | sed -n '1p')"
me_body="$(echo "${me_out}" | sed '1d')"
[[ "${me_status}" == "200" ]] || fail "/me status=${me_status}"
echo "${me_body}" | jq -e '.ok == true and .me.sub != null' >/dev/null || fail "/me body invalid"
pass "/me"

info "Checking /devices"
devices_out="$(call_api GET /devices)"
devices_status="$(echo "${devices_out}" | sed -n '1p')"
devices_body="$(echo "${devices_out}" | sed '1d')"
[[ "${devices_status}" == "200" ]] || fail "/devices status=${devices_status}"
echo "${devices_body}" | jq -e '.ok == true and (.devices | type=="array")' >/dev/null || fail "/devices body invalid"
pass "/devices"

if [[ -z "${DEVICE_ID}" ]]; then
  info "DEVICE_ID not provided; skipping device-specific tests"
  exit 0
fi

if [[ ! "${DEVICE_ID}" =~ ^[0-9]{6}$ ]]; then
  fail "DEVICE_ID must be 6 digits"
fi

if [[ -n "${CLAIM_SECRET}" ]]; then
  info "Checking claim-proof sync"
  cps_body="$(jq -nc --arg v "${CLAIM_SECRET}" '{claimSecret:$v}')"
  cps_out="$(call_api POST "/device/${DEVICE_ID}/claim-proof/sync" "${cps_body}")"
  cps_status="$(echo "${cps_out}" | sed -n '1p')"
  cps_json="$(echo "${cps_out}" | sed '1d')"
  assert_status_2xx_or_404 "${cps_status}" || fail "claim-proof/sync status=${cps_status}"
  if [[ "${cps_status}" =~ ^2 ]]; then
    echo "${cps_json}" | jq -e '.ok == true' >/dev/null || fail "claim-proof/sync body invalid"
  fi
  pass "claim-proof/sync"
fi

info "Checking claim"
claim_body='{}'
if [[ -n "${CLAIM_SECRET}" ]]; then
  claim_body="$(jq -nc --arg v "${CLAIM_SECRET}" '{claimSecret:$v}')"
fi
claim_out="$(call_api POST "/device/${DEVICE_ID}/claim" "${claim_body}")"
claim_status="$(echo "${claim_out}" | sed -n '1p')"
claim_json="$(echo "${claim_out}" | sed '1d')"
if [[ "${claim_status}" =~ ^2 ]]; then
  echo "${claim_json}" | jq -e '.ok == true and .deviceId != null' >/dev/null || fail "claim body invalid"
  pass "claim"
else
  # already_claimed / claim_proof_required etc. are acceptable in smoke mode.
  echo "${claim_json}" | jq . >/dev/null || fail "claim error body invalid JSON"
  info "claim returned status=${claim_status} (accepted for smoke if device already claimed/policy guarded)"
fi

info "Checking /device/${DEVICE_ID}/state"
state_out="$(call_api GET "/device/${DEVICE_ID}/state")"
state_status="$(echo "${state_out}" | sed -n '1p')"
state_json="$(echo "${state_out}" | sed '1d')"
assert_status_2xx_or_404 "${state_status}" || fail "state status=${state_status}"
echo "${state_json}" | jq . >/dev/null || fail "state body invalid JSON"
pass "state"

info "Checking /device/${DEVICE_ID}/capabilities"
caps_out="$(call_api GET "/device/${DEVICE_ID}/capabilities")"
caps_status="$(echo "${caps_out}" | sed -n '1p')"
caps_json="$(echo "${caps_out}" | sed '1d')"
assert_status_2xx_or_404 "${caps_status}" || fail "capabilities status=${caps_status}"
if [[ "${caps_status}" =~ ^2 ]]; then
  echo "${caps_json}" | jq -e '.ok == true and .schemaVersion != null and .capabilities != null' >/dev/null || fail "capabilities body invalid"
fi
pass "capabilities"

info "Checking /device/${DEVICE_ID}/ha/config"
ha_out="$(call_api GET "/device/${DEVICE_ID}/ha/config")"
ha_status="$(echo "${ha_out}" | sed -n '1p')"
ha_json="$(echo "${ha_out}" | sed '1d')"
assert_status_2xx_or_404 "${ha_status}" || fail "ha/config status=${ha_status}"
if [[ "${ha_status}" =~ ^2 ]]; then
  echo "${ha_json}" | jq -e '
    .ok == true
    and (.messages | type=="array")
    and (.count | type=="number")
    and (.count == (.messages | length))
    and (
      (.messages | length) == 0
      or (
        .messages[0].topic != null
        and (.messages[0].topic | type=="string")
        and (.messages[0].topic | startswith("homeassistant/"))
        and (.messages[0].payload | type=="object")
      )
    )
  ' >/dev/null || fail "ha/config body invalid"
fi
pass "ha/config"

info "Checking desired shadow update"
desired_probe_ts="$(( $(date +%s) * 1000 ))"
desired_body="$(jq -nc --argjson ts "${desired_probe_ts}" \
  '{desired:{appDebugPing:true,appDebugTs:$ts}}')"
desired_out="$(call_api POST "/device/${DEVICE_ID}/desired" "${desired_body}")"
desired_status="$(echo "${desired_out}" | sed -n '1p')"
desired_json="$(echo "${desired_out}" | sed '1d')"
assert_status_2xx_or_404 "${desired_status}" || fail "desired status=${desired_status}"
if [[ "${desired_status}" =~ ^2 ]]; then
  echo "${desired_json}" | jq -e '.ok == true' >/dev/null || fail "desired body invalid"
  info "Checking desired->state roundtrip (probeTs=${desired_probe_ts})"
  roundtrip_ok=0
  for i in 1 2 3 4 5 6; do
    poll_out="$(call_api GET "/device/${DEVICE_ID}/state")"
    poll_status="$(echo "${poll_out}" | sed -n '1p')"
    poll_json="$(echo "${poll_out}" | sed '1d')"
    if [[ "${poll_status}" =~ ^2 ]]; then
      got_ts="$(echo "${poll_json}" | jq -r '.cloud.debug.lastDesiredClientTsMs // empty')"
      if [[ -n "${got_ts}" && "${got_ts}" == "${desired_probe_ts}" ]]; then
        roundtrip_ok=1
        break
      fi
    fi
    sleep 2
  done
  if [[ "${roundtrip_ok}" == "1" ]]; then
    pass "desired->state roundtrip"
  else
    if [[ "${SMOKE_STRICT_DESIRED}" == "1" ]]; then
      fail "desired roundtrip not observed in state (set SMOKE_STRICT_DESIRED=0 to allow soft mode)"
    fi
    info "desired roundtrip not observed (soft mode)"
  fi
fi
pass "desired"

info "Checking command publish"
cmd_id="smoke-$(date +%s)"
cmd_body="$(jq -nc --arg id "${cmd_id}" '{cmdId:$id,action:"ping"}')"
cmd_out="$(call_api POST "/device/${DEVICE_ID}/cmd" "${cmd_body}")"
cmd_status="$(echo "${cmd_out}" | sed -n '1p')"
cmd_json="$(echo "${cmd_out}" | sed '1d')"
if [[ "${cmd_status}" == "429" ]]; then
  info "cmd rate-limited (acceptable): status=429"
else
  assert_status_2xx_or_404 "${cmd_status}" || fail "cmd status=${cmd_status}"
  if [[ "${cmd_status}" =~ ^2 ]]; then
    echo "${cmd_json}" | jq -e '.ok == true and .cmdId != null' >/dev/null || fail "cmd body invalid"
  fi
fi
pass "cmd"

if [[ "${SMOKE_TEST_SHARE}" == "1" ]]; then
  info "Checking ACL push"
  acl_out="$(call_api POST "/device/${DEVICE_ID}/acl/push" '{}')"
  acl_status="$(echo "${acl_out}" | sed -n '1p')"
  acl_json="$(echo "${acl_out}" | sed '1d')"
  assert_status_owner_or_forbidden "${acl_status}" || fail "acl/push status=${acl_status}"
  echo "${acl_json}" | jq . >/dev/null || fail "acl/push body invalid JSON"
  pass "acl/push"

  info "Checking members"
  members_out="$(call_api GET "/device/${DEVICE_ID}/members")"
  members_status="$(echo "${members_out}" | sed -n '1p')"
  members_json="$(echo "${members_out}" | sed '1d')"
  assert_status_owner_or_forbidden "${members_status}" || fail "members status=${members_status}"
  if [[ "${members_status}" =~ ^2 ]]; then
    echo "${members_json}" | jq -e '.ok == true and (.members | type=="array")' >/dev/null || fail "members body invalid"
  else
    echo "${members_json}" | jq . >/dev/null || fail "members error body invalid JSON"
  fi
  pass "members"

  info "Checking invites"
  invites_out="$(call_api GET "/device/${DEVICE_ID}/invites")"
  invites_status="$(echo "${invites_out}" | sed -n '1p')"
  invites_json="$(echo "${invites_out}" | sed '1d')"
  assert_status_owner_or_forbidden "${invites_status}" || fail "invites status=${invites_status}"
  if [[ "${invites_status}" =~ ^2 ]]; then
    echo "${invites_json}" | jq -e '.ok == true and (.invites | type=="array")' >/dev/null || fail "invites body invalid"
  else
    echo "${invites_json}" | jq . >/dev/null || fail "invites error body invalid JSON"
  fi
  pass "invites"

  info "Checking integrations"
  integrations_out="$(call_api GET "/device/${DEVICE_ID}/integrations")"
  integrations_status="$(echo "${integrations_out}" | sed -n '1p')"
  integrations_json="$(echo "${integrations_out}" | sed '1d')"
  assert_status_owner_or_forbidden "${integrations_status}" || fail "integrations status=${integrations_status}"
  if [[ "${integrations_status}" =~ ^2 ]]; then
    echo "${integrations_json}" | jq -e '.ok == true and (.integrations | type=="array")' >/dev/null || fail "integrations body invalid"
  else
    echo "${integrations_json}" | jq . >/dev/null || fail "integrations error body invalid JSON"
  fi
  pass "integrations"
fi

info "Smoke test completed"
