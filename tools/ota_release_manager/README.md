# AAC OTA Release Manager

Yerel masaustu uygulamasi: firmware sec -> SHA256 hesapla -> S3 upload -> OTA job/campaign olustur.

## Gereksinimler
- macOS/Linux
- `python3` (tkinter destekli)
- `aws` CLI
- AWS CLI login/config (`aws configure`)

## Calistirma

### Mac'te cift tik ile
- `run.command` dosyasina cift tikla.

### Terminal ile
```bash
python3 tools/ota_release_manager/app.py
```

Legacy uyumluluk girişi:
```bash
python3 scripts/aws/release_manager.py
```

## macOS Crash Notu (Tkinter)
Eger acilista Python crash alirsan (genelde Xcode Python 3.9 + Tk 8.5):

```bash
brew install python
```

Ardindan `run.command` tekrar calistir. Launcher modern Python'u otomatik secmeye calisir.

## Uygulama Akisi
1. API Base URL gir.
2. `Cognito Login` alanında region/userPoolId/clientId/e-posta/şifre girip `JWT Al` butonuna bas.
3. JWT alanı otomatik dolar.
4. Firmware `.bin` dosyasi sec.
5. Version + target (`product/hwRev/boardRev/fwChannel`) gir.
6. `stable` release için `strictProd` açık tut ve production evidence JSON seç.
7. `Tek cihaz` veya `Campaign` sec.
8. `Yayinla`.

Uygulama otomatik olarak:
- SHA256 hesaplar
- S3'e yukler (`firmware/<product>/<hwRev>/<fwChannel>/<version>/firmware.bin`)
- OTA endpoint'ine request atar
- `stable` release'te strict production preflight calistirir

## Notlar
- Device endpoint: `/device/{id6}/ota/job`
- Campaign endpoint: `/ota/campaign`
- Config dosyasi: `~/.aac_release_manager.json`
- Cognito token alma adimi AWS CLI ile önce `initiate-auth (USER_PASSWORD_AUTH)`, bu kapaliysa otomatik `admin-initiate-auth (ADMIN_USER_PASSWORD_AUTH)` dener.
- Production evidence örneği: `docs/production_security_evidence.example.json`
