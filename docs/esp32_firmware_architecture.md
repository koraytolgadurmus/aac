# ArtAirCleaner ESP32 Gömülü Yazılım Mimarisi

- Doküman türü: Firmware mimari dokümanı
- Kapsam: ESP32 cihaz yazılımı (C++/Arduino/PlatformIO)
- Son güncelleme: 2026-02-20
- Hedef kitle: Firmware geliştiriciler, test mühendisleri, teknik paydaşlar

## 1. Amaç ve Kapsam

Bu doküman yalnızca ESP32 üzerindeki gömülü yazılım mimarisini açıklar.

Temel amaçlar:
- Cihazın sensör/aktüatör kontrolünü güvenilir şekilde yürütmek
- BLE + Wi-Fi provisioning ile ilk kurulum akışını desteklemek
- Yerel HTTP API ve cloud MQTT katmanını birlikte yönetmek
- Owner/User yetkilendirmesi ve güvenlik kontrollerini uygulamak
- Ağ/saat (NTP) problemlerinde otomatik toparlanma sağlamak

Kapsam dışı:
- Mobil uygulama UI/UX detayları
- AWS backend servis iç mimarisinin tüm detayları

## 2. Teknoloji Yığını (Firmware)

- Dil: C++
- Framework: Arduino (ESP32)
- Build sistemi: PlatformIO (`platformio.ini`)
- Hedef kart: `esp32dev` (Espressif32 platformu)
- BLE: NimBLE-Arduino
- JSON: ArduinoJson
- MQTT: PubSubClient (TLS ile)
- Sensör kütüphaneleri: BSEC2, BME68x, SEN5x
- Kalıcı depolama: Preferences (NVS), SPIFFS

Not:
- ESP32 runtime tarafında Python kullanılmaz.
- Python sadece geliştirici yardımcı scriptlerinde kullanılır (QR/tooling).

## 3. Firmware Katmanları

1. Donanım ve Sürücü Katmanı
- I2C başlatma, sensör driver init/okuma
- Röle ve GPIO kontrolü

2. Ağ ve Bağlantı Katmanı
- Wi-Fi AP/STA/AP+STA yönetimi
- mDNS yayını
- BLE advertising, bağlantı, komut/notify akışı

3. Protokol ve API Katmanı
- Yerel HTTP endpoint’leri (`/api/status`, `/api/cmd`, `/api/session/open`, vb.)
- BLE komut protokolü (`GET_NONCE`, `AUTH`, `scan_wifi`, provisioning komutları)
- MQTT topic abonelik/yayın (`cmd`, `state`, `shadow`, `jobs`)

4. İş Mantığı Katmanı
- Owner claim ve ACL rol çözümleme
- Komut doğrulama ve uygulama
- Cloud state machine yönetimi

5. Dayanıklılık ve Güvenlik Katmanı
- NTP geçerlilik kontrolü (`no_time` koruması)
- TLS hazır olma kontrolleri
- Retry/backoff, fallback ve self-healing akışları

## 4. Ana Modüller ve Sorumluluklar

### 4.1 Boot ve Başlatma
- Cihaz kimliğini (ID6/ID12) yükler
- NVS/SPIFFS’den credential ve config okur
- Sensör ve haberleşme modüllerini başlatır
- AP’yi açar, mümkünse STA bağlantı denemesi yapar

### 4.2 Wi-Fi Yöneticisi
- AP modunu onboarding için her zaman hazır tutar
- Kayıtlı SSID varsa STA bağlantısını dener
- AP grace window ve coexistence davranışını yönetir
- Wi-Fi event kodlarından state günceller

### 4.3 BLE Yöneticisi
- Cihaz advertises eder (`ArtAirCleaner_BT_<id6>`)
- Auth/pairing penceresini ve nonce akışını yönetir
- BLE üzerinden Wi-Fi scan/provisioning komutlarını işler
- Policy’ye göre BLE shutdown/restart yapar

### 4.4 Yerel HTTP API
- İmzalı header veya session token ile erişim denetler
- `status`, `cmd`, session/open ve provisioning related endpoint’leri sunar
- Role-based komut filtresi uygular (OWNER/USER/GUEST/NONE)

### 4.5 Cloud/MQTT Yöneticisi
- TLS materyalini doğrular (rootCA, deviceCert, deviceKey)
- MQTT bağlantısını kurar ve topic aboneliklerini yönetir
- Shadow delta/cmd mesajlarını parse eder, komuta çevirir
- State/shadow publish ile cihaz durumunu senkronlar

