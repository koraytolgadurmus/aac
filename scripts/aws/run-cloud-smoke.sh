#!/usr/bin/env bash
set -euo pipefail

# Wrapper for scripts/aws/cloud-smoke.sh with env-file loading.
# Default env file: scripts/aws/smoke.env
# Usage:
#   ./scripts/aws/run-cloud-smoke.sh
#   ./scripts/aws/run-cloud-smoke.sh --env-file scripts/aws/smoke.env

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ROOT_DIR}/scripts/aws/smoke.env"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--env-file PATH]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || { echo "--env-file requires a value" >&2; exit 1; }
      ENV_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env file not found: $ENV_FILE" >&2
  echo "Copy scripts/aws/smoke.env.example to scripts/aws/smoke.env and edit values." >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

cd "$ROOT_DIR"
./scripts/aws/cloud-smoke.sh
