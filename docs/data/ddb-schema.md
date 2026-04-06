# DynamoDB Schema

## aac_device_ownership
- **PK**: deviceId (string)
- **Attributes**:
  - ownerUserId (string)
  - ownerUserIdHash (string, optional)
  - status (string: active/deleted)
  - claimedAt (number, epoch ms)
  - claimSecretHash (string, sha256)
    - Öneri: `sha256(pairToken)` değeri (pairToken düz metni asla cloud'a yazılmaz)
  - deviceBrand (string, optional)
  - deviceSuffix (string, optional)
  - deviceDisplayName (string, optional)
  - deletedAt (number, epoch ms, optional)
- **GSI**: byOwnerUserId
  - PK: ownerUserId
  - SK: deviceId

## aac_device_state (optional)
- **PK**: deviceId (string)
- **Attributes**:
  - state (map/json)
  - updatedAt (number, epoch ms)
  - source (string: telemetry/shadow)

## aac_user_devices (optional)
- **PK**: userId (string)
- **SK**: deviceId (string)
- **Attributes**:
  - role (string: OWNER/USER/GUEST)
  - status (string: active/revoked/deleted/pending/accepted)
  - claimedAt (number, epoch ms, owner için)
  - invitedAt (number, epoch ms, optional)
  - acceptedAt (number, epoch ms, optional)
  - invitedBy (string, optional)
  - inviteId (string, optional)
  - userIdHash (string, optional)
  - revokedAt (number, epoch ms, optional)
  - revokedBy (string, optional)
  - updatedAt (number, epoch ms)
- **GSI**: byDeviceId
  - PK: deviceId
  - SK: userId

## aac_device_invites
- **PK**: inviteId (string)
- **Attributes**:
  - deviceId (string)
  - role (string: USER/GUEST)
  - status (string: pending/accepted/revoked/deleted)
  - inviterUserId (string)
  - inviterUserIdHash (string, optional)
  - inviterEmail (string, optional)
  - inviteToken (string, optional, signed short-lived token)
  - userIdHash (string, optional, local ACL eşleme için)
  - createdAt (number, epoch ms)
  - updatedAt (number, epoch ms)
  - acceptedAt (number, epoch ms, optional)
  - acceptedBy (string, optional)
  - revokedAt (number, epoch ms, optional)
  - revokedBy (string, optional)
  - validUntil (number, epoch seconds, optional)
  - expiresAt (number, epoch seconds, TTL)
- **GSI**: byDeviceId
  - PK: deviceId
  - SK: createdAt

## aac_integration_links
- **PK**: integrationId (string)
- **SK**: deviceId (string)
- **Attributes**:
  - status (string: active/revoked/deleted)
  - scopes (list: `device:read`, `device:write`, `device:admin`)
  - grantedBy (string)
  - createdAt (number, epoch ms)
  - updatedAt (number, epoch ms)
  - expiresAt (number, epoch seconds, TTL, optional)
- **GSI**: byDeviceId
  - PK: deviceId
  - SK: integrationId

## aac_cmd_idempotency
- **PK**: cmdKey (string, `${deviceId}#${cmdId}`)
- **Attributes**:
  - deviceId (string)
  - cmdId (string)
  - userSub (string)
  - createdAt (number, epoch ms)
  - expiresAt (number, epoch seconds, TTL)

## aac_rate_limit
- **PK**: rateKey (string)
- **Attributes**:
  - windowStartSec (number)
  - requestCount (number)
  - userSub (string)
  - deviceId (string)
  - updatedAt (number, epoch ms)
  - expiresAt (number, epoch seconds, TTL)

## aac_audit
- **PK**: auditId (string)
- **Attributes**:
  - eventType (string)
  - createdAt (number, epoch ms)
  - expiresAt (number, epoch seconds, TTL)
  - details... (claim, invite, revoke, acl push, recovery olayları)
