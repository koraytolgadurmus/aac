#!/usr/bin/env bash
set -euo pipefail

# Tail cloud API Lambda logs for a stack.
# Usage:
#   ./scripts/aws/tail-cloud-logs.sh
#   ./scripts/aws/tail-cloud-logs.sh AacCloud-dev 30m

STACK_NAME="${1:-AacCloud-dev}"
SINCE="${2:-30m}"

FN_NAME="$(aws cloudformation describe-stack-resources \
  --stack-name "$STACK_NAME" \
  --query "StackResources[?ResourceType=='AWS::Lambda::Function' && starts_with(PhysicalResourceId, 'aac-')].PhysicalResourceId | [0]" \
  --output text)"

if [[ -z "$FN_NAME" || "$FN_NAME" == "None" ]]; then
  echo "Lambda function not found for stack: $STACK_NAME" >&2
  exit 1
fi

LOG_GROUP="/aws/lambda/${FN_NAME}"
echo "[INFO] Tailing $LOG_GROUP (since $SINCE)"

aws logs tail "$LOG_GROUP" --since "$SINCE" --follow --format short
