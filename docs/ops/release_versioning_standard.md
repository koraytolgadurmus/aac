# Release & Versioning Standard

Bu repo için sürümleme standardı:

## Firmware (`src/main.cpp`)

- `FW_VERSION` semver formatında olmalı: `x.y.z`
- Opsiyonel pre-release/build metadata kullanılabilir:
  - `x.y.z-rc.1`
  - `x.y.z+build.45`

## Mobile App (`app/pubspec.yaml`)

- Flutter sürümü `x.y.z+build` formatında olmalı.
- Örnek: `1.0.0+1`

## Policy Gate

- Script: `scripts/qa/version_policy_check.sh`
- CI: `quality-gate` workflow içinde zorunlu adım olarak çalışır.

## Release Discipline

- `main` branch yalnızca PR ile güncellenir.
- Release checklist workflow:
  - `.github/workflows/release-checklist.yml`
  - `v*` tag push ile otomatik çalışır.
- Release notları ve artefact doğrulaması:
  - `scripts/production/generate_release_attestation.py`
  - `docs/cloud/release_runbook.md`
