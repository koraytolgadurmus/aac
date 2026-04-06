#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="${1:-AacCloud-next}"

get_out() {
  local key="$1"
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='${key}'].OutputValue" \
    --output text
}

API_BASE_URL="$(get_out HttpApiUrl)"
COGNITO_USER_POOL_ID="$(get_out CognitoUserPoolId)"
COGNITO_CLIENT_ID="$(get_out CognitoClientId)"
COGNITO_ISSUER="$(get_out CognitoIssuer)"
COGNITO_HOSTED_DOMAIN_URL="$(get_out CognitoHostedDomainUrl)"

cat <<ENVVARS
export API_BASE_URL='${API_BASE_URL}'
export COGNITO_USER_POOL_ID='${COGNITO_USER_POOL_ID}'
export COGNITO_CLIENT_ID='${COGNITO_CLIENT_ID}'
export COGNITO_ISSUER='${COGNITO_ISSUER}'
export COGNITO_HOSTED_DOMAIN='${COGNITO_HOSTED_DOMAIN_URL#https://}'
ENVVARS
