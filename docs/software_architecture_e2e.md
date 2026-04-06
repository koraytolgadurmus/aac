# ArtAirCleaner Uçtan Uca Yazılım Mimarisi

- Doküman türü: Yazılım mimari dokümanı (E2E)
- Kapsam: Mobil uygulama, ESP32 firmware, cloud/backend, güvenlik, operasyon
- Son güncelleme: 2026-02-17
- Hedef kitle: Yazılım geliştiriciler, firmware geliştiriciler, DevOps, teknik paydaşlar

## 1. Amaç ve Kapsam

Bu doküman ArtAirCleaner sisteminin uçtan uca yazılım mimarisini açıklar.

Temel amaçlar:
- Cihazın yerel ve bulut üzerinden güvenli kontrolünü sağlamak
- İlk kurulum (onboarding) akışını BLE + Wi-Fi provisioning ile gerçekleştirmek
- Owner/User yetki modelini ACL ile yönetmek
- Bağlantı kesintilerinde otomatik toparlanan (resilient) bir yapı kurmak
- Operasyonel gözlemlenebilirlik ve sürdürülebilir bakım sağlamak

Kapsam dışı:
- Endüstriyel mekanik tasarım detayları
- Elektrik şeması bileşen seviyesinde üretim detayları
- Mobil UI tasarım sisteminin tüm ekran bazlı detayları

## 2. Sistem Özeti

Sistem üç ana katmandan oluşur:

1. Cihaz katmanı (ESP32 firmware)
- Sensör okuma, aktüatör kontrolü, yerel API, BLE eşleştirme, cloud MQTT istemcisi

2. Uygulama katmanı (Flutter mobile app)
- Onboarding, cihaz yönetimi, kontrol komutları, cloud kimlik doğrulama, fallback karar mekanizması

3. Cloud katmanı (AWS)
- API Gateway tabanlı HTTP uçları, kimlik doğrulama, cihaz state/ACL yönetimi, AWS IoT MQTT yönlendirme

## 3. Teknoloji Yığını

### 3.1 Mobil Uygulama
- Dil/SDK: Dart + Flutter
- Platform: iOS (ana), Android (genişletilebilir)
- BLE: `flutter_blue_plus`
- Güvenli saklama: `flutter_secure_storage`
- Yerel durum: `shared_preferences`
- Ağ: `http`
- i18n: Uygulama içi çoklu dil haritalama

### 3.2 Firmware
- Dil/Framework: C++ (Arduino framework)
- Build sistemi: PlatformIO
- MCU: ESP32
- BLE stack: NimBLE
- HTTP server: WebServer
- Local storage: Preferences, SPIFFS
- Cloud: MQTT istemcisi (TLS)
- Sensör kütüphaneleri: BSEC2, BME, SEN5X vb.

### 3.3 Backend/Cloud
- API giriş: AWS API Gateway
- Kimlik: AWS Cognito/OIDC tabanlı token akışı
- IoT iletişim: AWS IoT Core (MQTT)
- Yetki/veri: ACL, device state, invite/member akışları
- Altyapı kodu: CDK tabanlı bileşenler (infra/cdk)

### 3.4 Teknoloji-Konum Matrisi (Repo Bazlı)

Bu bölüm, "hangi teknoloji nerede kullanılıyor" sorusunu doğrudan dosya/yol bazında cevaplar.

1. ESP32 Firmware (runtime)
- Dil/Framework: C++ + Arduino framework
- Konfigürasyon: `platformio.ini`
- Ana kaynak: `src/main.cpp`
- Build/Toolchain: PlatformIO (`espressif32`, `esp32dev`)
- Firmware kütüphaneleri (örnek): NimBLE, ArduinoJson, PubSubClient, BSEC2, BME/SEN5x (`platformio.ini` içindeki `lib_deps`)

2. Mobil Uygulama (runtime)
- Dil/SDK: Dart + Flutter
- Bağımlılıklar: `app/pubspec.yaml`
- Ana uygulama kodu: `app/lib/main.dart` (+ diğer `app/lib/**`)
- iOS native bağımlılık yönetimi: CocoaPods (`app/ios/Podfile`)

