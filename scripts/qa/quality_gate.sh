#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "[QA] Step 1/6: Flutter analyze"
flutter analyze app/lib/main.dart

echo "[QA] Step 2/6: Cloud preflight"
./scripts/aws/release-preflight.sh

echo "[QA] Step 3/6: Dependency audit"
./scripts/qa/dependency_audit.sh

echo "[QA] Step 4/6: Generate SBOM"
python3 scripts/qa/generate_sbom.py

echo "[QA] Step 5/6: Firmware build (legacy)"
platformio run -e esp32dev_board_legacy

echo "[QA] Step 6/6: Firmware build (aux)"
platformio run -e esp32dev_board_aux

echo "[QA] quality_gate: OK"
