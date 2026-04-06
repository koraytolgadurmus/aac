# ESP32 Secure Boot + Flash Encryption (Production Checklist)

Bu adımlar **kod değişikliği değil**, üretim/provisioning adımıdır.

## Özet

1. **Secure Boot v2** aktif et (eFuse).
2. **Flash Encryption** aktif et (eFuse).
3. OTA ve NVS dahil tüm flash içeriği şifreli olur.
4. Üretim release'inden once kanit JSON'u üret ve sakla.

## PlatformIO / ESP-IDF notları

- Secure Boot + Flash Encryption genelde **ESP-IDF tooling** ile yapılır.
- Arduino/PlatformIO build’leri için:
  - Bootloader imzalama
  - Partition table imzalama
  - Application imzalama
  - Efuse yakma

## Önerilen üretim akışı (özet)

1. **Anahtar üretimi**
   - Secure Boot signing key
   - Flash encryption key
2. **Cihaz başlatma**
   - Efuse’ları yaz (secure boot + flash encryption)
3. **İlk firmware flash**
   - İmzalı bootloader + app
4. **Doğrulama**
   - Secure boot açık mı?
   - Flash encryption aktif mi?
   - Device key tipi EC/P-256 mi?
   - Kanıt JSON'u oluşturuldu mu?

## Production Evidence JSON

`strict-prod` kapısı artık doğrulanabilir bir kanıt dosyası ister.
Örnek şema:

- Örnek dosya: `docs/production_security_evidence.example.json`
- Zorunlu alanlar:
  - `schemaVersion = 1`
  - `secureBoot.enabled = true`
  - `secureBoot.version = "v2"`
  - `flashEncryption.enabled = true`
  - `deviceIdentity.keyType = "ec-p256"`
  - `evidence.generatedAt`
  - `evidence.verifiedBy`

Önerilen üretim komutu:

```bash
./scripts/aws/release-preflight.sh \
  --with-firmware \
  --firmware-env esp32dev_board_legacy \
  --strict-prod \
  --prod-evidence /path/to/production-evidence.json
```

Evidence dosyasını üretmek için:

```bash
python3 scripts/production/generate_security_evidence.py \
  --espefuse-summary /path/to/espefuse-summary.txt \
  --device-key "$AAC_SECRET_DIR/device_private.key" \
  --device-id 709373 \
  --board-rev esp32dev-legacy \
  --verified-by factory-line-01 \
  --output /path/to/production-evidence.json
```

## Risk uyarısı

Efuse **geri alınamaz**. Üretim ortamında test cihazlarıyla doğrulayın.

## Not

Bu repo içinde Secure Boot/Flash Encryption hala cihaz provisioning adımıdır.
Ancak artık `strict-prod` release kapısı, bunun yapıldığına dair kanıt JSON'u olmadan geçmez.