3. Cloud API (runtime)
- Dil/Runtime: JavaScript (Node.js Lambda)
- Ana dosya: `scripts/aws/aac-cloud-api.js`
- AWS SDK kullanımı: DynamoDB, IoT Data Plane, IoT Control (dosya içindeki `@aws-sdk/*` importları)

4. Cloud Altyapı (IaC)
- Dil: TypeScript
- CDK proje dosyaları: `infra/cdk/package.json`, `infra/cdk/bin/aac-cloud.ts`, `infra/cdk/lib/aac-cloud-stack.ts`
- Build/deploy komutları: `infra/cdk/package.json` (`build`, `synth`, `deploy`)

5. Operasyon / Otomasyon Scriptleri
- Bash scriptler: `scripts/aws/*.sh` (smoke test, log tail, env export vb.)
- Python yardımcı scriptler (runtime değil, tooling):
  - `scripts/auto_pair_qr.py`
  - `scripts/simple_pair_qr.py`
  - `scripts/generate_pair_qr.py`
  - `monitor/filter_esp32_autoreset.py`

6. Önemli Not (Yanlış anlaşılmayı önlemek için)
- ESP32 üzerinde Python çalışmıyor; cihaz runtime'ı C++.
- Python bu projede yalnızca geliştirici araçları/yardımcı scriptler için kullanılıyor.

## 4. Yüksek Seviye Mimari

```text
[Flutter App]
   | \
   |  \--(BLE)-------------------------------+
   |                                         |
   +--(HTTP Local: /api/*, mDNS/IP)--> [ESP32 Device]
   |
   +--(HTTPS + Bearer)--> [API Gateway] --> [Cloud Services]
                                            |
                                            +--(MQTT cmd/shadow)--> [AWS IoT Core]
                                                                     |
                                                                     v
                                                                [ESP32 Device]
```

Prensip:
- Öncelik duruma göre değişir: local/BLE/AP/cloud
- Cloud açık olsa bile kritik sağlık sinyali bozuksa local fallback yapılır
- Komut yolu dinamik seçilir, tek kanala kör bağlılık yoktur

## 5. Ana Bileşenler ve Sorumluluklar

### 5.1 Flutter App

Ana modüller:
- Device orchestration: aktif cihaz seçimi, cihaz listesi
- Connectivity manager: local health, BLE hazır mı, cloud hazır mı
- Command path selector: local/BLE/AP/cloud karar ağacı
- Cloud session manager: token yenileme, auth readiness
- BLE onboarding: nonce/auth/setup/claim/provision
- Planner/UI state sync: durum poll ve kontrol ekranları

Önemli davranışlar:
- Cloud komutu başarısızsa hata tanısı çıkarılır (`HTTP`, `err`, `reason`)
- ACL/yetki tipi hatalarda otomatik ACL push recovery denenir
- MQTT hazır değilken cloud-only zorlaması bypass edilip local/ble/ap fallback yapılır

### 5.2 ESP32 Firmware

Ana modüller:
- Wi-Fi yönetimi: AP, STA, AP+STA, event tabanlı durum değişimi
- BLE yönetimi: reklam, auth penceresi, claim/provision komutları
- HTTP API: `/api/status`, `/api/cmd`, session/open vb.
- Cloud state machine: OFF, SETUP_REQUIRED, PROVISIONING, LINKED, CONNECTED, DEGRADED
- MQTT loop: subscribe/publish, delta/cmd işleme
- ACL/role enforcement: owner/user/guest yetki kontrolü
- Zaman/NTP katmanı: TLS için geçerli epoch kontrolü

Önemli davranışlar:
- `no_time` durumunda cloud DEGRADED olur, MQTT connect bloklanır
- NTP periyodik otomatik kick ile saat toparlama yapılır
- Saat geçerli olunca MQTT bağlantı tekrar dener ve CONNECTED duruma geçer

