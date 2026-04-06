# API Routes

Base: API Gateway HTTP API (JWT authorizer with Cognito User Pool).

Runtime Lambda: `scripts/aws/aac-cloud-api.js`

## Public (auth not required)

| Method | Path | Notes |
| --- | --- | --- |
| GET | /health | Service health and config presence summary. |
| GET | /healthz | Alias of `/health`. |

## Auth required (Cognito JWT)

| Method | Path | Notes |
| --- | --- | --- |
| GET | /me | Current user + cloud state/features. |
| GET | /devices | User device list + cloud metadata. |
| POST | /device/{id6}/claim-proof/sync | Sync claim proof hash to ownership row. |
| POST | /device/{id6}/claim | Owner claim or invite accept (`inviteId`). |
| POST | /device/{id6}/unclaim | Owner unclaim + revoke members/invites. |
| GET | /device/{id6}/capabilities | Versioned capabilities schema for integrations. |
| GET | /device/{id6}/ha/config | Home Assistant discovery config topic/payload list. |
| GET | /device/{id6}/state | Device state (shadow reported preferred, DDB fallback). |
| POST | /device/{id6}/desired | Update IoT Shadow desired state. |
| POST | /device/{id6}/cmd | Publish command (`aac/{id6}/cmd`). |
| GET | /device/{id6}/members | Owner-only member list. |
| POST | /device/{id6}/member/{userSub}/revoke | Owner-only member revoke. |
| POST | /device/{id6}/invite | Owner-only invite create. |
| GET | /device/{id6}/invites | Owner-only invite list. |
| POST | /device/{id6}/invite/{inviteId}/revoke | Owner-only invite revoke. |
| POST | /device/{id6}/acl/push | Owner-only ACL snapshot'ını device shadow desired alanına iter. |
| POST | /device/{id6}/integration/link | Owner-only integration link oluşturur. |
| GET | /device/{id6}/integrations | Owner-only integration link listesi. |
| POST | /device/{id6}/integration/{integrationId}/revoke | Owner-only integration revoke. |

## Paylaşım modeli

- `POST /device/{id6}/claim` iki iş yapar:
  - Owner ilk sahiplenme / tekrar claim
  - Davet kabulü (`inviteId` + `inviteToken`)
- Cloud yetkisi doğrudan MQTT topic izni vermek yerine uygulama API'si üzerinden çözümlenir.
- Device tarafına etkin kullanıcı listesi `desired.acl` olarak push edilir; cihaz reconnect olduğunda shadow delta ile tekrar senkron olur.
- Member revoke sırasında iki kanal birlikte kullanılır:
  - Anlık etki için MQTT `REVOKE_USER`
  - Cihaz o anda offline ise eventual consistency için `desired.acl`

## Feature-gated routes

- `FEATURE_INVITES=0`: invite routes return `404 not_found`.
- `FEATURE_SHADOW_DESIRED=0`: `/device/{id6}/desired` returns `404 not_found`.
- `FEATURE_SHADOW_STATE=0`: `/device/{id6}/state` skips shadow and uses DDB path.

## Security controls

- JWT auth via API Gateway authorizer (required except health).
- Membership/ownership checks per device on protected routes.
- Optional claim proof enforcement (`FEATURE_CLAIM_PROOF`, `CLAIM_PROOF_REQUIRED`).
- Command idempotency (`FEATURE_IDEMPOTENCY`) with TTL table.
- Command rate limiting (`FEATURE_RATE_LIMIT`) with `429` and rate headers.
