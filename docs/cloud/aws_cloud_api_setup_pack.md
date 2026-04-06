# AWS Cloud API Setup Pack (Dev)

Bu paket, `scripts/aws/aac-cloud-api.js` için hızlı başlangıç materyalini içerir:

- Env şablonu: `scripts/aws/templates/aac-cloud-api.dev.env.example`
- IAM policy şablonu: `scripts/aws/templates/aac-cloud-api.iam.policy.json`

## 1) Env değerlerini doldur

Önce şablonu kopyala ve gerçek değerlerle doldur:

```bash
cp scripts/aws/templates/aac-cloud-api.dev.env.example /tmp/aac-cloud-api.dev.env
```

Notlar:
- `INVITE_TOKEN_SECRET` en az 16 karakter olmalı.
- `IOT_ENDPOINT` mutlaka `*-ats.iot.<region>.amazonaws.com` endpoint’i olmalı.
- Tablolar/GSI isimleri mevcut DDB kaynaklarınla birebir eşleşmeli.

## 2) IAM policy’yi özelleştir

Policy şablonundaki:
- region (`eu-central-1`)
- account (`123456789012`)
- table adları (`aac-dev-*`)

alanlarını kendi ortamına göre güncelle.

## 3) Policy’yi role’a bağla

```bash
aws iam create-policy \
  --policy-name aac-dev-cloud-api-policy \
  --policy-document file://scripts/aws/templates/aac-cloud-api.iam.policy.json

aws iam attach-role-policy \
  --role-name aac-dev-cloud-api-role \
  --policy-arn arn:aws:iam::123456789012:policy/aac-dev-cloud-api-policy
```

## 4) Lambda env’i güncelle

En güvenli yol: Console veya IaC (CDK).
CLI ile tek satır `Variables={...}` göndermek hata riski yüksek olduğu için önerilmez.

## 5) API route kontrolü

Yeni route’ların API Gateway’de tanımlı olduğundan emin ol:

- `POST /device/{id6}/acl/push`
- `POST /device/{id6}/integration/link`
- `GET /device/{id6}/integrations`
- `POST /device/{id6}/integration/{integrationId}/revoke`

## 6) Smoke test

```bash
./scripts/aws/run-cloud-smoke.sh
```

Manuel ek test:
- Owner token ile `POST /device/{id6}/acl/push` => `ok: true`, `pushed: true`
