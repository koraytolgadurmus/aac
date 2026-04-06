# Production Standard Usage & Test Runbook

Bu doküman, mevcut yapıyı "büyük üretici" disiplininde kullanmak ve test etmek için
tek akış sunar: secret yönetimi, build, provisioning, claim/recovery, cloud doğrulama.

## 1) Secret Yönetimi (Build-Time Injection)

Firmware artık secret'ları koddan değil ortam değişkeninden alır:
- `WAQI_API_TOKEN`
- `AWS_IOT_ENDPOINT`
- `AWS_IOT_PORT`
- `AWS_IOT_ROOT_CA_PEM`
- `AWS_IOT_DEVICE_CERT_PEM`
- `AWS_IOT_PRIVATE_KEY_PEM`
- `AWS_IOT_CLAIM_CERT_PEM`
- `AWS_IOT_CLAIM_PRIVATE_KEY_PEM`

Build sırasında `scripts/pio/generate_secrets_header.py` çalışır ve:
- `.pio/secrets/generated_secrets.h` üretir
- Derlemeye `-include` ile otomatik enjekte eder

Not:
- `include/config.h` artık placeholder içindir; gerçek secret kaynağı **env** olmalı.
- Secret'ları repository'ye commit etmeyin.
- Repo içindeki `certs/`, `data/`, `app/aws_iot_bootstrap/` yollarında canlı AWS cert/key/meta tutulmaz.
- Yerel geliştirme için varsayılan secret dizini: `~/.aac-secrets/aac`

## 2) Build / Flash

```bash
export AWS_IOT_ENDPOINT="xxx-ats.iot.eu-central-1.amazonaws.com"
export AWS_IOT_ROOT_CA_PEM="$(cat /secure/root_ca.pem)"
export AWS_IOT_CLAIM_CERT_PEM="$(cat /secure/claim_cert.pem)"
export AWS_IOT_CLAIM_PRIVATE_KEY_PEM="$(cat /secure/claim_key.pem)"
export WAQI_API_TOKEN="..."

platformio run -e esp32dev
platformio run -e esp32dev -t upload
```

Debug build'ler:
- `esp32dev_manual`
- `esp32dev_bleauthdebug`
- `esp32dev_sen55debug`

Build öncesi AWS secret/material taraması:
```bash
./scripts/aws/secret-scan.sh
```

## 3) İlk Kullanım (Owner Onboarding)

1. Uygulamadan cihaz QR tara.
2. App claim state kartında:
   - `QR kaydedildi`
   - `claiming`
   - `claimed`
3. Wi-Fi provisioning tamamla (BLE veya AP).
4. Cloud açıksa app cloud claim/recovery denemesini otomatik yapar.

QR kayıp senaryosu:
- Ayarlar > `Recovery kodu gir`
- `id6` + `recovery/pair token` ile akışı yeniden başlat.

## 4) Local Smoke Test (AP / Session / Scan)

Script:
- `scripts/qa/local_onboarding_smoke.sh`

Kullanım:
```bash
BASE_URL=http://192.168.4.1 \
PAIR_TOKEN="<qr_pair_token>" \
./scripts/qa/local_onboarding_smoke.sh
```

Beklenen:
- `/api/ap_info` 200
- `/api/nonce` 200
- `/api/session/open` 200 ve `token/nonce`
- `/api/status` 200
- `/api/scan` 200

## 5) Cloud Smoke Test

Mevcut cloud smoke akışı:
- `docs/cloud/smoke_test.md`
- `scripts/aws/cloud-smoke.sh`
- `scripts/aws/release-preflight.sh --with-smoke`

Örnek:
```bash
API_BASE_URL="https://..." \
ACCESS_TOKEN="eyJ..." \
DEVICE_ID="123456" \
CLAIM_SECRET="..." \
./scripts/aws/cloud-smoke.sh
```

## 6) Güvenlik Doğrulama Kontrolü

Bu sürümde aktif:
- Factory QR/AP şifre logları default kapalı
- Setup credential brute-force lockout (`setup_locked`, `retryMs`)
- Root web portal yalnız SoftAP ağından erişilebilir
- Owner varsa web root token enjeksiyonu yok

Manuel doğrulama:
1. Ardışık yanlış `AUTH_SETUP`/`CLAIM_REQUEST` sonrası lockout tetiklenmeli.
2. Lockout süresinde istekler `setup_locked` dönmeli.
3. LAN üzerinden `/` endpoint'i 403 dönmeli.
4. Owner olduktan sonra local QR fallback ile owner komutları kabul edilmemeli (imzalı/sesssion owner auth gerekli).

## 7) Release Gate (Önerilen Minimum)

Release öncesi hepsi `PASS`:
1. `platformio run` (tüm env)
2. `scripts/qa/local_onboarding_smoke.sh`
3. Cloud smoke (`scripts/aws/cloud-smoke.sh`)
4. Factory reset -> reclaim -> recovery akışı
5. 24 saat soak test (Wi-Fi reconnect, MQTT reconnect, BLE policy)

## 8) Operasyonel Kullanım Özeti

- Günlük kullanım: sadece app onboarding + cloud bağlantı.
- Destek ekibi:
  - QR kaybında kullanıcıya `recovery token` ile yönlendirme
  - Zorunlu durumda owner recovery prompt ile cloud ownership rotate
- Üretim hattı:
  - Secret'lar CI/secure vault'tan env olarak verilir
  - Cihaza özel key/token repo'ya yazılmaz.
