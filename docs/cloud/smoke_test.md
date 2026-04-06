# Cloud Smoke Test

Bu doküman, cloud API için hızlı uçtan uca doğrulama adımlarını içerir.

Script: `scripts/aws/cloud-smoke.sh`
Wrapper: `scripts/aws/run-cloud-smoke.sh`

İlgili dokümanlar:
- AWS kontrol listesi: `docs/cloud/aws_side_checklist.md`
- Release runbook: `docs/cloud/release_runbook.md`

## Gereksinimler

- `curl`
- `jq`
- Geçerli Cognito access token

## Zorunlu değişkenler

- `API_BASE_URL`  
  Örn: `https://xxxx.execute-api.eu-central-1.amazonaws.com`
- `ACCESS_TOKEN`  
  Cognito JWT access token

## Opsiyonel değişkenler

- `DEVICE_ID` (6 haneli)
- `CLAIM_SECRET`
- `SMOKE_STRICT_DESIRED` (`1` ise desired->state roundtrip zorunlu, varsayılan `0`)

`DEVICE_ID` verilirse cihaz endpointleri de test edilir:
- claim-proof sync
- claim
- state
- capabilities
- ha/config
- desired
- cmd

## Çalıştırma

### Seçenek 1: Direkt env export ile

```bash
API_BASE_URL="https://xxxx.execute-api.eu-central-1.amazonaws.com" \
ACCESS_TOKEN="eyJ..." \
DEVICE_ID="123456" \
CLAIM_SECRET="your-claim-secret" \
./scripts/aws/cloud-smoke.sh
```

### Seçenek 2: Env dosyası ile (önerilen)

```bash
# Otomatik doldur (stack output'lardan)
./scripts/aws/init-smoke-env.sh AacCloud-dev scripts/aws/smoke.env
# ACCESS_TOKEN ve DEVICE_ID alanlarını doldur
./scripts/aws/run-cloud-smoke.sh
```

Not: `scripts/aws/smoke.env` dosyası `.gitignore` içinde tutulur, repoya commit edilmemelidir.

## Beklenen davranış

- `/health`, `/me`, `/devices` başarılı olmalı.
- Cihaz adımlarında bazı cevaplar politika gereği `404`, `403` veya `429` olabilir.
- Script, smoke amacıyla bu beklenen varyasyonları tolere eder ve kritik hatada durur.
- `desired` adımında script, `appDebugPing/appDebugTs` gönderip state içinde
  `cloud.debug.lastDesiredClientTsMs` alanını poll eder.
  - `SMOKE_STRICT_DESIRED=0`: sadece bilgi amaçlı (soft check)
  - `SMOKE_STRICT_DESIRED=1`: roundtrip görünmezse fail eder
- `ha/config` adımında script, response içindeki `messages` formatını doğrular:
  - `count == messages.length`
  - ilk mesajda `topic` (`homeassistant/...`) ve `payload` object yapısı

## CI entegrasyonu

Workflow: `.github/workflows/cloud-ci.yml`

- Her push/PR:
  - `scripts/aws/release-preflight.sh` (CDK build + Lambda syntax)
- Secret'lar tanımlıysa ek olarak smoke test:
  - `CLOUD_SMOKE_API_BASE_URL` (zorunlu)
  - `CLOUD_SMOKE_ACCESS_TOKEN` (zorunlu)
  - `CLOUD_SMOKE_DEVICE_ID` (opsiyonel)
  - `CLOUD_SMOKE_CLAIM_SECRET` (opsiyonel)
