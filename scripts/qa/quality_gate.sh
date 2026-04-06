#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "[QA] Step 1/8: Flutter analyze"
(
  cd app
  flutter pub get
  flutter analyze lib/main.dart
)

echo "[QA] Step 2/8: Cloud preflight"
./scripts/aws/release-preflight.sh

echo "[QA] Step 3/8: Dependency audit"
./scripts/qa/dependency_audit.sh

echo "[QA] Step 4/8: Secret scan"
./scripts/aws/secret-scan.sh

echo "[QA] Step 5/8: Version policy check"
./scripts/qa/version_policy_check.sh

echo "[QA] Step 6/8: Generate SBOM"
python3 scripts/qa/generate_sbom.py

echo "[QA] Step 7/8: Firmware build (legacy)"
platformio run -e esp32dev_board_legacy

echo "[QA] Step 8/8: Firmware build (aux)"
platformio run -e esp32dev_board_aux

echo "[QA] quality_gate: OK"
