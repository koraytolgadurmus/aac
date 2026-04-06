# AAC Production Go-Live Checklist

Bu checklist, pilot seviyesinden seri üretim seviyesine geçişte minimum kalite kapılarını tanımlar.

## 1) Firmware Build Profiles

- [ ] `platformio.ini` içinde iki board env mevcut:
  - [ ] `esp32dev_board_legacy`
  - [ ] `esp32dev_board_aux`
- [ ] Legacy kart build:
  - `pio run -e esp32dev_board_legacy`
- [ ] Aux kart build:
  - `pio run -e esp32dev_board_aux`

## 2) Cloud Release Preflight

- [ ] CI kalite kapıları yeşil:
  - [ ] `Quality Gate / quality-gate`
  - [ ] `Cloud CI / cloud-checks`
- [ ] Tek komut yerel kalite kapısı:
  - `./scripts/qa/quality_gate.sh`
- [ ] Branch protection standard uygulandı:
  - [ ] `docs/ops/branch_protection_standard.md`
- [ ] Standart preflight:
  - `./scripts/aws/release-preflight.sh`
- [ ] Üretim preflight (hard gate):
  - `./scripts/aws/release-preflight.sh --with-firmware --firmware-env esp32dev_board_legacy --strict-prod`
- [ ] Smoke test:
  - `./scripts/aws/release-preflight.sh --with-smoke --env-file scripts/aws/smoke.env`

## 3) TLS / Certificate Quality Gate

- [ ] Device key tipi EC/P-256 (RSA değil)
- [ ] `strict-prod` evidence JSON mevcut ve doğrulanıyor
- [ ] Secure Boot v2 aktif kanıtı mevcut
- [ ] Flash Encryption aktif kanıtı mevcut
- [ ] Kanıt JSON'u `scripts/production/generate_security_evidence.py` ile üretildi
- [ ] Claim -> device cert provisioning akışı başarılı
- [ ] MQTT reconnect loop gözlenmiyor (en az 30 dk stabil)

## 4) Functional Factory Tests (Per Device)

- [ ] BLE pair + auth + Wi-Fi provisioning
- [ ] Local API `/api/status` + `/api/cmd`
- [ ] Cloud claim + owner role + ACL push
- [ ] Fan PWM command etkisi fiziksel olarak doğrulandı
- [ ] Tüm relay çıkışları doğrulandı

## 5) Soak / Reliability

- [ ] 24 saat sürekli çalışma
- [ ] Wi-Fi kesinti / geri gelme senaryosu
- [ ] Router reboot sonrası otomatik toparlama
- [ ] Güç kesintisi sonrası boot + cloud relink

## 6) Release & Rollback

- [ ] Sürüm notu ve hedef board env kaydı
- [ ] SBOM üretildi:
  - `python3 scripts/qa/generate_sbom.py`
- [ ] Release attestation üretildi:
  - `python3 scripts/production/generate_release_attestation.py --firmware-bin <bin> --firmware-env <env> --version <ver> --board-rev <rev> --output <json>`
- [ ] Rollback komutu ve önceki stabil sürüm hazır
- [ ] CloudWatch alarmları aktif (5xx, claim fail, mqtt connect fail)

## 7) Operations & SLO

- [ ] SLO/incident standard aktif:
  - [ ] `docs/ops/slo_incident_standard.md`
- [ ] On-call sahibi ve escalation rotası tanımlı
