# Cloud Release Runbook

Bu doküman, cloud backend değişikliklerini kontrollü şekilde canlıya almak için
minimum release akışını tanımlar.

İlgili dokümanlar:
- AWS kontrol listesi: `docs/cloud/aws_side_checklist.md`
- Smoke test: `docs/cloud/smoke_test.md`
- Branch protection: `docs/ops/branch_protection_standard.md`
- SLO/incident standard: `docs/ops/slo_incident_standard.md`

## 0) Kapsam

Bu runbook aşağıdaki parçaları kapsar:
- CDK stack (`infra/cdk`)
- Lambda (`scripts/aws/aac-cloud-api.js`)
- API route değişiklikleri
- Shadow/HA/claim/membership akışları

Local (BLE/SoftAP/local HTTP) akışı bu release planının dışında tutulur ve
cloud kapalıyken etkilenmemelidir.

## 1) Pre-Deploy

- [ ] CI required checks yeşil:
  - [ ] `Quality Gate / quality-gate`
  - [ ] `Cloud CI / cloud-checks`
  - [ ] (Varsa) repo branch protection altında tanımlı diğer zorunlu checkler

- [ ] Tek komut preflight (önerilen):

```bash
./scripts/aws/release-preflight.sh
```

- [ ] Branch güncel ve CI yeşil.
- [ ] `infra/cdk` build başarılı:

```bash
cd infra/cdk
npm ci
npm run -s build
```

- [ ] Lambda syntax kontrolü:

```bash
node --check scripts/aws/aac-cloud-api.js
```

- [ ] ESP32 build kırılmıyor (cloud hook değiştiyse):

```bash
pio run -e esp32dev
```

- [ ] `docs/cloud/aws_side_checklist.md` maddeleri stage için gözden geçirildi.

Opsiyonel:

```bash
# Firmware build dahil
./scripts/aws/release-preflight.sh --with-firmware

# Smoke dahil (API_BASE_URL ve ACCESS_TOKEN zorunlu)
API_BASE_URL="https://<api-id>.execute-api.<region>.amazonaws.com" \
ACCESS_TOKEN="<jwt>" \
DEVICE_ID="<id6>" \
./scripts/aws/release-preflight.sh --with-smoke

# Smoke dahil (env dosyası ile)
./scripts/aws/release-preflight.sh --with-smoke --env-file scripts/aws/smoke.env

# Üretim kapıları (board env + key type)
./scripts/aws/release-preflight.sh --with-firmware --firmware-env esp32dev_board_legacy --strict-prod --prod-evidence /path/to/production-evidence.json

# SBOM üret
python3 scripts/qa/generate_sbom.py

# Release attestation üret
python3 scripts/production/generate_release_attestation.py \
  --firmware-bin .pio/build/esp32dev_board_legacy/firmware.bin \
  --firmware-env esp32dev_board_legacy \
  --version <fw-version> \
  --board-rev esp32dev-legacy \
  --output docs/audit/attestations/<fw-version>.json
```

`strict-prod` artık şunları zorunlu kılar:
- board-specific firmware env (`esp32dev_board_legacy` veya `esp32dev_board_aux`)
- EC/P-256 device key
- secure boot + flash encryption kanıt JSON'u

Kanıt JSON'u üretimi:

```bash
python3 scripts/production/generate_security_evidence.py \
  --espefuse-summary /path/to/espefuse-summary.txt \
  --device-key "$AAC_SECRET_DIR/device_private.key" \
  --device-id <id6> \
  --board-rev esp32dev-legacy \
  --verified-by <operator> \
  --output /path/to/production-evidence.json
```

## 2) Deploy

```bash
cd infra/cdk
npx cdk synth
npx cdk deploy AacCloud-<stage>
```

Notlar:
- `stage` için doğru callback/signout URL parametreleri verildiğinden emin olun.
- Gerekirse `IotDataEndpoint` ve `ProvisioningRoleArn` parametrelerini açık verin.

## 3) Post-Deploy (Hızlı Doğrulama)

- [ ] `/health` ve `/me` yanıtları beklenen.
- [ ] `FEATURE_*` bayrakları `/me.cloud.features` içinde doğru.
- [ ] Kritik route’lar çalışıyor:
  - [ ] `/device/{id6}/state`
  - [ ] `/device/{id6}/capabilities`
  - [ ] `/device/{id6}/ha/config`
  - [ ] `/device/{id6}/desired`
  - [ ] `/device/{id6}/cmd`

Smoke testi:

```bash
API_BASE_URL="https://<api-id>.execute-api.<region>.amazonaws.com" \
ACCESS_TOKEN="<jwt>" \
DEVICE_ID="<id6>" \
CLAIM_SECRET="<optional>" \
./scripts/aws/cloud-smoke.sh
```

Stack output env'lerini hızlı almak için:

```bash
eval "$(./scripts/aws/export-cloud-env.sh AacCloud-dev)"
```

Env dosyasıyla alternatif:

```bash
cp scripts/aws/smoke.env.example scripts/aws/smoke.env
./scripts/aws/run-cloud-smoke.sh
```

## 4) Canary / Gözlem

Deploy sonrası en az kısa bir gözlem penceresi önerilir:
- CloudWatch Lambda error rate
- `claim_denied`, `cmd_rate_limited`, `cmd_duplicate` audit event yoğunluğu
- API Gateway 4xx/5xx trendi

## 5) Rollback

Öncelik sırası:
1. Feature flag kapatma (`FEATURE_*`) ile davranışı daralt.
2. Gerekirse stack’i önceki stabil commit/tag’e döndürüp yeniden deploy et.

Örnek:

```bash
# repo'da önceki stabil tag/commit checkout edildikten sonra
cd infra/cdk
npm run -s build
npx cdk deploy AacCloud-<stage>
```

## 6) Release Notu (Önerilen Şablon)

- Değişen endpointler:
- Yeni env/feature flag:
- DDB/IoT/Cognito etkisi:
- Geri dönüş planı:
- Smoke sonucu (komut + özet):
