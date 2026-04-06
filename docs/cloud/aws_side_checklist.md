# AWS Side Checklist (Cloud Module)

Bu kontrol listesi, cloud modülünü güvenli ve çalışır şekilde ayağa kaldırmak için
AWS tarafında doğrulanması gereken ayarları özetler.

Release adımları için: `docs/cloud/release_runbook.md`
Hazır env/policy paket dosyaları: `docs/cloud/aws_cloud_api_setup_pack.md`

## 1) Cognito App Client (Hosted UI)

- [ ] `Callback URL(s)` içinde mobil redirect URI mevcut:
  - [ ] `com.koray.artaircleaner://callback`
  - [ ] Android/iOS için kullanılan ek URI'ler (varsa)
- [ ] `Sign out URL(s)` callback ile uyumlu.
- [ ] OAuth flow: `Authorization code grant` aktif.
- [ ] OAuth scope: en az `openid`, `email`, `profile`.
- [ ] App client `secret` kapalı (public mobile client).
- [ ] Token süreleri mobil kullanım için makul (access/id ~60dk, refresh uzun).

## 2) API Gateway JWT Authorizer

- [ ] Issuer: `https://cognito-idp.<region>.amazonaws.com/<userPoolId>`
- [ ] Audience: Cognito app client id
- [ ] Aşağıdaki route'lar JWT ile korunuyor:
  - [ ] `/me`, `/devices`
  - [ ] `/device/{id6}/claim`, `/claim-proof/sync`, `/unclaim`
  - [ ] `/device/{id6}/state`, `/capabilities`, `/ha/config`, `/desired`, `/cmd`
  - [ ] invite/member route'ları
- [ ] Sadece `/health` ve `/healthz` public.

## 3) IoT Policy (Claim vs Thing)

### Secret / Artifact hygiene
- [ ] Claim/device private key hiçbir repo yolunda tutulmuyor.
- [ ] Claim/device certificate ve ARN/meta artifact'ları repo yerine secure vault veya `AAC_SECRET_DIR` altında tutuluyor.
- [ ] Eski claim/device cert'ler revoke/rotate edildi.

### Claim certificate policy
- [ ] Sadece provisioning topic'lerine izin:
  - [ ] `$aws/certificates/create/*`
  - [ ] `$aws/provisioning-templates/*`
- [ ] Normal device topic'lerine (`aac/{id6}/*`) publish/subscribe yok.

### Thing certificate policy
- [ ] Client connect sadece kendi thing adına izinli.
- [ ] Topic yetkisi sadece kendi `id6` scope'unda:
  - [ ] `aac/${iot:Connection.Thing.Attributes[id6]}/*`
- [ ] Shadow/jobs topicleri sadece kendi `ThingName`.
- [ ] Cross-device wildcard yetkisi yok.

## 4) Fleet Provisioning Template

- [ ] Thing adı deterministik: `aac-{Id6}`.
- [ ] Thing attribute içinde `id6` ve `serialNumber` yazılıyor.
- [ ] Provision sırasında `thing` + `certificate` + `policy` bağlanıyor.
- [ ] Provisioning role least-privilege (template için gerekli aksiyonlar dışında izin yok).

## 5) Lambda IAM / Least Privilege

- [ ] DynamoDB izinleri sadece kullanılan tablolar (+ gerekli index) ile sınırlı.
- [ ] IoT data-plane izinleri:
  - [ ] `iot:Publish` -> `topic/aac/*/cmd`
  - [ ] `iot:GetThingShadow`, `iot:UpdateThingShadow` -> `thing/aac-*`
- [ ] IoT Jobs control-plane izinleri yalnız gereken aksiyonlar:
  - [ ] `iot:CreateJob`, `iot:DescribeJob`, `iot:CancelJob`
- [ ] Fazla geniş `*` resource/policy yok.

## 6) S3 OTA Bucket

- [ ] Public access block aktif.
- [ ] TLS zorunlu (`aws:SecureTransport=false` deny).
- [ ] Versioning açık.
- [ ] Bucket policy public read vermiyor.
- [ ] OTA artifact upload path/prefix stratejisi tanımlı (örn: `firmware/<device-class>/...`).

## 7) IoT Rule / State Pipeline

- [ ] Device state akışı net:
  - [ ] Ana kaynak: IoT Shadow reported
  - [ ] DDB fallback sadece gerektiğinde
- [ ] Claim proof hash düz token içermiyor (`sha256` hash only).
- [ ] Telemetry/state rule'larında gereksiz veri kopyalama yok.

## 8) Operasyonel Kontrol

- [ ] Cloud smoke test çalıştırıldı:
  - [ ] `/health`, `/me`, `/devices`
  - [ ] `/state`, `/capabilities`, `/ha/config`, `/desired`, `/cmd`
- [ ] CloudWatch loglarında `claim_denied`, `cmd_rate_limited`, `cmd_duplicate` audit eventleri izleniyor.
- [ ] `FEATURE_*` flag'leri stage'e uygun:
  - [ ] prod: güvenlik flagleri açık
  - [ ] dev: test için kontrollü esneklik
- [ ] SLO/incident standardı ile alert eşikleri hizalı:
  - [ ] `docs/ops/slo_incident_standard.md`

## 9) Supply Chain & Attestation

- [ ] SBOM güncel:
  - `python3 scripts/qa/generate_sbom.py`
- [ ] Release attestation üretildi ve saklandı:
  - `python3 scripts/production/generate_release_attestation.py ...`

## 10) Deployment Sonrası Hızlı Doğrulama

- [ ] CDK output değerleri app config'e işlendi.
- [ ] Hosted UI login akışı `redirect_mismatch` vermiyor.
- [ ] Flutter cloud sync `/me` ve `/devices` üzerinden state/features alıyor.
- [ ] ESP32 local mod cloud kapalıyken etkilenmiyor (local kontrol %100 çalışıyor).