### 5.3 Cloud/Backend

Ana sorumluluklar:
- Kimliği doğrulanmış istekleri kabul etmek
- Device state ve ACL yönetimi sağlamak
- Davet (invite) ve üyelik (members) akışlarını yönetmek
- Desired/cmd akışını IoT katmanına taşımak
- Uygulama için kaynak uçları sunmak (`/me`, `/devices`, `/device/{id6}/state` ...)

## 6. Veri ve Kontrol Akışları

### 6.1 İlk Kurulum (Onboarding)

1. App BLE ile cihazı bulur
2. `GET_NONCE` + auth/setup doğrulaması
3. `CLAIM_REQUEST` ile owner atanır
4. Wi-Fi scan/provision BLE üzerinden yapılır
5. Cihaz STA IP alır, mDNS yayınlar
6. Cloud enable ile TLS/MQTT hazırlığı başlar

### 6.2 Yerel Kontrol Akışı

1. App local health check yapar
2. Local API üzerinden signed/session request gönderir
3. Firmware role/auth doğrular
4. Komut uygulanır (relay/mode/scheduler)
5. Status endpoint ile yeni state okunur

### 6.3 Cloud Kontrol Akışı

1. App cloud auth readiness kontrol eder
2. API Gateway'e desired/cmd POST eder
3. Cloud state güncellenir
4. Cihaz MQTT üzerinden komutu alır
5. Cihaz state/shadow publish eder
6. App state poll ile sonucu görür

### 6.4 ACL Senkron ve Recovery Akışı

1. App owner modunda periyodik olarak member/invite tazeler
2. Gerekli durumlarda `/acl/push` çağrılır
3. Firmware ACL dokümanını alır/uygular
4. Yetki çözümleme hataları azalır

## 7. Kimlik, Yetki ve Güvenlik

### 7.1 Kimlik Doğrulama
- Cloud: Bearer token ile yetkili API çağrıları
- Local HTTP: signed headers / session token modeli
- BLE: nonce + imza tabanlı doğrulama + owner key

### 7.2 Yetkilendirme
- Roller: OWNER, USER, GUEST, NONE
- Komut uygulama, role-based gate ile yapılır
- ACL dokümanı cloud/device arasında senkron tutulur

### 7.3 Kriptografik Malzeme
- Device certificate/key SPIFFS üzerinde
- Root CA doğrulaması
- Pair token ve invite imza doğrulamaları
- Güvenli saklama app tarafında secure storage

### 7.4 Güvenlik Notları
- Üretimde debug log seviyesi düşürülmeli
- Gizli anahtar/token loglanmamalı
- BLE pairing penceresi zaman sınırlı olmalı
- Claim/owner reset akışı auditlenmeli

## 8. Dayanıklılık ve Hata Yönetimi

### 8.1 Ağ ve Kanal Hataları
- Local DNS fail: mDNS/IP fallback
- BLE disconnect: reconnect + safe cleanup
- Cloud fail: cooldown, retry/backoff
- MQTT yok: local/BLE/AP fallback

### 8.2 Zaman/NTP Hataları
- `isTimeValid()` gate ile TLS korunur
- `no_time` durumunda periyodik NTP retry
- Saat gelince otomatik cloud recovery

### 8.3 Komut Güvenilirliği
- Dedup (aynı komut kısa pencerede tekrar gönderilmez)
- Path seçimi sırasında health sinyalleri değerlendirilir
- Cloud komut hata diagnostikleri kullanıcıya maplenir

## 9. Gözlemlenebilirlik (Observability)

Log etiketleri:
- Firmware: `[CLOUD]`, `[MQTT]`, `[AUTH][HTTP]`, `[BLE]`, `[WiFi]`, `[NTP]`
- App: `[PATH]`, `[CLOUD][HTTP]`, `[CLOUD][STATE]`, `[API SEND]`, `[PLANNER]`

