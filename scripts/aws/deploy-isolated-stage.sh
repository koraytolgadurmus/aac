#!/usr/bin/env bash
set -euo pipefail

# Deploy an isolated AAC cloud stack without touching existing stacks.
#
# Example:
#   ./scripts/aws/deploy-isolated-stage.sh --stage next --from-stack AacCloud-dev

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STAGE="next"
FROM_STACK="AacCloud-dev"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-central-1}}"
CALLBACK_URLS="com.koray.artaircleaner://callback"
SIGNOUT_URLS="com.koray.artaircleaner://callback"
IOT_DATA_ENDPOINT=""
PROVISIONING_ROLE_ARN=""

pass() { echo "[PASS] $*"; }
info() { echo "[INFO] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --stage NAME           New isolated stage name (default: ${STAGE})
  --from-stack NAME      Read IotDataEndpoint/ProvisioningRoleArn from existing stack (default: ${FROM_STACK})
  --iot-endpoint HOST    Explicit IoT Data endpoint (overrides --from-stack)
  --provision-role ARN   Explicit provisioning role ARN (overrides --from-stack)
  --region REGION        AWS region (default: ${REGION})
  --callback-urls CSV    Cognito callback URLs (default app deep link)
  --signout-urls CSV     Cognito signout URLs (default app deep link)
  -h, --help             Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)
      [[ $# -ge 2 ]] || fail "--stage requires a value"
      STAGE="$2"
      shift 2
      ;;
    --from-stack)
      [[ $# -ge 2 ]] || fail "--from-stack requires a value"
      FROM_STACK="$2"
      shift 2
      ;;
    --iot-endpoint)
      [[ $# -ge 2 ]] || fail "--iot-endpoint requires a value"
      IOT_DATA_ENDPOINT="$2"
      shift 2
      ;;
    --provision-role)
      [[ $# -ge 2 ]] || fail "--provision-role requires a value"
      PROVISIONING_ROLE_ARN="$2"
      shift 2
      ;;
    --region)
      [[ $# -ge 2 ]] || fail "--region requires a value"
      REGION="$2"
      shift 2
      ;;
    --callback-urls)
      [[ $# -ge 2 ]] || fail "--callback-urls requires a value"
      CALLBACK_URLS="$2"
      shift 2
      ;;
    --signout-urls)
      [[ $# -ge 2 ]] || fail "--signout-urls requires a value"
      SIGNOUT_URLS="$2"
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

if ! command -v aws >/dev/null 2>&1; then
  fail "aws cli is required"
fi
if ! command -v npm >/dev/null 2>&1; then
  fail "npm is required"
fi

STACK_NAME="AacCloud-${STAGE}"

if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" >/dev/null 2>&1; then
  fail "Stack already exists: ${STACK_NAME}. Pick another --stage."
fi

if [[ -z "${IOT_DATA_ENDPOINT}" || -z "${PROVISIONING_ROLE_ARN}" ]]; then
  info "Reading deployment params from ${FROM_STACK}"
  [[ -n "${FROM_STACK}" ]] || fail "Missing --from-stack"
  if [[ -z "${IOT_DATA_ENDPOINT}" ]]; then
    IOT_DATA_ENDPOINT="$(aws cloudformation describe-stacks \
      --stack-name "${FROM_STACK}" \
      --query "Stacks[0].Parameters[?ParameterKey=='IotDataEndpoint'].ParameterValue" \
      --output text)"
  fi
  if [[ -z "${PROVISIONING_ROLE_ARN}" ]]; then
    PROVISIONING_ROLE_ARN="$(aws cloudformation describe-stacks \
      --stack-name "${FROM_STACK}" \
      --query "Stacks[0].Parameters[?ParameterKey=='ProvisioningRoleArn'].ParameterValue" \
      --output text)"
  fi
fi

[[ -n "${IOT_DATA_ENDPOINT}" && "${IOT_DATA_ENDPOINT}" != "None" ]] || fail "IotDataEndpoint is empty"
[[ -n "${PROVISIONING_ROLE_ARN}" && "${PROVISIONING_ROLE_ARN}" != "None" ]] || fail "ProvisioningRoleArn is empty"

info "Deploying isolated stack: ${STACK_NAME}"
(
  cd "${ROOT_DIR}/infra/cdk"
  npm run deploy -- \
    --context stage="${STAGE}" \
    --parameters IotDataEndpoint="${IOT_DATA_ENDPOINT}" \
    --parameters ProvisioningRoleArn="${PROVISIONING_ROLE_ARN}" \
    --parameters CognitoCallbackUrls="${CALLBACK_URLS}" \
    --parameters CognitoSignoutUrls="${SIGNOUT_URLS}" \
    --require-approval never
)

pass "Deploy complete: ${STACK_NAME}"

info "Generating smoke env from stack outputs"
"${ROOT_DIR}/scripts/aws/init-smoke-env.sh" "${STACK_NAME}" "${ROOT_DIR}/scripts/aws/smoke.env"

echo
echo "Use these helpers:"
echo "  eval \"\$(${ROOT_DIR}/scripts/aws/export-cloud-env.sh ${STACK_NAME})\""
echo "  ${ROOT_DIR}/scripts/aws/run-cloud-smoke.sh"
