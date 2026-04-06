# Device Sharing Architecture

Bu doküman owner-local erişimden, cloud tabanlı çok kullanıcılı cihaz paylaşım modeline geçişi özetler.

## 1. Büyük üreticiler bunu nasıl yapıyor?

Temel prensip şudur:

- Cihazın gerçek sahibi cloud tarafında tek bir `owner` olarak tutulur.
- Diğer kullanıcılar doğrudan cihaza değil, cloud tarafındaki üyelik kaydına bağlanır.
- Mobil uygulama önce cloud'dan "bu kullanıcı bu cihazda hangi role sahip?" sorusunun cevabını alır.
- MQTT veya shadow komutları bu role göre üretilir.
- Cihaz üstünde ikinci bir yerel ACL kopyası tutulur; cihaz offline kalsa bile son yetki durumu korunur.

Bu modelde cihaz sertifikası veya MQTT topic erişimi son kullanıcı başına dağıtılmaz. Büyük üreticiler genelde:

- App user auth: Cognito/OIDC benzeri kullanıcı kimliği
- Device auth: X.509 cihaz sertifikası
- Access control: Cloud membership tablosu
- Device sync: Shadow/desired ACL snapshot
- Invite flow: Kısa ömürlü imzalı davet

kullanır.

## 2. Bu repoda mevcut olan yapı

Kod tabanında çekirdek paylaşım mimarisi zaten mevcut:

- Ownership kaydı: `aac_device_ownership`
- Kullanıcı-cihaz üyeliği: `aac_user_devices`
- Davet kaydı: `aac_device_invites`
- ACL shadow sync: `POST /device/{id6}/acl/push`
- Davet üretme: `POST /device/{id6}/invite`
- Davet kabul etme: `POST /device/{id6}/claim` içinde `inviteId`
- Üye iptali: `POST /device/{id6}/member/{userSub}/revoke`
- Offline revoke toparlama: shadow `desired.acl`

Yani mimari owner-only modelden çıkmış durumda; paylaşım için ana yapı taşları kurulmuş.

## 3. Önerilen üretim modeli

### 3.1 Roller

- `OWNER`: cihazı yönetir, paylaşır, revoke eder, unclaim yapar
- `USER`: cihazı kontrol eder
- `GUEST`: sınırlı okuma veya sınırlı komut

Not:
- `ADMIN` gibi ek roller eklenebilir ama ilk üretim sürümünde gerekli değilse açmamak daha doğru.

### 3.2 Kontrol katmanı

Yetki değerlendirmesi iki kademeli olmalı:

1. Cloud authoritative ACL
- API çağrısında kullanıcı üyeliği kontrol edilir.

2. Device cached ACL
- Cloud `desired.acl` push eder.
- Firmware bunu local cache olarak uygular.

Bu yaklaşım hem güvenli hem dayanıklıdır.

## 4. Kurulması gereken ürün akışı

### 4.1 Owner cihazı claim eder

- Kullanıcı login olur
- Pair/claim proof ile `POST /device/{id6}/claim`
- Ownership kaydı oluşur
- `aac_user_devices` içine owner link'i yazılır

### 4.2 Owner davet üretir

- `POST /device/{id6}/invite`
- Role + TTL seçilir
- Kısa ömürlü `inviteToken` üretilir
- App bunu QR, deeplink veya paylaşım linki olarak sunar

### 4.3 Davetli kullanıcı kabul eder

- Kullanıcı login olur
- `inviteId` + `inviteToken` ile `POST /device/{id6}/claim`
- Cloud `aac_user_devices` kaydını açar
- Sonra `acl/push` ile cihaz ACL senkronlanır

### 4.4 Revoke

- Owner user veya guest üyeliğini siler
- Cloud üyeliği `revoked` yapar
- MQTT ile anlık `REVOKE_USER` yollar
- Shadow `desired.acl` ile offline cihazlar sonra toparlar

## 5. Sıradaki eksikler

Üretim seviyesine geçmek için bundan sonra odak şu başlıklarda olmalı:

1. Mobil uygulama paylaşım ekranı
- Invite üretme
- Invite listesi
- Member listesi
- Revoke akışı

2. Invite taşıma biçimi
- QR
- Universal link / deep link
- Kopyalanabilir kısa kod

3. Audit görünürlüğü
- Kim kimi ne zaman invite etti
- Kim kabul etti
- Kim revoke etti

4. Policy netliği
- `USER` hangi komutları atabilir?
- `GUEST` sadece okur mu, yoksa power/light gibi sınırlı kontrol alır mı?

5. Owner recovery UX
- Fiziksel erişim + claim proof ile sahiplik devri

## 6. Kritik mimari kararı

En önemli nokta:

Son kullanıcıya ayrı MQTT kullanıcı adı/şifre dağıtma.

Büyük üreticiler çoğunlukla bunu yapmaz. Çünkü:

- topic ACL yönetimi karmaşıklaşır
- revoke işlemi zorlaşır
- cihaz değil kullanıcı kanalını güvenceye almak gerekir
- mobil istemciye fazla IoT yetkisi verilmiş olur

Daha doğru model:

- Kullanıcı -> Cloud API
- Cloud API -> IoT Core / Shadow / MQTT publish
- Device -> kendi sertifikası ile MQTT

Yani "paylaşım" kullanıcıya MQTT broker erişimi vermek değil, cloud membership vermektir.
