# Security Policy

Bu repo firmware, mobile app ve cloud bileşenlerini içerir. Güvenlik açıkları için
özel bildirim kanalı kullanın; issue listesine açık olarak yazmayın.

## Supported Scope

- ESP32 firmware (`src/`, `include/`)
- Mobile app (`app/lib/`)
- Cloud scripts/CDK (`scripts/aws/`, `infra/cdk/`)

## Reporting

Rapor içeriği:

- Etkilenen bileşen ve dosya yolu
- Yeniden üretim adımları
- Etki seviyesi (kimlik doğrulama atlatma, veri sızıntısı, RCE vb.)
- Mümkünse PoC ve log kesiti

## Secret Handling

- Secret/cert/private key dosyaları repoya commit edilmez.
- Build-time secret geçişi tercih edilir (`String.fromEnvironment`, CI secrets, local secret dir).
- Üretim cihazları için EC/P-256 key zorunludur.

## Release Security Gates

Üretim release öncesi minimum kapılar:

1. `./scripts/aws/release-preflight.sh --with-firmware --firmware-env esp32dev_board_legacy --strict-prod --prod-evidence <json>`
2. `./scripts/aws/release-preflight.sh --with-smoke --env-file scripts/aws/smoke.env`
3. CI Quality Gate yeşil (`.github/workflows/quality-gate.yml`)
4. SBOM güncel (`python3 scripts/qa/generate_sbom.py`)
5. Release attestation mevcut (`scripts/production/generate_release_attestation.py`)