Önerilen metrikler:
- MQTT connected ratio
- no_time görülme oranı
- command success ratio (by path)
- BLE onboarding success/fail ratio
- ACL recovery success ratio

## 10. Dağıtım ve Operasyon

### 10.1 Firmware Release
- PlatformIO environment bazlı build
- OTA veya seri port dağıtım
- Versiyon + schema uyumluluk kontrolü

### 10.2 App Release
- Flutter build pipeline
- iOS signing/provisioning
- Cloud feature flags ile kontrollü rollout

### 10.3 Backend Release
- CDK ile altyapı değişiklikleri
- Route/ACL backward compatibility
- Smoke test ve rollback planı

## 11. Performans ve Ölçeklenebilirlik

### 11.1 Cihaz
- Loop bloklamayan tasarım (non-blocking eğilimi)
- Backoff ile ağ yükü kontrolü
- Sensör/publish frekans dengesi

### 11.2 App
- Poll interval adaptasyonu
- Komut dedup ile gereksiz trafik azaltımı
- Çoklu kanal fallback ile kullanıcı algı performansı

### 11.3 Cloud
- API endpoint başına timeout ve retry stratejisi
- MQTT topic ayrımı (cmd/state/shadow/jobs)
- ACL ve state operasyonlarının idempotent tasarımı

## 12. Kritik Senaryolar ve Beklenen Davranış

1. Cihaz internete bağlı ama saat yok (`no_time`)
- Beklenen: App local fallback ile kontrol etmeye devam eder
- Beklenen: Firmware NTP retry ile kendini toparlar, sonra MQTT CONNECTED

2. App silinip yeniden kuruldu
- Beklenen: local secure storage sıfırlanır
- Beklenen: QR/BLE onboarding ile token/owner context yeniden kurulur
- Beklenen: cloud-only kilidine düşmeden fallback çalışır

3. ACL/role mismatch
- Beklenen: Cloud komutlarında yetki hatası görünür olur
- Beklenen: Owner için otomatik ACL recovery tetiklenir

4. BLE dalgalanması
- Beklenen: session cleanup + reconnect; kritik akışlarda fallback AP/local

## 13. Dokümanlar Arası Bağlantı (Source of Truth)

- API rotaları: `docs/api/routes.md`
- AWS kurulum paketi: `docs/cloud/aws_cloud_api_setup_pack.md`
- AWS runbook: `docs/cloud/release_runbook.md`
- Cloud smoke test: `docs/cloud/smoke_test.md`
- Konfigürasyon akışı: `docs/deploy/how-config-flows.md`
- DDB şema: `docs/data/ddb-schema.md`
- ESP32 güvenlik: `docs/esp32_secure_boot.md`

## 14. Açık Riskler ve İyileştirme Planı

Kısa vadeli:
- App tarafında cloud readiness kararına `stateReason` tabanlı ek filtre
- Firmware NTP kaynakları için bölgesel fallback havuzu
- Local/cloud command reconciliation için daha güçlü conflict çözümü

Orta vadeli:
- Structured logging + merkezi log toplayıcı
- Telemetry dashboard ve SLO tanımı
- Daha granüler ACL diff/merge mekanizması

Uzun vadeli:
- Çoklu cihaz/çoklu kullanıcı tenancy modeli iyileştirmesi
- Policy-as-code yaklaşımı ile izin yönetimi
- Formal threat modeling ve güvenlik test otomasyonu

## 15. Sonuç

ArtAirCleaner mimarisi, yerel düşük gecikmeli kontrol ile cloud üzerinden uzaktan yönetimi birlikte sunan hibrit bir IoT mimarisidir. Sistem, owner/ACL güvenlik modeli, çok kanallı komut iletimi (local/BLE/AP/cloud), otomatik fallback stratejileri ve cloud/NTP toparlanma mekanizmaları sayesinde gerçek dünya ağ koşullarında çalışabilirlik hedefler.

Bu doküman, proje sunumlarında ve teknik onboard süreçlerinde ana referans olarak kullanılmalıdır.