### 4.6 Zaman ve NTP Yöneticisi
- TLS/MQTT öncesi saat geçerliliğini denetler
- `no_time` durumunda cloud’u DEGRADED’e alır
- Periyodik NTP retry ile otomatik toparlanma sağlar

## 5. Durum Makineleri

### 5.1 Cloud Durum Makinesi
- `OFF`
- `SETUP_REQUIRED`
- `LINKED`
- `CONNECTED`
- `DEGRADED` (ör. `no_time`)

Geçiş örnekleri:
- TLS hazır -> `LINKED`
- MQTT bağlantı başarılı -> `CONNECTED`
- Saat geçersiz -> `DEGRADED (no_time)`

### 5.2 Ownership/Auth Durumu
- Unowned -> Owned (CLAIM_REQUEST ile)
- HTTP/BLE istekleri role ve auth durumuna göre kabul/red edilir

### 5.3 Wi-Fi Durumu
- AP up
- STA connecting/connected/disconnected
- AP+STA geçişleri scan/provisioning ihtiyacına göre

## 6. Veri ve Komut Akışı

### 6.1 BLE Onboarding
1. `GET_NONCE`
2. `AUTH` / `AUTH_SETUP`
3. `CLAIM_REQUEST` (owner atanması)
4. `scan_wifi` + provisioning payload
5. STA bağlantı + IP + mDNS

### 6.2 Yerel Komut Uygulama
1. Auth kontrolü (signed header/session)
2. JSON parse
3. Role kontrolü
4. Röle/switch/mode güncelleme
5. Status publish/yanıt

### 6.3 Cloud Komut Uygulama
1. MQTT cmd/shadow delta alınır
2. ACL/role çözümleme yapılır
3. Yetkiliyse komut uygulanır
4. Güncel state/shadow publish edilir

## 7. Güvenlik Mimarisi

- BLE nonce + imza doğrulaması
- Owner claim ile cihaz sahipliği sabitlenmesi
- Local HTTP signed header veya kısa ömürlü session token
- ACL tabanlı rol çözümleme ve komut kapıları
- TLS sertifika/anahtar doğrulamaları
- Log seviyesinde gizli veri maskeleme gereksinimi

## 8. Dayanıklılık ve Self-Healing

- NTP yoksa cloud komut yolu bloke edilip local akış korunur
- MQTT reconnect/retry ve backoff uygulanır
- Wi-Fi event tabanlı otomatik toparlanma
- BLE kopmalarında yeniden reklam ve reconnect stratejisi
- Geçici ağ problemlerinde AP fallback erişimi

## 9. Gözlemlenebilirlik

Öne çıkan firmware log etiketleri:
- `[BOOT]`, `[WiFi]`, `[BLE]`, `[AUTH][HTTP]`, `[CLOUD]`, `[MQTT]`, `[NTP]`, `[CMD]`

Önerilen metrikler:
- MQTT connection uptime oranı
- `no_time` oluşma/sürme süresi
- Komut başarı oranı (local vs cloud)
- BLE onboarding başarı oranı
- ACL role mismatch oranı

## 10. Build, Test ve Release

- Build: `pio run -e esp32dev`
- Flash: `pio run -e esp32dev -t upload`
- Monitor: `pio device monitor -e esp32dev`
- Kritik doğrulamalar:
  - Boot logları
  - Wi-Fi AP/STA geçişi
  - BLE auth + scan/provisioning
  - Local HTTP komutları
  - Cloud enable + MQTT connected akışı

## 11. Bilinen Riskler ve İyileştirme Alanları

Kısa vadeli:
- NTP kaynakları için çoklu fallback havuzu
- MQTT/ACL mismatch için daha görünür teşhis kodları
- Komut conflict çözümünü güçlendirme

Orta vadeli:
- Structured logging formatı
- Daha güçlü watchdog/self-test akışı
- Offline komut kuyruğu ve reconcile stratejisi

## 12. Sonuç

ESP32 firmware, ArtAirCleaner sisteminin gerçek zamanlı kontrol çekirdeğidir. Mimari; güvenlik (owner/ACL), çoklu iletişim kanalı (BLE/HTTP/MQTT), ve otomatik toparlanma (NTP/Wi-Fi/MQTT) ilkeleri üzerine kuruludur. Bu yapı, gerçek ağ koşullarında dahi cihazın erişilebilir ve kontrol edilebilir kalmasını hedefler.
