# Cognito Redirect Mismatch Fix (ArtAirCleaner)

Bu projede Flutter AppAuth için kullanılan redirect URI:

- iOS + Android: `com.koray.artaircleaner://callback`

Opsiyonel migration fallback (yalnızca gerekirse):

- `com.example.artaircleaner://callback`

## AWS Console ayarı (zorunlu)

1. AWS Console -> Cognito -> User pools -> ilgili pool -> App integration -> App client
2. `Allowed callback URLs` alanına şu URL'yi ekleyin:
   - `com.koray.artaircleaner://callback`
   - Not: Eski uygulama migration gerekiyorsa geçici olarak `com.example.artaircleaner://callback` da eklenebilir.
3. `Allowed sign-out URLs` için en az şunu ekleyin:
   - `com.koray.artaircleaner://callback`
4. OAuth 2.0 grant türlerinde `Authorization code grant` açık olmalı.
5. Scopes içinde en az `openid`, `email`, `profile` olmalı.

## App tarafı env değerleri

Flutter build sırasında şu değerleri verin:

- `COGNITO_HOSTED_DOMAIN` (örn. `https://aac-dev.auth.eu-central-1.amazoncognito.com`)
- `COGNITO_CLIENT_ID`
- `COGNITO_USER_POOL_ID`
- `COGNITO_REGION`

Opsiyonel:

- `COGNITO_REDIRECT_URI_IOS`
- `COGNITO_REDIRECT_URI_ANDROID`
- `COGNITO_REDIRECT_URI_ANDROID_LEGACY`
  - Varsayılan olarak boş bırakılır. Sadece eski sürüm migration için kullanın.

## Hızlı doğrulama

- Cloud login ekranından giriş başlat.
- Browser hata verirse URL'deki `redirect_uri` parametresini kontrol et.
- Bu değer Cognito App Client callback listesinde birebir olmalı.
