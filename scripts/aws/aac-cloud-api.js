// Lambda: aac-cloud-api (Node.js 18.x)
// Handles:
// - POST /device/{id6}/claim
// - GET  /device/{id6}/state
// - POST /device/{id6}/cmd

const crypto = require('crypto');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const {
  DynamoDBDocumentClient,
  GetCommand,
  QueryCommand,
  PutCommand,
  UpdateCommand,
  ScanCommand,
} = require('@aws-sdk/lib-dynamodb');
const {
  IoTDataPlaneClient,
  PublishCommand,
  GetThingShadowCommand,
  UpdateThingShadowCommand,
} = require('@aws-sdk/client-iot-data-plane');
const {
  IoTClient,
  CreateJobCommand,
  DescribeThingCommand,
} = require('@aws-sdk/client-iot');
const {
  S3Client,
  GetObjectCommand,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');

const OWNERSHIP_TABLE =
  process.env.OWNERSHIP_TABLE ??
  process.env.DEVICES_TABLE ??
  process.env.MEMBERS_TABLE ??
  process.env.DDB_DEVICE_OWNERSHIP_TABLE ??
  process.env.DDBDEVICEOWNERSHIPTABLE ??
  null;
const STATE_TABLE =
  process.env.STATE_TABLE ??
  process.env.DDB_DEVICE_STATE_TABLE ??
  process.env.DDBDEVICESTATETABLE ??
  null;
const USER_DEVICES_TABLE =
  process.env.USER_DEVICES_TABLE ??
  process.env.DDB_USER_DEVICES_TABLE ??
  process.env.DDBUSERDEVICESTABLE ??
  null;
const INVITES_TABLE =
  process.env.INVITES_TABLE ??
  process.env.DDB_DEVICE_INVITES_TABLE ??
  process.env.DDBDEVICEINVITESTABLE ??
  null;
const INTEGRATION_LINKS_TABLE =
  process.env.INTEGRATION_LINKS_TABLE ??
  process.env.DDB_INTEGRATION_LINKS_TABLE ??
  process.env.DDBINTEGRATIONLINKSTABLE ??
  null;
const OWNERSHIP_BY_OWNER_GSI =
  process.env.OWNERSHIP_BY_OWNER_GSI ??
  process.env.DDB_DEVICE_OWNERSHIP_BY_OWNER_GSI ??
  process.env.DDBDEVICEOWNERSHIPBYOWNERGSI ??
  'byOwnerUserId';
const USER_DEVICES_BY_DEVICE_GSI =
  process.env.USER_DEVICES_BY_DEVICE_GSI ??
  process.env.DDB_USER_DEVICES_BY_DEVICE_GSI ??
  process.env.DDBUSERDEVICESBYDEVICEGSI ??
  'byDeviceId';
const INVITES_BY_DEVICE_GSI =
  process.env.INVITES_BY_DEVICE_GSI ??
  process.env.DDB_DEVICE_INVITES_BY_DEVICE_GSI ??
  process.env.DDBDEVICEINVITESBYDEVICEGSI ??
  'byDeviceId';
const INTEGRATION_LINKS_BY_DEVICE_GSI =
  process.env.INTEGRATION_LINKS_BY_DEVICE_GSI ??
  process.env.DDB_INTEGRATION_LINKS_BY_DEVICE_GSI ??
  process.env.DDBINTEGRATIONLINKSBYDEVICEGSI ??
  'byDeviceId';
const IOT_ENDPOINT =
  process.env.IOT_ENDPOINT ??
  process.env.IOT_DATA_ENDPOINT ??
  process.env.CLOUD_IOT_ENDPOINT ??
  null;
const CLAIM_PROOF_REQUIRED =
  (process.env.CLAIM_PROOF_REQUIRED || '1').toString().toLowerCase() !== '0';
const CMD_IDEMPOTENCY_TABLE =
  process.env.CMD_IDEMPOTENCY_TABLE ??
  process.env.DDB_CMD_IDEMPOTENCY_TABLE ??
  process.env.DDBCMDIDEMPOTENCYTABLE ??
  null;
const AUDIT_TABLE =
  process.env.AUDIT_TABLE ??
  process.env.DDB_AUDIT_TABLE ??
  process.env.DDBAUDITTABLE ??
  null;
const RATE_LIMIT_TABLE =
  process.env.RATE_LIMIT_TABLE ??
  process.env.DDB_RATE_LIMIT_TABLE ??
  process.env.DDBRATELIMITTABLE ??
  null;
const IDEMPOTENCY_TTL_SEC = Math.max(
  60,
  Number(process.env.CMD_IDEMPOTENCY_TTL_SEC || 300),
);
const AUDIT_TTL_SEC = Math.max(
  3600,
  Number(process.env.AUDIT_TTL_SEC || 30 * 24 * 3600),
);
const CMD_RATE_LIMIT_WINDOW_SEC = Math.max(
  1,
  Number(process.env.CMD_RATE_LIMIT_WINDOW_SEC || 10),
);
const CMD_RATE_LIMIT_MAX = Math.max(
  1,
  Number(process.env.CMD_RATE_LIMIT_MAX || 20),
);
const CLAIM_PROOF_SYNC_RATE_LIMIT_WINDOW_SEC = Math.max(
  1,
  Number(process.env.CLAIM_PROOF_SYNC_RATE_LIMIT_WINDOW_SEC || 60),
);
const CLAIM_PROOF_SYNC_RATE_LIMIT_MAX = Math.max(
  1,
  Number(process.env.CLAIM_PROOF_SYNC_RATE_LIMIT_MAX || 6),
);
const FEATURE_INVITES =
  (process.env.FEATURE_INVITES || '1').toString().toLowerCase() !== '0';
const FEATURE_RATE_LIMIT =
  (process.env.FEATURE_RATE_LIMIT || '1').toString().toLowerCase() !== '0';
const FEATURE_IDEMPOTENCY =
  (process.env.FEATURE_IDEMPOTENCY || '1').toString().toLowerCase() !== '0';
const FEATURE_CLAIM_PROOF =
  (process.env.FEATURE_CLAIM_PROOF || '1').toString().toLowerCase() !== '0';
const FEATURE_CLAIM_AUTO_BOOTSTRAP =
  (process.env.FEATURE_CLAIM_AUTO_BOOTSTRAP || '1').toString().toLowerCase() !== '0';
const FEATURE_SHADOW_STATE =
  (process.env.FEATURE_SHADOW_STATE || '1').toString().toLowerCase() !== '0';
const FEATURE_SHADOW_DESIRED =
  (process.env.FEATURE_SHADOW_DESIRED || '1').toString().toLowerCase() !== '0';
// When enabled, the cloud will push `desired.acl` to the device shadow so that
// membership revokes made while the device is offline are eventually enforced
// after it reconnects (via shadow delta).
const FEATURE_SHADOW_ACL_SYNC =
  (process.env.FEATURE_SHADOW_ACL_SYNC || '1').toString().toLowerCase() !== '0';
const FEATURE_OTA_JOBS =
  (process.env.FEATURE_OTA_JOBS || '1').toString().toLowerCase() !== '0';
const THING_NAME_PREFIX =
  process.env.THING_NAME_PREFIX ??
  process.env.IOT_THING_NAME_PREFIX ??
  'aac-';
const IOT_THING_ARN_PREFIX =
  process.env.IOT_THING_ARN_PREFIX ??
  process.env.AWS_IOT_THING_ARN_PREFIX ??
  null;
const OTA_JOB_TARGET_SELECTION =
  (process.env.OTA_JOB_TARGET_SELECTION || 'SNAPSHOT').toString().trim().toUpperCase() === 'CONTINUOUS'
    ? 'CONTINUOUS'
    : 'SNAPSHOT';
const INVITE_TOKEN_SECRET = String(process.env.INVITE_TOKEN_SECRET || '').trim();
const FEATURE_SIGNED_INVITES =
  (process.env.FEATURE_SIGNED_INVITES || '1').toString().toLowerCase() !== '0' &&
  INVITE_TOKEN_SECRET.length >= 16;
const INTEGRATION_SCOPE_READ = 'device:read';
const INTEGRATION_SCOPE_WRITE = 'device:write';
const INTEGRATION_SCOPE_ADMIN = 'device:admin';
const INVITE_TTL_SEC_FIXED = 10 * 60;
const INVITE_RECORD_RETENTION_SEC = 24 * 3600;

const ddbClient = new DynamoDBClient({});
const ddbDoc = DynamoDBDocumentClient.from(ddbClient, {
  marshallOptions: {
    removeUndefinedValues: true,
  },
});

function wrapPromise(sendFn) {
  return {
    promise: () => sendFn(),
  };
}

const ddb = {
  get: (params) => wrapPromise(() => ddbDoc.send(new GetCommand(params))),
  query: (params) => wrapPromise(() => ddbDoc.send(new QueryCommand(params))),
  put: (params) => wrapPromise(() => ddbDoc.send(new PutCommand(params))),
  update: (params) => wrapPromise(() => ddbDoc.send(new UpdateCommand(params))),
  scan: (params) => wrapPromise(() => ddbDoc.send(new ScanCommand(params))),
};

const iotDataEndpoint = IOT_ENDPOINT
  ? (IOT_ENDPOINT.startsWith('http://') || IOT_ENDPOINT.startsWith('https://')
    ? IOT_ENDPOINT
    : `https://${IOT_ENDPOINT}`)
  : undefined;
const iotDataClient = new IoTDataPlaneClient(
  iotDataEndpoint ? { endpoint: iotDataEndpoint } : {},
);
const iotControlClient = new IoTClient({});
const s3Client = new S3Client({});

const iot = {
  publish: (params) => wrapPromise(() => iotDataClient.send(new PublishCommand(params))),
  getThingShadow: (params) =>
    wrapPromise(() => iotDataClient.send(new GetThingShadowCommand(params))),
  updateThingShadow: (params) =>
    wrapPromise(() => iotDataClient.send(new UpdateThingShadowCommand(params))),
};

const iotControl = {
  createJob: (params) => wrapPromise(() => iotControlClient.send(new CreateJobCommand(params))),
  describeThing: (params) => wrapPromise(() => iotControlClient.send(new DescribeThingCommand(params))),
};

function resp(statusCode, body, extraHeaders = null) {
  const payload =
    body && typeof body === 'object' && body !== null ? { ...body } : {};
  if (payload.error && payload.err == null) {
    payload.err = payload.error;
  }
  const baseHeaders = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization,content-type',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  };
  const mergedHeaders = extraHeaders
    ? { ...baseHeaders, ...extraHeaders }
    : baseHeaders;
  return {
    statusCode,
    headers: mergedHeaders,
    body: JSON.stringify(payload),
  };
}

function parseBody(event) {
  if (!event || !event.body) return {};
  const raw = event.isBase64Encoded
    ? Buffer.from(event.body, 'base64').toString('utf8')
    : event.body;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return {};
  }
}

function base64UrlEncode(input) {
  const buf = Buffer.isBuffer(input) ? input : Buffer.from(String(input), 'utf8');
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function base64UrlDecode(input) {
  const s = String(input || '').replace(/-/g, '+').replace(/_/g, '/');
  if (!s) return '';
  const padLen = (4 - (s.length % 4)) % 4;
  const padded = `${s}${'='.repeat(padLen)}`;
  return Buffer.from(padded, 'base64').toString('utf8');
}

function isPlainObject(v) {
  return !!v && typeof v === 'object' && !Array.isArray(v);
}

function isNonEmptyObject(v) {
  return isPlainObject(v) && Object.keys(v).length > 0;
}

function nowMs() {
  return Date.now();
}

function normalizeHex(v) {
  if (v == null) return '';
  return String(v).trim().toLowerCase();
}

function sha256Hex(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function safeEqualHex(a, b) {
  const left = normalizeHex(a);
  const right = normalizeHex(b);
  if (!left || !right || left.length !== right.length) return false;
  const lb = Buffer.from(left, 'utf8');
  const rb = Buffer.from(right, 'utf8');
  return crypto.timingSafeEqual(lb, rb);
}

function pickClaimProof(body) {
  if (!isPlainObject(body)) return '';
  const raw =
    body.claimSecret ??
    body.claim_secret ??
    body.pairToken ??
    body.pair_token ??
    body.proof ??
    body.qrToken ??
    body.qr_token ??
    '';
  return String(raw || '').trim();
}

function pickInviteToken(body) {
  if (!isPlainObject(body)) return '';
  // Accept token either at top-level (preferred) or nested under "invite"/"inviteQr"
  // to be backward-compatible with older clients.
  const nestedInvite = isPlainObject(body.invite) ? body.invite : null;
  const nestedQr = isPlainObject(body.inviteQr) ? body.inviteQr : null;
  const raw =
    body.inviteToken ??
    body.invite_token ??
    body.token ??
    nestedInvite?.inviteToken ??
    nestedInvite?.invite_token ??
    nestedInvite?.token ??
    nestedQr?.inviteToken ??
    nestedQr?.invite_token ??
    nestedQr?.token ??
    '';
  return String(raw || '').trim();
}

function pickUserIdHash(body) {
  if (!isPlainObject(body)) return '';
  const raw =
    body.userIdHash ??
    body.user_id_hash ??
    (isPlainObject(body.invite) ? (body.invite.userIdHash ?? body.invite.user_id_hash) : undefined) ??
    '';
  const s = String(raw || '').trim().toLowerCase();
  // Firmware expects a hex string (typically 64 chars), but keep validation loose
  // to avoid breaking existing deployments.
  return /^[0-9a-f]{16,128}$/.test(s) ? s : '';
}

function pickOwnerPubKeyB64(body) {
  if (!isPlainObject(body)) return '';
  const raw =
    body.ownerPubKey ??
    body.owner_pubkey ??
    body.ownerPublicKey ??
    '';
  return String(raw || '').trim();
}

function deriveUserIdHashFromOwnerPubKeyB64(pubB64) {
  const raw = String(pubB64 || '').trim();
  if (!raw) return '';
  try {
    const normalized = raw.replace(/-/g, '+').replace(/_/g, '/').replace(/\s+/g, '');
    const decoded = Buffer.from(normalized, 'base64');
    if (!decoded || decoded.length !== 65) return '';
    return crypto.createHash('sha256').update(decoded).digest('hex');
  } catch (_) {
    return '';
  }
}

function resolveOwnerUserIdHash(body) {
  const derived = deriveUserIdHashFromOwnerPubKeyB64(pickOwnerPubKeyB64(body));
  if (derived) return derived;
  return pickUserIdHash(body);
}

function parseScopes(raw) {
  if (Array.isArray(raw)) {
    return Array.from(
      new Set(
        raw
          .map((v) => String(v || '').trim())
          .filter((v) => !!v),
      ),
    );
  }
  const s = String(raw || '').trim();
  if (!s) return [];
  return Array.from(new Set(s.split(/[\s,]+/).map((v) => v.trim()).filter((v) => !!v)));
}

function normalizedIntegrationScopes(raw, fallback = [INTEGRATION_SCOPE_READ]) {
  const allowed = new Set([
    INTEGRATION_SCOPE_READ,
    INTEGRATION_SCOPE_WRITE,
    INTEGRATION_SCOPE_ADMIN,
  ]);
  const parsed = parseScopes(raw).filter((s) => allowed.has(s));
  return parsed.length ? parsed : fallback;
}

function hasIntegrationScope(scopes, requiredScope) {
  const set = new Set(normalizedIntegrationScopes(scopes, []));
  if (set.has(INTEGRATION_SCOPE_ADMIN)) return true;
  if (requiredScope === INTEGRATION_SCOPE_READ) {
    return set.has(INTEGRATION_SCOPE_READ) || set.has(INTEGRATION_SCOPE_WRITE);
  }
  return set.has(requiredScope);
}

function signInvitePayload(payloadObj) {
  const payload = base64UrlEncode(JSON.stringify(payloadObj));
  const sig = base64UrlEncode(
    crypto
      .createHmac('sha256', INVITE_TOKEN_SECRET)
      .update(payload, 'utf8')
      .digest(),
  );
  return `v1.${payload}.${sig}`;
}

function verifyInviteToken(token, { inviteId, deviceId, role, expiresAt }) {
  if (!FEATURE_SIGNED_INVITES) return { ok: true };
  const raw = String(token || '');
  const parts = raw.split('.');
  if (parts.length !== 3 || parts[0] !== 'v1') return { ok: false, err: 'invite_token_invalid' };
  const payloadB64 = parts[1];
  const sigB64 = parts[2];
  const expectedSig = base64UrlEncode(
    crypto
      .createHmac('sha256', INVITE_TOKEN_SECRET)
      .update(payloadB64, 'utf8')
      .digest(),
  );
  if (!safeEqualHex(sha256Hex(expectedSig), sha256Hex(sigB64))) {
    return { ok: false, err: 'invite_token_invalid' };
  }
  let payload = null;
  try {
    payload = JSON.parse(base64UrlDecode(payloadB64));
  } catch (_) {
    payload = null;
  }
  if (!isPlainObject(payload)) return { ok: false, err: 'invite_token_invalid' };
  if (String(payload.inviteId || '') !== String(inviteId || '')) {
    return { ok: false, err: 'invite_token_mismatch' };
  }
  if (String(payload.deviceId || '') !== String(deviceId || '')) {
    return { ok: false, err: 'invite_token_mismatch' };
  }
  if (String(payload.role || '').toUpperCase() !== String(role || '').toUpperCase()) {
    return { ok: false, err: 'invite_token_mismatch' };
  }
  const tokenExp = Number(payload.exp || 0);
  if (!Number.isFinite(tokenExp) || tokenExp <= 0) {
    return { ok: false, err: 'invite_token_invalid' };
  }
  const nowS = Math.floor(nowMs() / 1000);
  if (nowS >= tokenExp) return { ok: false, err: 'invite_token_expired' };
  const inviteExp = Number(expiresAt || 0);
  if (inviteExp > 0 && tokenExp > inviteExp + 5) {
    return { ok: false, err: 'invite_token_mismatch' };
  }
  return { ok: true, payload };
}

function buildInviteToken(invite) {
  if (!FEATURE_SIGNED_INVITES) return '';
  const usableUntil = inviteUsableUntilSec(invite);
  return signInvitePayload({
    inviteId: String(invite.inviteId || ''),
    deviceId: String(invite.deviceId || ''),
    role: roleNorm(invite.role, 'USER'),
    exp: usableUntil,
    iat: Math.floor(nowMs() / 1000),
  });
}

function getClaimSecretHash(item) {
  if (!item || typeof item !== 'object') return '';
  const raw =
    item.claimSecretHash ??
    item.claim_secret_hash ??
    item.pairTokenHash ??
    item.pair_token_hash ??
    '';
  return normalizeHex(raw);
}

function logEvent(tag, details) {
  console.log(`[CLOUD][${tag}]`, details);
}

function requireTable(label, tableName) {
  if (!tableName) {
    const err = new Error(`${label}_table_not_configured`);
    err.statusCode = 500;
    throw err;
  }
  return tableName;
}

async function fetchOwnership(deviceId, stage = '') {
  const tableName = requireTable('ownership', OWNERSHIP_TABLE);
  const key = { deviceId };
  logEvent('OWNERSHIP', {
    action: 'lookup',
    table: tableName,
    key,
    stage,
  });
  const out = await ddb
    .get({
      TableName: tableName,
      Key: key,
    })
    .promise();
  const item = out && out.Item ? out.Item : null;
  logEvent('OWNERSHIP', {
    action: item ? 'found' : 'missing',
    table: tableName,
    key,
    ownerUserId: item?.ownerUserId,
    status: item?.status,
    stage,
  });
  return item;
}

async function getUserDeviceLink(userSub, deviceId) {
  if (!USER_DEVICES_TABLE) return null;
  const out = await ddb
    .get({
      TableName: USER_DEVICES_TABLE,
      Key: { userId: userSub, deviceId },
    })
    .promise();
  return out?.Item || null;
}

function maskSub(sub) {
  if (!sub) return '';
  if (sub.length <= 8) return sub;
  return `${sub.slice(0, 4)}...${sub.slice(-4)}`;
}

function genCmdId() {
  const t = Date.now().toString(16);
  const r = Math.floor(Math.random() * 0xffffffff)
    .toString(16)
    .padStart(8, '0');
  return `${t}${r}`;
}

function genAuditId() {
  const t = Date.now().toString(36);
  const r = Math.floor(Math.random() * 0xffffffff)
    .toString(36)
    .padStart(7, '0');
  return `${t}-${r}`;
}

function genInviteId() {
  if (typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID().replace(/-/g, '');
  }
  return sha256Hex(`${Date.now()}-${Math.random()}`).slice(0, 32);
}

function payloadHash(value) {
  try {
    return sha256Hex(JSON.stringify(value));
  } catch (_) {
    return '';
  }
}

function roleNorm(raw, fallback = 'USER') {
  const v = (raw || fallback).toString().trim().toUpperCase();
  if (v === 'OWNER' || v === 'ADMIN' || v === 'USER' || v === 'GUEST') return v;
  return fallback;
}

function statusNorm(raw, fallback = 'active') {
  const v = (raw || fallback).toString().trim().toLowerCase();
  if (v === 'active' || v === 'deleted' || v === 'revoked' || v === 'pending' || v === 'accepted') {
    return v;
  }
  return fallback;
}

function normalizeDeviceBrand(raw, fallback = '') {
  const s = String(raw || '').trim();
  if (!s) return fallback;
  return s.slice(0, 64);
}

function normalizeDeviceSuffix(raw) {
  const s = String(raw || '').trim();
  if (!s) return '';
  return s.slice(0, 32);
}

function buildDeviceDisplayName(brand, suffix) {
  const normalizedBrand = normalizeDeviceBrand(brand, '');
  const normalizedSuffix = normalizeDeviceSuffix(suffix);
  if (!normalizedBrand) return '';
  if (!normalizedSuffix) return normalizedBrand;
  return `${normalizedBrand} ${normalizedSuffix}`;
}

function pickDevicePresentation(body) {
  const src = isPlainObject(body) ? body : {};
  const nestedDevice = isPlainObject(src.device) ? src.device : {};
  const brand = normalizeDeviceBrand(
    src.deviceBrand ??
      src.device_brand ??
      src.brand ??
      nestedDevice.deviceBrand ??
      nestedDevice.device_brand ??
      nestedDevice.brand ??
      '',
    '',
  );
  const suffix = normalizeDeviceSuffix(
    src.deviceSuffix ??
      src.device_suffix ??
      src.suffix ??
      nestedDevice.deviceSuffix ??
      nestedDevice.device_suffix ??
      nestedDevice.suffix ??
      '',
  );
  return {
    brand,
    suffix,
    displayName: buildDeviceDisplayName(brand, suffix),
  };
}

function getDevicePresentation(item) {
  if (!isPlainObject(item)) {
    return { brand: '', suffix: '', displayName: '' };
  }
  const brand = normalizeDeviceBrand(
    item.deviceBrand ??
      item.device_brand ??
      item.brand ??
      '',
    '',
  );
  const suffix = normalizeDeviceSuffix(
    item.deviceSuffix ??
      item.device_suffix ??
      item.suffix ??
      '',
  );
  const displayName = String(
    item.deviceDisplayName ??
      item.device_display_name ??
      item.displayName ??
      buildDeviceDisplayName(brand, suffix),
  ).trim();
  return { brand, suffix, displayName };
}

function inviteUsableUntilSec(invite) {
  const v = Number(
    invite?.validUntil ??
      invite?.valid_until ??
      invite?.inviteValidUntil ??
      invite?.invite_valid_until ??
      invite?.expiresAt ??
      0,
  );
  return Number.isFinite(v) && v > 0 ? v : 0;
}

function parseTtlSec(raw, fallbackSec = 86400, minSec = 60, maxSec = 7 * 24 * 3600) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallbackSec;
  return Math.max(minSec, Math.min(maxSec, Math.floor(n)));
}

function normalizeInviteeEmail(raw) {
  const s = String(raw || '').trim().toLowerCase();
  if (!s) return '';
  if (s.length > 254) return '';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s)) return '';
  return s;
}

function routeParamFromPath(rawPath, pattern) {
  const m = (rawPath || '').match(pattern);
  if (!m || !m[1]) return '';
  try {
    return decodeURIComponent(m[1]);
  } catch (_) {
    return m[1];
  }
}

function normalizeHex64(v) {
  const s = normalizeHex(v);
  return /^[0-9a-f]{64}$/.test(s) ? s : '';
}

function awsErrCode(e) {
  return String(e?.name || e?.code || '');
}

function missingThingNameFromCreateJobError(e) {
  const msg = String(e?.message || e || '');
  const m = msg.match(/Thing\s+([A-Za-z0-9:_-]+)\s+cannot be found\.?/i);
  return m && m[1] ? String(m[1]).trim() : '';
}

async function createIotJobWithMissingThingRetry({
  jobId,
  targets,
  document,
  targetSelection,
  description,
  stage = '',
  id6 = '',
}) {
  const uniqueTargets = Array.from(new Set((Array.isArray(targets) ? targets : []).filter((v) => !!v)));
  if (!uniqueTargets.length) {
    const err = new Error('iot_thing_arn_not_configured');
    err.statusCode = 500;
    throw err;
  }
  try {
    return await iotControl
      .createJob({
        jobId,
        targets: uniqueTargets,
        document,
        targetSelection,
        description,
      })
      .promise();
  } catch (e) {
    const missingThing = missingThingNameFromCreateJobError(e);
    if (!missingThing) throw e;
    const filtered = uniqueTargets.filter((arn) => !String(arn).endsWith(`:thing/${missingThing}`));
    if (!filtered.length || filtered.length === uniqueTargets.length) throw e;
    logEvent('OTA', {
      action: 'create_job_retry_without_missing_thing',
      id6,
      stage,
      jobId,
      missingThing,
      originalTargetCount: uniqueTargets.length,
      retryTargetCount: filtered.length,
    });
    return iotControl
      .createJob({
        jobId,
        targets: filtered,
        document,
        targetSelection,
        description,
      })
      .promise();
  }
}

function isConditionalCheckFailed(e) {
  return awsErrCode(e) === 'ConditionalCheckFailedException';
}

function currentFeatureFlags() {
  return {
    invites: FEATURE_INVITES && !!INVITES_TABLE,
    signedInvites: FEATURE_INVITES && FEATURE_SIGNED_INVITES && !!INVITES_TABLE,
    integrationLinks: !!INTEGRATION_LINKS_TABLE,
    claimProof: FEATURE_CLAIM_PROOF && CLAIM_PROOF_REQUIRED,
    cmdRateLimit: FEATURE_RATE_LIMIT && !!RATE_LIMIT_TABLE,
    cmdIdempotency: FEATURE_IDEMPOTENCY && !!CMD_IDEMPOTENCY_TABLE,
    shadowState: FEATURE_SHADOW_STATE && !!IOT_ENDPOINT,
    shadowDesired: FEATURE_SHADOW_DESIRED && !!IOT_ENDPOINT,
    shadowAclSync: FEATURE_SHADOW_ACL_SYNC && !!IOT_ENDPOINT,
    otaJobs: FEATURE_OTA_JOBS,
    audit: !!AUDIT_TABLE,
  };
}

function cloudStateFromCounts(deviceCount) {
  if (!IOT_ENDPOINT) return 'SETUP_REQUIRED';
  if (deviceCount > 0) return 'LINKED';
  return 'SETUP_REQUIRED';
}

function hasAnyKey(obj, keys) {
  if (!isPlainObject(obj)) return false;
  for (const k of keys) {
    if (Object.prototype.hasOwnProperty.call(obj, k)) return true;
  }
  return false;
}

function inferCapabilitiesFromState(stateObj) {
  const s = isPlainObject(stateObj) ? stateObj : {};
  const rawCaps = isPlainObject(s.capabilities) ? s.capabilities : null;
  if (rawCaps) {
    const caps = { ...rawCaps };
    if (!isPlainObject(caps.switches)) caps.switches = {};
    if (!isPlainObject(caps.controls)) caps.controls = {};
    if (!isPlainObject(caps.sensors)) caps.sensors = {};
    if (caps.schemaVersion == null || caps.schemaVersion === '') {
      caps.schemaVersion = '1';
    } else {
      caps.schemaVersion = String(caps.schemaVersion);
    }
    return caps;
  }

  const status = isPlainObject(s.status) ? s.status : {};
  const env = isPlainObject(s.env) ? s.env : {};
  const fan = isPlainObject(s.fan) ? s.fan : {};
  const city = isPlainObject(s.city) ? s.city : {};
  const rgb = isPlainObject(s.rgb) ? s.rgb : {};

  const switches = {
    masterOn: hasAnyKey(status, ['masterOn']) || hasAnyKey(s, ['masterOn']),
    lightOn: hasAnyKey(status, ['lightOn']) || hasAnyKey(s, ['lightOn']),
    cleanOn: hasAnyKey(status, ['cleanOn']) || hasAnyKey(s, ['cleanOn']),
    ionOn: hasAnyKey(status, ['ionOn']) || hasAnyKey(s, ['ionOn']),
    rgbOn: hasAnyKey(rgb, ['on']) || hasAnyKey(s, ['rgbOn']),
  };
  const controls = {
    mode: {
      supported: hasAnyKey(status, ['mode']) || hasAnyKey(s, ['mode']),
      type: 'enum',
      values: ['AUTO', 'SLEEP', 'LOW', 'MID', 'HIGH'],
    },
    fanPercent: {
      supported: hasAnyKey(status, ['fanPercent']) || hasAnyKey(s, ['fanPercent']),
      type: 'range',
      min: 0,
      max: 100,
    },
    rgb: {
      supported: hasAnyKey(rgb, ['r', 'g', 'b']) || hasAnyKey(s, ['r', 'g', 'b']),
      type: 'rgb',
    },
    rgbBrightness: {
      supported: hasAnyKey(rgb, ['brightness']) || hasAnyKey(s, ['rgbBrightness']),
      type: 'range',
      min: 0,
      max: 100,
    },
    autoHumEnabled: {
      supported: hasAnyKey(env, ['autoHumEnabled']),
      type: 'bool',
    },
    autoHumTarget: {
      supported: hasAnyKey(env, ['autoHumTarget']),
      type: 'range',
      min: 30,
      max: 70,
    },
  };
  const sensors = {
    tempC: hasAnyKey(env, ['tempC']) || hasAnyKey(s, ['tempC']),
    humPct: hasAnyKey(env, ['humPct', 'hum']) || hasAnyKey(s, ['hum', 'humPct']),
    pm2_5: hasAnyKey(env, ['pm2_5', 'pm25']) || hasAnyKey(s, ['pm2_5', 'pm25']),
    vocIndex: hasAnyKey(env, ['vocIndex']) || hasAnyKey(s, ['vocIndex']),
    noxIndex: hasAnyKey(env, ['noxIndex']) || hasAnyKey(s, ['noxIndex']),
    rpm: hasAnyKey(fan, ['rpm']) || hasAnyKey(s, ['rpm']),
    aqi: hasAnyKey(city, ['aqi']),
  };

  return {
    schemaVersion: '1',
    switches,
    controls,
    sensors,
    mappingHints: {
      homeAssistant: {
        switchDomain: 'switch',
        sensorDomain: 'sensor',
      },
      matter: {
        identifyCluster: true,
        fanControlCluster: !!controls.mode.supported,
      },
    },
  };
}

function normalizeOtaTargetValue(v) {
  return String(v ?? '')
    .trim()
    .toLowerCase();
}

function pickOtaTargetFromState(stateObj) {
  const s = isPlainObject(stateObj) ? stateObj : {};
  const meta = isPlainObject(s.meta) ? s.meta : {};
  const caps = isPlainObject(s.capabilities) ? s.capabilities : {};
  return {
    product: normalizeOtaTargetValue(
      meta.product ?? caps.deviceProduct ?? s.deviceProduct ?? '',
    ),
    hwRev: normalizeOtaTargetValue(
      meta.hwRev ?? caps.hwRev ?? s.hwRev ?? s.hardwareRev ?? '',
    ),
    boardRev: normalizeOtaTargetValue(
      meta.boardRev ?? caps.boardRev ?? s.boardRev ?? s.board ?? '',
    ),
    fwChannel: normalizeOtaTargetValue(
      meta.fwChannel ?? caps.fwChannel ?? s.fwChannel ?? s.channel ?? '',
    ),
  };
}

function pickOtaTargetFromRequest(body) {
  const b = isPlainObject(body) ? body : {};
  const target = isPlainObject(b.target) ? b.target : {};
  return {
    product: normalizeOtaTargetValue(
      target.product ?? target.deviceProduct ?? b.product ?? b.deviceProduct ?? '',
    ),
    hwRev: normalizeOtaTargetValue(
      target.hwRev ?? target.hardwareRev ?? b.hwRev ?? b.hardwareRev ?? '',
    ),
    boardRev: normalizeOtaTargetValue(
      target.boardRev ?? target.board ?? b.boardRev ?? b.board ?? '',
    ),
    fwChannel: normalizeOtaTargetValue(
      target.fwChannel ?? target.channel ?? b.fwChannel ?? b.channel ?? '',
    ),
  };
}

function capabilitySupported(v) {
  if (v === true) return true;
  if (isPlainObject(v) && v.supported === true) return true;
  return false;
}

function generateHaDiscoveryConfigMessages(deviceId, capabilities) {
  const caps = isPlainObject(capabilities) ? capabilities : {};
  const devicePart = String(deviceId || '').trim() || 'device';
  const entityBase = `aac_${devicePart}`;
  const thingName = thingNameFromId6(devicePart);
  const stateTopic = `aac/${devicePart}/state`;
  const cmdTopic = `aac/${devicePart}/cmd`;
  const shadowDesiredTopic = `$aws/things/${thingName}/shadow/update`;

  const messages = [];
  const pushMsg = (domain, keyRaw, payload) => {
    const key = String(keyRaw || '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '') || 'x';
    const uniqueId = `${entityBase}_${key}`;
    messages.push({
      topic: `homeassistant/${domain}/${uniqueId}/config`,
      payload: {
        ...payload,
        unique_id: uniqueId,
        device: {
          identifiers: [devicePart],
          name: `AAC ${devicePart}`,
          manufacturer: 'AAC',
          model: 'ArtAirCleaner',
        },
      },
    });
  };

  const switches = isPlainObject(caps.switches) ? caps.switches : {};
  for (const [key, v] of Object.entries(switches)) {
    if (!capabilitySupported(v)) continue;
    pushMsg('switch', key, {
      name: `AAC ${key}`,
      state_topic: stateTopic,
      value_template: `{{ value_json.${key} }}`,
      command_topic: cmdTopic,
      command_template: JSON.stringify({ [key]: '{{ value | tojson }}' }),
    });
  }

  const controls = isPlainObject(caps.controls) ? caps.controls : {};
  for (const [key, v] of Object.entries(controls)) {
    if (!capabilitySupported(v)) continue;
    const isMode = key.toLowerCase().includes('mode');
    if (isMode) {
      pushMsg('select', key, {
        name: `AAC ${key}`,
        state_topic: stateTopic,
        value_template: `{{ value_json.${key} }}`,
        command_topic: cmdTopic,
        command_template: JSON.stringify({ [key]: '{{ value }}' }),
      });
      continue;
    }
    const min = Number(v?.min);
    const max = Number(v?.max);
    pushMsg('number', key, {
      name: `AAC ${key}`,
      state_topic: stateTopic,
      value_template: `{{ value_json.${key} }}`,
      command_topic: shadowDesiredTopic,
      command_template: JSON.stringify({
        state: {
          desired: {
            [key]: '{{ value | float }}',
          },
        },
      }),
      mode: 'box',
      ...(Number.isFinite(min) ? { min } : {}),
      ...(Number.isFinite(max) ? { max } : {}),
    });
  }

  const sensors = isPlainObject(caps.sensors) ? caps.sensors : {};
  for (const [key, v] of Object.entries(sensors)) {
    if (!capabilitySupported(v)) continue;
    pushMsg('sensor', key, {
      name: `AAC ${key}`,
      state_topic: stateTopic,
      value_template: `{{ value_json.${key} }}`,
    });
  }

  return messages;
}

function thingNameFromId6(id6) {
  return `${THING_NAME_PREFIX}${id6}`;
}

function thingNameCandidatesFromId6(id6) {
  const normalized = String(id6 || '').trim();
  if (!normalized) return [];
  const out = [];
  const pref = String(THING_NAME_PREFIX || '').trim();
  if (pref) out.push(`${pref}${normalized}`);
  out.push(normalized);
  return Array.from(new Set(out.filter((v) => !!v)));
}

function thingArnFromId6(id6) {
  const thingName = thingNameFromId6(id6);
  if (IOT_THING_ARN_PREFIX) return `${IOT_THING_ARN_PREFIX}${thingName}`;
  const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || '';
  const accountId = process.env.AWS_ACCOUNT_ID || '';
  if (region && accountId) {
    return `arn:aws:iot:${region}:${accountId}:thing/${thingName}`;
  }
  return '';
}

function thingArnCandidatesFromId6(id6) {
  const names = thingNameCandidatesFromId6(id6);
  if (!names.length) return [];
  if (IOT_THING_ARN_PREFIX) {
    return Array.from(new Set(names.map((n) => `${IOT_THING_ARN_PREFIX}${n}`)));
  }
  const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || '';
  const accountId = process.env.AWS_ACCOUNT_ID || '';
  if (region && accountId) {
    return Array.from(new Set(
      names.map((n) => `arn:aws:iot:${region}:${accountId}:thing/${n}`),
    ));
  }
  return [];
}

function thingArnFromThingName(thingName) {
  const name = String(thingName || '').trim();
  if (!name) return '';
  if (IOT_THING_ARN_PREFIX) return `${IOT_THING_ARN_PREFIX}${name}`;
  const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || '';
  const accountId = process.env.AWS_ACCOUNT_ID || '';
  if (region && accountId) {
    return `arn:aws:iot:${region}:${accountId}:thing/${name}`;
  }
  return '';
}

function parseS3LocationFromUrl(rawUrl) {
  const url = String(rawUrl || '').trim();
  if (!url) return null;
  let parsed;
  try {
    parsed = new URL(url);
  } catch (_) {
    return null;
  }
  if (parsed.protocol !== 'https:') return null;
  if (parsed.searchParams.get('X-Amz-Signature')) return null;
  const host = parsed.hostname || '';
  let bucket = '';
  let key = '';
  let m = host.match(/^(.+)\.s3[.-][a-z0-9-]+\.amazonaws\.com$/i);
  if (m && m[1]) {
    bucket = m[1];
    key = parsed.pathname.replace(/^\/+/, '');
  } else {
    m = host.match(/^s3[.-][a-z0-9-]+\.amazonaws\.com$/i);
    if (m) {
      const parts = parsed.pathname.replace(/^\/+/, '').split('/');
      bucket = parts.shift() || '';
      key = parts.join('/');
    }
  }
  if (!bucket || !key) return null;
  return { bucket, key };
}

async function ensureSignedFirmwareUrl(rawUrl) {
  const url = String(rawUrl || '').trim();
  if (!url) return '';
  const s3Loc = parseS3LocationFromUrl(url);
  if (!s3Loc) return url;
  const expiresIn = Math.max(
    60,
    Math.min(7 * 24 * 3600, Number(process.env.OTA_URL_EXPIRES_SEC || 7 * 24 * 3600)),
  );
  return getSignedUrl(
    s3Client,
    new GetObjectCommand({
      Bucket: s3Loc.bucket,
      Key: s3Loc.key,
    }),
    { expiresIn },
  );
}

async function resolveExistingThingArnsForId6(id6, stage = '') {
  const names = thingNameCandidatesFromId6(id6);
  if (!names.length) return [];
  const resolved = [];
  for (const thingName of names) {
    try {
      const out = await iotControl
        .describeThing({ thingName })
        .promise();
      const arn = String(out?.thingArn || '').trim() || thingArnFromThingName(thingName);
      if (arn) resolved.push(arn);
      logEvent('OTA', {
        action: 'thing_resolved',
        id6,
        thingName,
        stage,
      });
    } catch (e) {
      logEvent('OTA', {
        action: 'thing_missing',
        id6,
        thingName,
        stage,
        errorCode: awsErrCode(e),
      });
    }
  }
  return Array.from(new Set(resolved));
}

function genOtaJobId(id6) {
  const t = Date.now().toString(36);
  const r = Math.floor(Math.random() * 0xffffffff)
    .toString(36)
    .padStart(7, '0');
  return `ota-${id6}-${t}-${r}`;
}

function genOtaCampaignJobId() {
  const t = Date.now().toString(36);
  const r = Math.floor(Math.random() * 0xffffffff)
    .toString(36)
    .padStart(7, '0');
  return `ota-campaign-${t}-${r}`;
}

function parsePositiveInt(raw, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return null;
  const i = Math.floor(n);
  if (i < min) return null;
  return Math.min(i, max);
}

function normalizeDeviceIdList(raw) {
  const src = Array.isArray(raw)
    ? raw
    : (typeof raw === 'string' ? raw.split(/[,\s]+/) : []);
  const out = [];
  for (const v of src) {
    const id = String(v || '').trim();
    if (/^[0-9]{6}$/.test(id)) out.push(id);
  }
  return Array.from(new Set(out));
}

function normalizeOtaRolloutPercent(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return 100;
  if (n <= 0) return 1;
  if (n >= 100) return 100;
  return Math.floor(n);
}

function rolloutBucketPercent(seed, deviceId) {
  const hex = sha256Hex(`${String(seed || '')}:${String(deviceId || '')}`).slice(0, 8);
  const n = Number.parseInt(hex, 16);
  if (!Number.isFinite(n)) return 100;
  return (n % 100) + 1;
}

function matchesRollout(seed, deviceId, percent) {
  if (percent >= 100) return true;
  return rolloutBucketPercent(seed, deviceId) <= percent;
}

function otaTargetMatchesFilter(deviceTarget, filterTarget) {
  const device = isPlainObject(deviceTarget) ? deviceTarget : {};
  const filter = isPlainObject(filterTarget) ? filterTarget : {};
  const keys = ['product', 'hwRev', 'boardRev', 'fwChannel'];
  for (const k of keys) {
    const expected = normalizeOtaTargetValue(filter[k]);
    if (!expected) continue;
    const actual = normalizeOtaTargetValue(device[k]);
    if (!actual || actual !== expected) return false;
  }
  return true;
}

function parseBoolean(v, fallback = false) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v !== 0;
  if (typeof v === 'string') {
    const s = v.trim().toLowerCase();
    if (s === '1' || s === 'true' || s === 'yes' || s === 'on') return true;
    if (s === '0' || s === 'false' || s === 'no' || s === 'off') return false;
  }
  return fallback;
}

function clampInt(value, min, max) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  const i = Math.round(n);
  return Math.max(min, Math.min(max, i));
}

function sanitizeDesiredPayload(input) {
  const src = isPlainObject(input) ? input : {};
  const out = {};

  const boolKeys = ['masterOn', 'lightOn', 'cleanOn', 'ionOn', 'rgbOn', 'autoHumEnabled'];
  for (const k of boolKeys) {
    if (Object.prototype.hasOwnProperty.call(src, k)) {
      const b = parseBoolean(src[k], false);
      out[k] = k === 'autoHumEnabled' ? (b ? 1 : 0) : b;
    }
  }

  if (Object.prototype.hasOwnProperty.call(src, 'mode')) {
    // Firmware accepts numeric mode values used by planner.
    const modeVal = clampInt(src.mode, 0, 10);
    if (modeVal != null) out.mode = modeVal;
  }
  if (Object.prototype.hasOwnProperty.call(src, 'fanPercent')) {
    const fan = clampInt(src.fanPercent, 0, 100);
    if (fan != null) out.fanPercent = fan;
  }
  if (Object.prototype.hasOwnProperty.call(src, 'rgbBrightness')) {
    const b = clampInt(src.rgbBrightness, 0, 100);
    if (b != null) out.rgbBrightness = b;
  }
  if (Object.prototype.hasOwnProperty.call(src, 'autoHumTarget')) {
    const t = clampInt(src.autoHumTarget, 30, 70);
    if (t != null) out.autoHumTarget = t;
  }

  if (isPlainObject(src.rgb)) {
    const rgbIn = src.rgb;
    const rgbOut = {};
    if (Object.prototype.hasOwnProperty.call(rgbIn, 'on')) {
      rgbOut.on = parseBoolean(rgbIn.on, false);
    }
    if (Object.prototype.hasOwnProperty.call(rgbIn, 'r')) {
      const r = clampInt(rgbIn.r, 0, 255);
      if (r != null) rgbOut.r = r;
    }
    if (Object.prototype.hasOwnProperty.call(rgbIn, 'g')) {
      const g = clampInt(rgbIn.g, 0, 255);
      if (g != null) rgbOut.g = g;
    }
    if (Object.prototype.hasOwnProperty.call(rgbIn, 'b')) {
      const b = clampInt(rgbIn.b, 0, 255);
      if (b != null) rgbOut.b = b;
    }
    if (Object.prototype.hasOwnProperty.call(rgbIn, 'brightness')) {
      const br = clampInt(rgbIn.brightness, 0, 100);
      if (br != null) rgbOut.brightness = br;
    }
    if (Object.keys(rgbOut).length > 0) out.rgb = rgbOut;
  }

  // Keep ACL writes possible for owner/admin flows.
  if (isPlainObject(src.acl)) {
    out.acl = src.acl;
  }

  // Clear stale command-only keys that can get stuck in desired and repeatedly
  // trigger firmware command handlers on each delta.
  const staleCmdKeys = [
    'type',
    'role',
    'ttl',
    'inviteId',
    'cmdId',
    'appDebugPing',
    'appDebugTs',
  ];
  for (const k of staleCmdKeys) out[k] = null;

  return out;
}

function desiredToCmdPayload(desired) {
  if (!isPlainObject(desired)) return {};
  const out = {};
  for (const [k, v] of Object.entries(desired)) {
    if (v === null || v === undefined) continue;
    if (k === 'acl') continue;
    out[k] = v;
  }
  return out;
}

function pruneNoopKeysAgainstReported(payload, reportedState, keepKeys = []) {
  const patch = isPlainObject(payload) ? payload : {};
  const reported = isPlainObject(reportedState) ? reportedState : {};
  const keep = new Set(Array.isArray(keepKeys) ? keepKeys : []);
  const out = {};
  for (const [k, v] of Object.entries(patch)) {
    if (keep.has(k)) {
      out[k] = v;
      continue;
    }
    if (v === null || v === undefined) continue;
    if (Object.prototype.hasOwnProperty.call(reported, k) && valuesDeepEqual(v, reported[k])) {
      continue;
    }
    out[k] = v;
  }
  return out;
}

function isCmdAuthKey(k) {
  return k === 'userIdHash' || k === 'cmdId';
}

function pruneNoopCmdPayload(cmdPayload, reportedState) {
  const raw = isPlainObject(cmdPayload) ? cmdPayload : {};
  const reported = isPlainObject(reportedState) ? reportedState : {};
  const out = {};
  let actionCount = 0;
  for (const [k, v] of Object.entries(raw)) {
    if (isCmdAuthKey(k)) continue;
    if (Object.prototype.hasOwnProperty.call(reported, k) && valuesDeepEqual(v, reported[k])) {
      continue;
    }
    out[k] = v;
    actionCount += 1;
  }
  if (actionCount > 0 && raw.userIdHash != null) {
    out.userIdHash = raw.userIdHash;
  }
  if (actionCount > 0 && raw.cmdId != null) {
    out.cmdId = raw.cmdId;
  }
  return out;
}

function stableSortObject(value) {
  if (Array.isArray(value)) return value.map((v) => stableSortObject(v));
  if (!isPlainObject(value)) return value;
  const out = {};
  for (const k of Object.keys(value).sort()) {
    out[k] = stableSortObject(value[k]);
  }
  return out;
}

function valuesDeepEqual(a, b) {
  try {
    return JSON.stringify(stableSortObject(a)) === JSON.stringify(stableSortObject(b));
  } catch (_) {
    return false;
  }
}

function buildEffectiveDesiredPatch(currentDesired, desiredPatch) {
  const current = isPlainObject(currentDesired) ? currentDesired : {};
  const patch = isPlainObject(desiredPatch) ? desiredPatch : {};
  const out = {};
  for (const [k, v] of Object.entries(patch)) {
    const hasCurrent = Object.prototype.hasOwnProperty.call(current, k);
    if (v === null) {
      if (hasCurrent) out[k] = null;
      continue;
    }
    if (!hasCurrent || !valuesDeepEqual(v, current[k])) {
      out[k] = v;
    }
  }
  return out;
}

function desiredCmdTransientCleanupFromCurrent(currentDesired) {
  const existing = isPlainObject(currentDesired) ? currentDesired : {};
  // Keep only long-lived desired branches. Command-like fields should not stay
  // in desired for USER flows, otherwise every reported shadow update can
  // continuously retrigger delta handling on device.
  const keep = new Set(['acl']);
  const cleanup = {};
  for (const k of Object.keys(existing)) {
    if (!keep.has(k)) cleanup[k] = null;
  }
  return cleanup;
}

function desiredCleanupFromCurrent(currentDesired) {
  const existing = isPlainObject(currentDesired) ? currentDesired : {};
  const allowed = new Set([
    'masterOn',
    'lightOn',
    'cleanOn',
    'ionOn',
    'rgbOn',
    'mode',
    'fanPercent',
    'rgbBrightness',
    'autoHumEnabled',
    'autoHumTarget',
    'userIdHash',
    'rgb',
    'acl',
  ]);
  const cleanup = {};
  for (const k of Object.keys(existing)) {
    if (!allowed.has(k)) cleanup[k] = null;
  }
  return cleanup;
}

function decodeIotPayload(payload) {
  if (payload == null) return null;
  let jsonText = '';
  if (typeof payload === 'string') {
    jsonText = payload;
  } else if (Buffer.isBuffer(payload)) {
    jsonText = payload.toString('utf8');
  } else if (payload instanceof Uint8Array) {
    jsonText = Buffer.from(payload).toString('utf8');
  } else {
    jsonText = String(payload);
  }
  if (!jsonText) return null;
  try {
    return JSON.parse(jsonText);
  } catch (_) {
    return null;
  }
}

function normalizeStateResponseObject(raw) {
  if (!isPlainObject(raw)) return {};
  const state = isPlainObject(raw.state) ? raw.state : null;
  if (!state) return raw;
  const reported = isPlainObject(state.reported) ? state.reported : null;
  if (reported) return reported;
  return state;
}

function stateHasExplicitRgb(stateObj) {
  const s = normalizeStateResponseObject(stateObj);
  if (!isPlainObject(s)) return false;
  const ui = isPlainObject(s.ui) ? s.ui : {};
  const rgb = isPlainObject(s.rgb) ? s.rgb : {};
  return (
    hasAnyKey(ui, ['rgbOn', 'rgbR', 'rgbG', 'rgbB', 'rgbBrightness']) ||
    hasAnyKey(rgb, ['on', 'r', 'g', 'b', 'brightness']) ||
    hasAnyKey(s, ['rgbOn', 'rgbBrightness', 'r', 'g', 'b'])
  );
}

function extractRgbSummary(stateObj) {
  const s = normalizeStateResponseObject(stateObj);
  if (!isPlainObject(s)) {
    return {
      hasRgb: false,
      ui: null,
      rgb: null,
    };
  }
  const ui = isPlainObject(s.ui) ? s.ui : null;
  const rgb = isPlainObject(s.rgb) ? s.rgb : null;
  return {
    hasRgb: stateHasExplicitRgb(s),
    ui: ui
      ? {
          rgbOn: ui.rgbOn ?? null,
          rgbR: ui.rgbR ?? null,
          rgbG: ui.rgbG ?? null,
          rgbB: ui.rgbB ?? null,
          rgbBrightness: ui.rgbBrightness ?? null,
        }
      : null,
    rgb: rgb
      ? {
          on: rgb.on ?? null,
          r: rgb.r ?? null,
          g: rgb.g ?? null,
          b: rgb.b ?? null,
          brightness: rgb.brightness ?? null,
        }
      : null,
  };
}

function mergeStateResponseObjects(primaryRaw, fallbackRaw) {
  const primary = normalizeStateResponseObject(primaryRaw);
  const fallback = normalizeStateResponseObject(fallbackRaw);
  if (!isPlainObject(primary)) return isPlainObject(fallback) ? fallback : {};
  if (!isPlainObject(fallback)) return primary;

  const merged = {
    ...fallback,
    ...primary,
  };

  const branchKeys = ['status', 'env', 'fan', 'city', 'meta', 'cloud', 'owner', 'join', 'auth', 'claim', 'ui', 'rgb'];
  for (const key of branchKeys) {
    const a = isPlainObject(primary[key]) ? primary[key] : null;
    const b = isPlainObject(fallback[key]) ? fallback[key] : null;
    if (a || b) {
      merged[key] = {
        ...(b || {}),
        ...(a || {}),
      };
    }
  }

  return merged;
}

function attachStateFreshness(statePayload, updatedAtMs) {
  const base = isPlainObject(statePayload) ? { ...statePayload } : {};
  const cloud = isPlainObject(base.cloud) ? { ...base.cloud } : {};
  const ts = Number(updatedAtMs || 0) || 0;
  if (ts > 0) {
    cloud.stateUpdatedAtMs = ts;
    base.cloud = cloud;
    base.stateUpdatedAtMs = ts;
  }
  return base;
}

async function fetchPersistedStateUpdatedAtMs(id6) {
  if (!STATE_TABLE) return 0;
  try {
    const out = await ddb
      .get({
        TableName: STATE_TABLE,
        Key: { deviceId: id6 },
        ProjectionExpression: 'updatedAt',
      })
      .promise();
    return Number(out?.Item?.updatedAt || 0) || 0;
  } catch (_) {
    return 0;
  }
}

async function fetchPersistedStateObject(id6, stage = '') {
  if (!STATE_TABLE) return null;
  const out = await ddb
    .get({
      TableName: STATE_TABLE,
      Key: { deviceId: id6 },
    })
    .promise();
  const payloadB64 = out?.Item?.payload_b64 || '';
  if (!payloadB64) return null;
  try {
    const jsonStr = Buffer.from(payloadB64, 'base64').toString('utf8');
    const parsed = JSON.parse(jsonStr);
    return isPlainObject(parsed) ? parsed : null;
  } catch (e) {
    logEvent('STATE', {
      action: 'decode_error',
      id6,
      stage,
      error: e?.message || e,
    });
    return null;
  }
}

async function fetchShadowReportedState(id6, stage = '') {
  if (!IOT_ENDPOINT) return null;
  const thingName = thingNameFromId6(id6);
  try {
    const out = await iot
      .getThingShadow({ thingName })
      .promise();
    const obj = decodeIotPayload(out?.payload);
    const reported =
      obj && isPlainObject(obj.state) && isPlainObject(obj.state.reported)
        ? obj.state.reported
        : null;
    logEvent('SHADOW', {
      action: isNonEmptyObject(reported) ? 'state_loaded' : 'state_empty',
      id6,
      thingName,
      stage,
    });
    return isNonEmptyObject(reported) ? reported : null;
  } catch (e) {
    logEvent('SHADOW', {
      action: 'state_error',
      id6,
      thingName,
      stage,
      errorCode: e?.code,
      error: e?.message || e,
    });
    return null;
  }
}

async function fetchShadowDesiredState(id6, stage = '') {
  if (!IOT_ENDPOINT) return null;
  const thingName = thingNameFromId6(id6);
  try {
    const out = await iot
      .getThingShadow({ thingName })
      .promise();
    const obj = decodeIotPayload(out?.payload);
    const desired =
      obj && isPlainObject(obj.state) && isPlainObject(obj.state.desired)
        ? obj.state.desired
        : null;
    return isNonEmptyObject(desired) ? desired : null;
  } catch (e) {
    logEvent('SHADOW', {
      action: 'desired_read_error',
      id6,
      thingName,
      stage,
      errorCode: e?.code,
      error: e?.message || e,
    });
    return null;
  }
}

async function cleanupShadowDesiredUnknownKeys(id6, stage = '') {
  if (!IOT_ENDPOINT) return { cleaned: false, count: 0 };
  const currentDesired = await fetchShadowDesiredState(id6, stage);
  const cleanupUnknown = desiredCleanupFromCurrent(currentDesired);
  const keys = Object.keys(cleanupUnknown);
  if (keys.length === 0) return { cleaned: false, count: 0 };
  try {
    await updateShadowDesiredState(id6, cleanupUnknown, stage);
    logEvent('SHADOW', {
      action: 'desired_cleanup_applied',
      id6,
      stage,
      cleanedCount: keys.length,
      cleanedKeys: keys,
    });
    return { cleaned: true, count: keys.length };
  } catch (e) {
    logEvent('SHADOW', {
      action: 'desired_cleanup_failed',
      id6,
      stage,
      errorCode: awsErrCode(e),
      error: e?.message || e,
    });
    return { cleaned: false, count: 0 };
  }
}

function claimHashFromObj(obj) {
  if (!isPlainObject(obj)) return '';
  const direct =
    obj.claimSecretHash ??
    obj.claim_secret_hash ??
    obj.pairTokenHash ??
    obj.pair_token_hash ??
    '';
  const directNorm = normalizeHex64(direct);
  if (directNorm) return directNorm;
  const claim = isPlainObject(obj.claim) ? obj.claim : null;
  if (!claim) return '';
  return normalizeHex64(
    claim.claimSecretHash ??
    claim.claim_secret_hash ??
    claim.pairTokenHash ??
    claim.pair_token_hash ??
    '',
  );
}

async function resolveClaimHashFromState(id6, stage = '') {
  if (FEATURE_SHADOW_STATE) {
    const shadowReported = await fetchShadowReportedState(id6, stage);
    const shadowHash = claimHashFromObj(shadowReported);
    if (shadowHash) {
      logEvent('CLAIM', {
        action: 'claim_hash_resolved',
        source: 'shadow_reported',
        id6,
        stage,
      });
      return { hash: shadowHash, source: 'shadow_reported' };
    }
  }

  if (STATE_TABLE) {
    try {
      const out = await ddb
        .get({
          TableName: STATE_TABLE,
          Key: { deviceId: id6 },
        })
        .promise();
      const item = out?.Item || null;
      if (item) {
        const fromAttrs = claimHashFromObj(item);
        if (fromAttrs) {
          logEvent('CLAIM', {
            action: 'claim_hash_resolved',
            source: 'state_item_attr',
            id6,
            stage,
          });
          return { hash: fromAttrs, source: 'state_item_attr' };
        }
        const payloadB64 = String(item.payload_b64 || '');
        if (payloadB64) {
          const jsonStr = Buffer.from(payloadB64, 'base64').toString('utf8');
          let parsed = null;
          try {
            parsed = JSON.parse(jsonStr);
          } catch (_) {
            parsed = null;
          }
          const fromPayload = claimHashFromObj(parsed);
          if (fromPayload) {
            logEvent('CLAIM', {
              action: 'claim_hash_resolved',
              source: 'state_payload_b64',
              id6,
              stage,
            });
            return { hash: fromPayload, source: 'state_payload_b64' };
          }
        }
      }
    } catch (e) {
      logEvent('CLAIM', {
        action: 'claim_hash_state_lookup_error',
        id6,
        stage,
        errorCode: e?.code,
        error: e?.message || e,
      });
    }
  }

  return { hash: '', source: '' };
}

async function syncClaimProofForDevice({
  id6,
  userSub,
  claimProof,
  stageDetected,
}) {
  const ownershipTable = requireTable('ownership', OWNERSHIP_TABLE);
  const deviceRecord = await ddb
    .get({
      TableName: ownershipTable,
      Key: { deviceId: id6 },
    })
    .promise();
  if (!deviceRecord?.Item) {
    return { ok: false, code: 404, err: 'device_not_found' };
  }

  const currentOwner = (
    deviceRecord.Item.ownerUserId || deviceRecord.Item.ownerSub || ''
  ).toString();
  const currentStatus = statusNorm(deviceRecord.Item.status, 'active');
  if (currentOwner && currentOwner !== userSub) {
    return { ok: false, code: 403, err: 'already_claimed' };
  }

  if (!claimProof) {
    return { ok: false, code: 400, err: 'claim_proof_required' };
  }
  const providedClaimHash = normalizeHex64(sha256Hex(claimProof));
  if (!providedClaimHash) {
    return { ok: false, code: 400, err: 'invalid_claim_proof' };
  }

  const storedClaimHash = getClaimSecretHash(deviceRecord.Item);
  let expectedClaimHash = storedClaimHash;
  let expectedClaimHashSource = storedClaimHash ? 'ownership' : '';
  if (!expectedClaimHash) {
    const resolved = await resolveClaimHashFromState(id6, stageDetected);
    expectedClaimHash = resolved.hash;
    expectedClaimHashSource = resolved.source || '';
  }
  const canRotateProof =
    !currentOwner || currentStatus === 'deleted';
  if (expectedClaimHash && !safeEqualHex(expectedClaimHash, providedClaimHash) && !canRotateProof) {
    await writeAudit('claim_proof_sync_denied', {
      deviceId: id6,
      userSub,
      reason: 'claim_proof_mismatch',
      expectedClaimHashSource,
    });
    return { ok: false, code: 403, err: 'claim_proof_mismatch' };
  }

  const now = nowMs();
  await ddb
    .update({
      TableName: ownershipTable,
      Key: { deviceId: id6 },
      UpdateExpression:
        'SET claimSecretHash = :hash, claimProofSyncedAt = :now, claimProofSyncedBy = :by, updatedAt = :now',
      ConditionExpression:
        'attribute_exists(deviceId) AND (attribute_not_exists(ownerUserId) OR ownerUserId = :by OR #st = :deleted)',
      ExpressionAttributeNames: {
        '#st': 'status',
      },
      ExpressionAttributeValues: {
        ':hash': providedClaimHash,
        ':now': now,
        ':by': userSub,
        ':deleted': 'deleted',
      },
    })
    .promise();

  await writeAudit('claim_proof_synced', {
    deviceId: id6,
    userSub,
    source: expectedClaimHashSource || 'provided',
    rotated: !!(expectedClaimHash && !safeEqualHex(expectedClaimHash, providedClaimHash)),
  });
  return {
    ok: true,
    code: 200,
    hashSource: expectedClaimHashSource || 'provided',
    rotated: !!(expectedClaimHash && !safeEqualHex(expectedClaimHash, providedClaimHash)),
  };
}

async function recoverOwnershipForDevice({
  id6,
  userSub,
  claimProof,
  userIdHash = '',
  deviceBrand = '',
  deviceSuffix = '',
  stageDetected,
}) {
  const ownershipTable = requireTable('ownership', OWNERSHIP_TABLE);
  const deviceRecord = await ddb
    .get({
      TableName: ownershipTable,
      Key: { deviceId: id6 },
    })
    .promise();
  if (!deviceRecord?.Item) {
    return { ok: false, code: 404, err: 'device_not_found' };
  }

  if (!claimProof) {
    return { ok: false, code: 400, err: 'claim_proof_required' };
  }
  const providedClaimHash = normalizeHex64(sha256Hex(claimProof));
  if (!providedClaimHash) {
    return { ok: false, code: 400, err: 'invalid_claim_proof' };
  }

  const resolved = await resolveClaimHashFromState(id6, stageDetected);
  const liveClaimHash = resolved.hash;
  const liveClaimHashSource = resolved.source || '';
  if (!liveClaimHash) {
    await writeAudit('ownership_recovery_denied', {
      deviceId: id6,
      userSub,
      reason: 'recovery_claim_proof_unavailable',
    });
    return { ok: false, code: 409, err: 'recovery_claim_proof_unavailable' };
  }
  if (!safeEqualHex(liveClaimHash, providedClaimHash)) {
    await writeAudit('ownership_recovery_denied', {
      deviceId: id6,
      userSub,
      reason: 'claim_proof_mismatch',
      liveClaimHashSource,
    });
    return { ok: false, code: 403, err: 'claim_proof_mismatch' };
  }

  const previousOwner = String(
    deviceRecord.Item.ownerUserId || deviceRecord.Item.ownerSub || '',
  );
  const previousStatus = statusNorm(deviceRecord.Item.status, 'active');
  const now = nowMs();

  let membersRevoked = 0;
  let invitesRevoked = 0;
  if (USER_DEVICES_TABLE) {
    membersRevoked = await revokeAllMembersForDevice(id6, userSub, stageDetected);
  }
  if (INVITES_TABLE) {
    invitesRevoked = await revokeAllInvitesForDevice(id6, userSub, stageDetected);
  }

  const exprNames = {
    '#st': 'status',
  };
  const exprValues = {
    ':me': userSub,
    ':now': now,
    ':active': 'active',
    ':claimHash': providedClaimHash,
    ':prevOwner': previousOwner,
    ':prevStatus': previousStatus,
  };
  let updateExpression =
    'SET ownerUserId = :me, ownerSub = :me, claimedAt = :now, #st = :active, ' +
    'lastClaimedBy = :me, lastClaimedAt = :now, updatedAt = :now, createdAt = if_not_exists(createdAt, :now), ' +
    'claimSecretHash = :claimHash, recoveredAt = :now, recoveredBy = :me, recoveredFromOwnerUserId = :prevOwner, recoveredFromStatus = :prevStatus';
  if (userIdHash) {
    updateExpression += ', ownerUserIdHash = :userIdHash';
    exprValues[':userIdHash'] = userIdHash;
  }
  if (deviceBrand) {
    updateExpression += ', deviceBrand = :deviceBrand';
    exprValues[':deviceBrand'] = deviceBrand;
  }
  updateExpression += ', deviceSuffix = :deviceSuffix';
  exprValues[':deviceSuffix'] = deviceSuffix;
  const deviceDisplayName = buildDeviceDisplayName(deviceBrand, deviceSuffix);
  if (deviceDisplayName) {
    updateExpression += ', deviceDisplayName = :deviceDisplayName';
    exprValues[':deviceDisplayName'] = deviceDisplayName;
  }

  await ddb
    .update({
      TableName: ownershipTable,
      Key: { deviceId: id6 },
      UpdateExpression: updateExpression,
      ConditionExpression: 'attribute_exists(deviceId)',
      ExpressionAttributeNames: exprNames,
      ExpressionAttributeValues: exprValues,
    })
    .promise();

  if (USER_DEVICES_TABLE) {
    const key = { userId: userSub, deviceId: id6 };
    try {
      await ddb
        .put({
          TableName: USER_DEVICES_TABLE,
          Item: {
            userId: userSub,
            deviceId: id6,
            role: 'OWNER',
            status: 'active',
            claimedAt: now,
            updatedAt: now,
            userIdHash: userIdHash || undefined,
          },
          ConditionExpression:
            'attribute_not_exists(userId) AND attribute_not_exists(deviceId)',
        })
        .promise();
    } catch (e) {
      if (!isConditionalCheckFailed(e)) throw e;
      const exprNames2 = {
        '#st': 'status',
        '#role': 'role',
      };
      const exprValues2 = {
        ':active': 'active',
        ':owner': 'OWNER',
        ':now': now,
      };
      let updateExpression2 =
        'SET #st = :active, #role = :owner, updatedAt = :now';
      if (userIdHash) {
        updateExpression2 += ', userIdHash = :userIdHash';
        exprValues2[':userIdHash'] = userIdHash;
      }
      await ddb
        .update({
          TableName: USER_DEVICES_TABLE,
          Key: key,
          UpdateExpression: updateExpression2,
          ExpressionAttributeNames: exprNames2,
          ExpressionAttributeValues: exprValues2,
        })
        .promise();
    }
  }

  await writeAudit('ownership_recovered', {
    deviceId: id6,
    userSub,
    previousOwner,
    previousStatus,
    liveClaimHashSource,
    membersRevoked,
    invitesRevoked,
  });

  return {
    ok: true,
    code: 200,
    previousOwner,
    previousStatus,
    membersRevoked,
    invitesRevoked,
    liveClaimHashSource,
  };
}

async function bootstrapClaimOwnership({
  id6,
  userSub,
  now,
  claimProof,
  userIdHash,
  deviceBrand = '',
  deviceSuffix = '',
  stageDetected,
}) {
  const ownershipTable = requireTable('ownership', OWNERSHIP_TABLE);
  const claimSecretHash = claimProof
    ? normalizeHex64(sha256Hex(claimProof))
    : '';
  const item = {
    deviceId: id6,
    ownerUserId: userSub,
    ownerSub: userSub,
    claimedAt: now,
    status: 'active',
    lastClaimedBy: userSub,
    lastClaimedAt: now,
    createdAt: now,
    updatedAt: now,
  };
  if (claimSecretHash) {
    item.claimSecretHash = claimSecretHash;
  }
  if (userIdHash) {
    item.ownerUserIdHash = userIdHash;
  }
  const deviceDisplayName = buildDeviceDisplayName(deviceBrand, deviceSuffix);
  if (deviceBrand) item.deviceBrand = deviceBrand;
  if (deviceSuffix) item.deviceSuffix = deviceSuffix;
  if (deviceDisplayName) item.deviceDisplayName = deviceDisplayName;

  try {
    await ddb
      .put({
        TableName: ownershipTable,
        Item: item,
        ConditionExpression: 'attribute_not_exists(deviceId)',
      })
      .promise();
  } catch (e) {
    if (isConditionalCheckFailed(e)) {
      return { ok: false, code: 409, err: 'claim_race_retry' };
    }
    throw e;
  }

  if (USER_DEVICES_TABLE) {
    const key = { userId: userSub, deviceId: id6 };
    try {
      await ddb
        .put({
          TableName: USER_DEVICES_TABLE,
          Item: {
            userId: userSub,
            deviceId: id6,
            role: 'OWNER',
            status: 'active',
            claimedAt: now,
            updatedAt: now,
            userIdHash: userIdHash || undefined,
          },
          ConditionExpression:
            'attribute_not_exists(userId) AND attribute_not_exists(deviceId)',
        })
        .promise();
    } catch (e) {
      if (isConditionalCheckFailed(e)) {
        const exprNames = {
          '#st': 'status',
          '#role': 'role',
        };
        const exprValues = {
          ':active': 'active',
          ':owner': 'OWNER',
          ':now': now,
        };
        let updateExpression =
          'SET #st = :active, #role = :owner, updatedAt = :now';
        if (userIdHash) {
          updateExpression += ', userIdHash = if_not_exists(userIdHash, :userIdHash)';
          exprValues[':userIdHash'] = userIdHash;
        }
        await ddb
          .update({
            TableName: USER_DEVICES_TABLE,
            Key: key,
            UpdateExpression: updateExpression,
            ExpressionAttributeNames: exprNames,
            ExpressionAttributeValues: exprValues,
          })
          .promise();
      } else {
        throw e;
      }
    }
  }

  await writeAudit('claim_bootstrap_created', {
    deviceId: id6,
    userSub,
    hasClaimProof: !!claimSecretHash,
    stage: stageDetected,
  });

  return { ok: true, code: 200, claimSecretHashStored: !!claimSecretHash };
}

async function updateShadowDesiredState(id6, desired, stage = '') {
  if (!IOT_ENDPOINT) {
    const err = new Error('iot_endpoint_not_configured');
    err.statusCode = 500;
    throw err;
  }
  const thingName = thingNameFromId6(id6);
  const payload = {
    state: { desired },
  };
  const out = await iot
    .updateThingShadow({
      thingName,
      payload: JSON.stringify(payload),
    })
    .promise();
  const parsed = decodeIotPayload(out?.payload) || {};
  logEvent('SHADOW', {
    action: 'desired_updated',
    id6,
    thingName,
    stage,
  });
  return parsed;
}

async function loadStateObjectForIntegrations(id6, stage = '') {
  let stateObj = null;
  let source = 'default';

  if (FEATURE_SHADOW_STATE) {
    const shadowReported = await fetchShadowReportedState(id6, stage);
    if (shadowReported && isPlainObject(shadowReported)) {
      stateObj = shadowReported;
      source = 'shadow';
    }
  }

  if (!stateObj && STATE_TABLE) {
    const out = await ddb
      .get({
        TableName: STATE_TABLE,
        Key: { deviceId: id6 },
      })
      .promise();
    const payloadB64 = out?.Item?.payload_b64 || '';
    if (payloadB64) {
      try {
        const jsonStr = Buffer.from(payloadB64, 'base64').toString('utf8');
        const parsed = JSON.parse(jsonStr);
        if (isPlainObject(parsed)) {
          stateObj = parsed;
          source = 'ddb';
        }
      } catch (_) {
        // keep default
      }
    }
  }

  return { stateObj, source };
}

async function writeAudit(eventType, details = {}) {
  if (!AUDIT_TABLE) return;
  const now = Date.now();
  const nowSec = Math.floor(now / 1000);
  const item = {
    auditId: genAuditId(),
    eventType,
    createdAt: now,
    expiresAt: nowSec + AUDIT_TTL_SEC,
    ...details,
  };
  try {
    await ddb
      .put({
        TableName: AUDIT_TABLE,
        Item: item,
      })
      .promise();
  } catch (e) {
    logEvent('AUDIT', {
      action: 'write_failed',
      eventType,
      errorCode: e?.code,
      error: e?.message || e,
    });
  }
}

async function reserveCmdIdempotency(deviceId, userSub, cmdId, nowMs) {
  if (!CMD_IDEMPOTENCY_TABLE) {
    return { enforced: false, duplicate: false };
  }
  const nowSec = Math.floor(nowMs / 1000);
  const cmdKey = `${deviceId}#${cmdId}`;
  try {
    await ddb
      .put({
        TableName: CMD_IDEMPOTENCY_TABLE,
        Item: {
          cmdKey,
          deviceId,
          cmdId,
          userSub,
          createdAt: nowMs,
          expiresAt: nowSec + IDEMPOTENCY_TTL_SEC,
        },
        ConditionExpression: 'attribute_not_exists(cmdKey)',
      })
      .promise();
    return { enforced: true, duplicate: false };
  } catch (e) {
    if (isConditionalCheckFailed(e)) {
      return { enforced: true, duplicate: true };
    }
    throw e;
  }
}

async function enforceCmdRateLimit(deviceId, userSub, now = nowMs()) {
  if (!RATE_LIMIT_TABLE) {
    return {
      enforced: false,
      limited: false,
      count: 0,
      max: CMD_RATE_LIMIT_MAX,
      windowSec: CMD_RATE_LIMIT_WINDOW_SEC,
      retryAfterSec: 0,
    };
  }
  return enforceRateLimitByKey({
    rateKey: `cmd#${userSub}#${deviceId}`,
    now,
    max: CMD_RATE_LIMIT_MAX,
    windowSec: CMD_RATE_LIMIT_WINDOW_SEC,
    userSub,
    deviceId,
  });
}

async function enforceClaimProofSyncRateLimit(deviceId, userSub, now = nowMs()) {
  if (!RATE_LIMIT_TABLE) {
    return {
      enforced: false,
      limited: false,
      count: 0,
      max: CLAIM_PROOF_SYNC_RATE_LIMIT_MAX,
      windowSec: CLAIM_PROOF_SYNC_RATE_LIMIT_WINDOW_SEC,
      retryAfterSec: 0,
    };
  }
  return enforceRateLimitByKey({
    rateKey: `claimsync#${userSub}#${deviceId}`,
    now,
    max: CLAIM_PROOF_SYNC_RATE_LIMIT_MAX,
    windowSec: CLAIM_PROOF_SYNC_RATE_LIMIT_WINDOW_SEC,
    userSub,
    deviceId,
  });
}

async function enforceRateLimitByKey({
  rateKey,
  now,
  max,
  windowSec,
  userSub,
  deviceId,
}) {
  const nowSec = Math.floor(now / 1000);
  const windowStartSec = nowSec - (nowSec % windowSec);
  const expiresAt = windowStartSec + windowSec + 5;
  let count = 0;

  try {
    const out = await ddb
      .update({
        TableName: RATE_LIMIT_TABLE,
        Key: { rateKey },
        UpdateExpression:
          'SET windowStartSec = if_not_exists(windowStartSec, :ws), updatedAt = :now, expiresAt = :exp ' +
          'ADD requestCount :one',
        ConditionExpression:
          'attribute_not_exists(windowStartSec) OR windowStartSec = :ws',
        ExpressionAttributeValues: {
          ':ws': windowStartSec,
          ':now': now,
          ':exp': expiresAt,
          ':one': 1,
        },
        ReturnValues: 'UPDATED_NEW',
      })
      .promise();
    count = Number(out?.Attributes?.requestCount || 0);
  } catch (e) {
    if (!isConditionalCheckFailed(e)) throw e;
    await ddb
      .put({
        TableName: RATE_LIMIT_TABLE,
        Item: {
          rateKey,
          userSub,
          deviceId,
          windowStartSec,
          requestCount: 1,
          updatedAt: now,
          expiresAt,
        },
      })
      .promise();
    count = 1;
  }

  const limited = count > max;
  const retryAfterSec = limited
    ? Math.max(1, windowSec - (nowSec - windowStartSec))
    : 0;
  return {
    enforced: true,
    limited,
    count,
    max,
    windowSec,
    retryAfterSec,
  };
}

function routeMatches(method, rawPath, routeKey, expectedRouteKey, expectedPathRegex) {
  if (routeKey === expectedRouteKey) return true;
  if (method !== expectedRouteKey.split(' ')[0]) return false;
  return expectedPathRegex.test(rawPath || '');
}

function requireId6(id6) {
  if (!/^[0-9]{6}$/.test(id6 || '')) {
    const err = new Error('invalid_device_id');
    err.statusCode = 400;
    throw err;
  }
  return id6;
}

async function listDevicesForUser(userSub, stage = '') {
  const out = [];
  const seen = new Set();

  if (USER_DEVICES_TABLE) {
    const tableName = USER_DEVICES_TABLE;
    logEvent('DEVICES', {
      action: 'query_user_devices',
      table: tableName,
      key: { userId: userSub },
      stage,
    });
    const q = await ddb
      .query({
        TableName: tableName,
        KeyConditionExpression: 'userId = :uid',
        ExpressionAttributeValues: {
          ':uid': userSub,
        },
      })
      .promise();
    const items = Array.isArray(q?.Items) ? q.Items : [];
    for (const item of items) {
      const deviceId = (item?.deviceId || '').toString();
      const status = (item?.status || 'active').toString().toLowerCase();
      if (
        !/^[0-9]{6}$/.test(deviceId) ||
        status === 'deleted' ||
        status === 'revoked' ||
        status === 'pending'
      ) {
        continue;
      }
      const role = (item?.role || 'OWNER').toString().toUpperCase();
      const existing = out.find((it) => it.deviceId === deviceId);
      if (!existing) {
        seen.add(deviceId);
        out.push({
          deviceId,
          role,
          status,
          source: 'user_devices',
        });
      } else {
        existing.status = statusNorm(existing.status, status);
        if (role === 'OWNER') existing.role = 'OWNER';
        existing.source = existing.source === 'ownership_gsi'
          ? 'user_devices+ownership_gsi'
          : existing.source;
      }
    }
  }

  if (OWNERSHIP_BY_OWNER_GSI) {
    const tableName = requireTable('ownership', OWNERSHIP_TABLE);
    logEvent('DEVICES', {
      action: 'query_ownership_gsi',
      table: tableName,
      index: OWNERSHIP_BY_OWNER_GSI,
      key: { ownerUserId: userSub },
      stage,
    });
    const q = await ddb
      .query({
        TableName: tableName,
        IndexName: OWNERSHIP_BY_OWNER_GSI,
        KeyConditionExpression: 'ownerUserId = :uid',
        ExpressionAttributeValues: {
          ':uid': userSub,
        },
      })
      .promise();
    const items = Array.isArray(q?.Items) ? q.Items : [];
    for (const item of items) {
      const deviceId = (item?.deviceId || '').toString();
      const status = (item?.status || 'active').toString().toLowerCase();
      if (!/^[0-9]{6}$/.test(deviceId) || status === 'deleted') continue;
      const role = (item?.role || 'OWNER').toString().toUpperCase();
      const existing = out.find((it) => it.deviceId === deviceId);
      if (!existing) {
        seen.add(deviceId);
        out.push({
          deviceId,
          role,
          status,
          source: 'ownership_gsi',
        });
      } else {
        if (role === 'OWNER') existing.role = 'OWNER';
        if (!existing.source.includes('ownership_gsi')) {
          existing.source = `${existing.source}+ownership_gsi`;
        }
      }
    }
  }

  const presentationCache = new Map();
  async function enrichDevicePresentation(device) {
    const deviceId = String(device?.deviceId || '');
    if (!deviceId) return;
    if (presentationCache.has(deviceId)) {
      Object.assign(device, presentationCache.get(deviceId));
      return;
    }
    device.thingName = thingNameFromId6(deviceId);
    let presentation = { brand: '', suffix: '', displayName: '' };
    try {
      const ownership = await fetchOwnership(deviceId, stage);
      presentation = getDevicePresentation(ownership);
    } catch (_) {
      presentation = { brand: '', suffix: '', displayName: '' };
    }
    const enriched = { ...presentation, thingName: device.thingName };
    presentationCache.set(deviceId, enriched);
    Object.assign(device, enriched);
  }
  await Promise.all(out.map((device) => enrichDevicePresentation(device)));

  out.sort((a, b) => a.deviceId.localeCompare(b.deviceId));
  logEvent('DEVICES', {
    action: 'list_done',
    userSub,
    count: out.length,
    devices: out.map((d) => ({
      deviceId: d.deviceId,
      role: d.role,
      status: d.status,
      source: d.source,
    })),
    stage,
  });
  return out;
}

async function getMembership(deviceId, userSub, stage = '') {
  const item = await fetchOwnership(deviceId, stage);
  const ownerUserId = ((item && (item.ownerUserId || item.ownerSub)) || '').toString();
  const ownerStatus = statusNorm(item?.status, 'active');
  if (ownerUserId && ownerUserId === userSub && ownerStatus !== 'deleted') {
    const role = 'OWNER';
    logEvent('MEMBERSHIP', {
      action: 'resolve_owner',
      table: OWNERSHIP_TABLE,
      key: { deviceId },
      userSub,
      ownerUserId,
      role,
      status: ownerStatus,
      stage,
    });
    return { ownerUserId, role, status: ownerStatus, raw: item };
  }

  const link = await getUserDeviceLink(userSub, deviceId);
  if (!link) return null;
  const linkStatus = statusNorm(link.status, 'active');
  if (linkStatus === 'deleted' || linkStatus === 'revoked') return null;
  const role = roleNorm(link.role, 'USER');
  const status = linkStatus;
  logEvent('MEMBERSHIP', {
    action: 'resolve',
    table: USER_DEVICES_TABLE || OWNERSHIP_TABLE,
    key: { deviceId },
    userSub,
    ownerUserId,
    role,
    status,
    stage,
  });
  return { ownerUserId, role, status, raw: { ownership: item, link } };
}

async function requireMember(deviceId, userSub, stage = '') {
  const membership = await getMembership(deviceId, userSub, stage);
  const st = statusNorm(membership?.status, 'deleted');
  if (!membership || st === 'deleted' || st === 'revoked') {
    logEvent('MEMBERSHIP', {
      action: 'denied',
      table: USER_DEVICES_TABLE || OWNERSHIP_TABLE,
      key: { deviceId },
      userSub,
      ownerUserId: membership?.ownerUserId,
      role: membership?.role,
      status: st,
      stage,
    });
    const err = new Error('not_member');
    err.statusCode = 403;
    throw err;
  }
  return membership;
}

async function requireOwner(deviceId, userSub, stage = '') {
  const membership = await requireMember(deviceId, userSub, stage);
  if (roleNorm(membership.role, 'USER') !== 'OWNER') {
    const err = new Error('owner_required');
    err.statusCode = 403;
    throw err;
  }
  return membership;
}

async function fetchInvite(inviteId) {
  const tableName = requireTable('invites', INVITES_TABLE);
  const out = await ddb
    .get({
      TableName: tableName,
      Key: { inviteId },
    })
    .promise();
  return out?.Item || null;
}

async function getIntegrationLink(integrationId, deviceId) {
  if (!INTEGRATION_LINKS_TABLE) return null;
  const out = await ddb
    .get({
      TableName: INTEGRATION_LINKS_TABLE,
      Key: { integrationId, deviceId },
    })
    .promise();
  return out?.Item || null;
}

async function requireIntegrationAccess({
  integrationId,
  deviceId,
  requiredScope = INTEGRATION_SCOPE_READ,
  stage = '',
}) {
  const tableName = requireTable('integration_links', INTEGRATION_LINKS_TABLE);
  const link = await getIntegrationLink(integrationId, deviceId);
  if (!link) {
    const err = new Error('integration_not_linked');
    err.statusCode = 403;
    throw err;
  }
  const status = statusNorm(link.status, 'active');
  const nowS = Math.floor(nowMs() / 1000);
  const expiresAt = Number(link.expiresAt || 0);
  if (status !== 'active' || (expiresAt > 0 && nowS >= expiresAt)) {
    const err = new Error('integration_link_inactive');
    err.statusCode = 403;
    throw err;
  }
  if (!hasIntegrationScope(link.scopes, requiredScope)) {
    const err = new Error('integration_scope_denied');
    err.statusCode = 403;
    throw err;
  }
  logEvent('INTEGRATION', {
    action: 'access_granted',
    table: tableName,
    integrationId,
    deviceId,
    requiredScope,
    stage,
  });
  return link;
}

async function listIntegrationLinksByDevice(deviceId, stage = '') {
  if (!INTEGRATION_LINKS_TABLE) return [];
  let items = [];
  try {
    const q = await ddb
      .query({
        TableName: INTEGRATION_LINKS_TABLE,
        IndexName: INTEGRATION_LINKS_BY_DEVICE_GSI,
        KeyConditionExpression: 'deviceId = :did',
        ExpressionAttributeValues: {
          ':did': deviceId,
        },
      })
      .promise();
    items = Array.isArray(q?.Items) ? q.Items : [];
  } catch (e) {
    logEvent('INTEGRATION', {
      action: 'query_fallback_scan',
      table: INTEGRATION_LINKS_TABLE,
      index: INTEGRATION_LINKS_BY_DEVICE_GSI,
      deviceId,
      stage,
      errorCode: e?.code,
    });
    const s = await ddb
      .scan({
        TableName: INTEGRATION_LINKS_TABLE,
        FilterExpression: 'deviceId = :did',
        ExpressionAttributeValues: {
          ':did': deviceId,
        },
      })
      .promise();
    items = Array.isArray(s?.Items) ? s.Items : [];
  }
  return items
    .map((it) => ({
      integrationId: String(it.integrationId || ''),
      deviceId: String(it.deviceId || ''),
      status: statusNorm(it.status, 'active'),
      scopes: normalizedIntegrationScopes(it.scopes, []),
      grantedBy: String(it.grantedBy || ''),
      createdAt: Number(it.createdAt || 0) || null,
      updatedAt: Number(it.updatedAt || 0) || null,
      expiresAt: Number(it.expiresAt || 0) || null,
    }))
    .filter((it) => !!it.integrationId);
}

async function listMembersByDevice(deviceId, stage = '') {
  if (!USER_DEVICES_TABLE) return [];
  const tableName = USER_DEVICES_TABLE;
  let items = [];
  try {
    const q = await ddb
      .query({
        TableName: tableName,
        IndexName: USER_DEVICES_BY_DEVICE_GSI,
        KeyConditionExpression: 'deviceId = :did',
        ExpressionAttributeValues: {
          ':did': deviceId,
        },
      })
      .promise();
    items = Array.isArray(q?.Items) ? q.Items : [];
  } catch (e) {
    logEvent('MEMBERS', {
      action: 'query_fallback_scan',
      table: tableName,
      index: USER_DEVICES_BY_DEVICE_GSI,
      deviceId,
      stage,
      errorCode: e?.code,
    });
    const s = await ddb
      .scan({
        TableName: tableName,
        FilterExpression: 'deviceId = :did',
        ExpressionAttributeValues: {
          ':did': deviceId,
        },
    })
    .promise();
    items = Array.isArray(s?.Items) ? s.Items : [];
  }
  let acceptedInviteEmailByUser = new Map();
  try {
    const invites = await listInvitesByDevice(deviceId, stage);
    acceptedInviteEmailByUser = new Map(
      invites
        .filter((it) => statusNorm(it?.status, 'pending') === 'accepted')
        .map((it) => [
          String(it.acceptedBy || ''),
          normalizeInviteeEmail(it.inviteeEmail || ''),
        ])
        .filter(([userSub, email]) => !!userSub && !!email),
    );
  } catch (_) {
    acceptedInviteEmailByUser = new Map();
  }
  return items
    .map((it) => ({
      userSub: String(it.userId || ''),
      email:
        normalizeInviteeEmail(it.userEmail || it.email || '') ||
        acceptedInviteEmailByUser.get(String(it.userId || '')) ||
        '',
      role: roleNorm(it.role, 'USER'),
      status: statusNorm(it.status, 'active'),
      invitedBy: String(it.invitedBy || ''),
      invitedAt: Number(it.invitedAt || 0) || null,
      acceptedAt: Number(it.acceptedAt || 0) || null,
      updatedAt: Number(it.updatedAt || 0) || null,
    }))
    .filter((it) => !!it.userSub);
}

async function listInvitesByDevice(deviceId, stage = '') {
  const tableName = requireTable('invites', INVITES_TABLE);
  let items = [];
  try {
    const q = await ddb
      .query({
        TableName: tableName,
        IndexName: INVITES_BY_DEVICE_GSI,
        KeyConditionExpression: 'deviceId = :did',
        ExpressionAttributeValues: {
          ':did': deviceId,
        },
      })
      .promise();
    items = Array.isArray(q?.Items) ? q.Items : [];
  } catch (e) {
    logEvent('INVITES', {
      action: 'query_fallback_scan',
      table: tableName,
      index: INVITES_BY_DEVICE_GSI,
      deviceId,
      stage,
      errorCode: e?.code,
    });
    const s = await ddb
      .scan({
        TableName: tableName,
        FilterExpression: 'deviceId = :did',
        ExpressionAttributeValues: {
          ':did': deviceId,
        },
      })
      .promise();
    items = Array.isArray(s?.Items) ? s.Items : [];
  }
  return items
    .map((it) => ({
      inviteId: String(it.inviteId || ''),
      role: roleNorm(it.role, 'USER'),
      status: statusNorm(it.status, 'pending'),
      inviterUserId: String(it.inviterUserId || ''),
      inviteeEmail: String(it.inviteeEmail || ''),
      createdAt: Number(it.createdAt || 0) || null,
      updatedAt: Number(it.updatedAt || 0) || null,
      expiresAt: inviteUsableUntilSec(it) || null,
      deleteAt: Number(it.expiresAt || 0) || null,
      acceptedBy: String(it.acceptedBy || ''),
      acceptedAt: Number(it.acceptedAt || 0) || null,
    }))
    .filter((it) => !!it.inviteId)
    .sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
}

function inviteClientPayload(it) {
  const inviteId = String(it?.inviteId || '');
  const deviceId = String(it?.deviceId || '');
  const role = roleNorm(it?.role, 'USER');
  const expiresAt = inviteUsableUntilSec(it) || null;
  const inviteeEmail = normalizeInviteeEmail(it?.inviteeEmail || it?.invitee_email || '');
  const inviteToken = pickInviteToken(it) || '';
  return {
    inviteId,
    deviceId,
    role,
    status: statusNorm(it?.status, 'pending'),
    createdAt: Number(it?.createdAt || 0) || null,
    updatedAt: Number(it?.updatedAt || 0) || null,
    expiresAt,
    inviteeEmail: inviteeEmail || undefined,
    inviteToken: inviteToken || undefined,
    inviteQr: {
      v: 1,
      t: 'device_invite',
      source: 'cloud',
      cloud: true,
      deviceId,
      inviteId,
      inviteeEmail: inviteeEmail || undefined,
      inviteToken: inviteToken || undefined,
      exp: expiresAt || undefined,
    },
    t: 'device_invite',
    source: 'cloud',
    cloud: true,
    id6: deviceId,
  };
}

async function listInvitesByInviteeEmail(inviteeEmail, stage = '') {
  const email = normalizeInviteeEmail(inviteeEmail || '');
  if (!email) return [];
  const tableName = requireTable('invites', INVITES_TABLE);
  const s = await ddb
    .scan({
      TableName: tableName,
      FilterExpression: 'inviteeEmail = :email',
      ExpressionAttributeValues: {
        ':email': email,
      },
    })
    .promise();
  const nowS = Math.floor(nowMs() / 1000);
  const items = Array.isArray(s?.Items) ? s.Items : [];
  return items
    .filter((it) => {
      const status = statusNorm(it?.status, 'pending');
      if (status !== 'pending' && status !== 'active') return false;
      const usableUntil = inviteUsableUntilSec(it);
      return usableUntil > 0 && nowS < usableUntil;
    })
    .map((it) => inviteClientPayload(it))
    .filter((it) => !!it.inviteId && !!it.deviceId)
    .sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
}

async function acceptInvite({ invite, id6, userSub, userEmail, stageDetected }) {
  const inviteId = String(invite.inviteId || '');
  const inviteDeviceId = String(invite.deviceId || '');
  const inviteStatus = statusNorm(invite.status, 'pending');
  const inviteeEmail = normalizeInviteeEmail(invite.inviteeEmail || invite.invitee_email || '');
  const actorEmail = normalizeInviteeEmail(userEmail || '');
  const usableUntil = inviteUsableUntilSec(invite);
  const now = nowMs();
  const nowS = Math.floor(now / 1000);
  if (!inviteId || !inviteDeviceId || inviteDeviceId !== id6) {
    return { ok: false, code: 400, err: 'invalid_invite' };
  }
  if (inviteStatus === 'revoked' || inviteStatus === 'deleted') {
    return { ok: false, code: 403, err: 'invite_revoked' };
  }
  if (usableUntil > 0 && nowS >= usableUntil) {
    return { ok: false, code: 403, err: 'invite_expired' };
  }
  if (inviteeEmail && actorEmail !== inviteeEmail) {
    return { ok: false, code: 403, err: 'invite_email_mismatch' };
  }
  if (!USER_DEVICES_TABLE) {
    return { ok: false, code: 500, err: 'user_devices_table_not_configured' };
  }
  const inviteToken = pickInviteToken(invite) || '';
  if (FEATURE_SIGNED_INVITES) {
    const verify = verifyInviteToken(inviteToken, {
      inviteId,
      deviceId: id6,
      role: invite.role,
      expiresAt: usableUntil,
    });
    if (!verify.ok) {
      return { ok: false, code: 403, err: verify.err || 'invite_token_invalid' };
    }
  }

  const role = roleNorm(invite.role, 'USER');
  try {
    await ddb
      .update({
        TableName: INVITES_TABLE,
        Key: { inviteId },
        UpdateExpression:
          'SET #st = :accepted, acceptedBy = :uid, acceptedAt = :now, updatedAt = :now',
        ConditionExpression:
          'attribute_exists(inviteId) AND (#st = :pending OR #st = :active OR (#st = :accepted AND acceptedBy = :uid))',
        ExpressionAttributeNames: {
          '#st': 'status',
        },
        ExpressionAttributeValues: {
          ':accepted': 'accepted',
          ':pending': 'pending',
          ':active': 'active',
          ':uid': userSub,
          ':now': now,
        },
      })
      .promise();
  } catch (e) {
    if (isConditionalCheckFailed(e)) {
      return { ok: false, code: 403, err: 'invite_already_used' };
    }
    throw e;
  }

  try {
    await ddb
      .put({
        TableName: USER_DEVICES_TABLE,
        Item: {
          userId: userSub,
          deviceId: id6,
          userEmail: actorEmail || undefined,
          role,
          status: 'active',
          invitedAt: Number(invite.createdAt || now),
          acceptedAt: now,
          updatedAt: now,
          invitedBy: String(invite.inviterUserId || ''),
          inviteId,
          // Optional: allows cloud-side revoke to also revoke local ACL via MQTT
          // (firmware uses userIdHash as stable local identity).
          userIdHash: invite?.userIdHash || invite?.user_id_hash || undefined,
        },
        ConditionExpression:
          'attribute_not_exists(userId) AND attribute_not_exists(deviceId)',
      })
      .promise();
  } catch (e) {
    if (isConditionalCheckFailed(e)) {
      const acceptedUserIdHash =
        invite?.userIdHash || invite?.user_id_hash || undefined;
      let updateExpression =
        'SET #st = :active, #role = :role, acceptedAt = :now, updatedAt = :now, inviteId = :inviteId';
      const expressionAttributeValues = {
        ':active': 'active',
        ':role': role,
        ':now': now,
        ':inviteId': inviteId,
      };
      if (actorEmail) {
        updateExpression += ', userEmail = :userEmail';
        expressionAttributeValues[':userEmail'] = actorEmail;
      }
      if (acceptedUserIdHash) {
        updateExpression += ', userIdHash = if_not_exists(userIdHash, :userIdHash)';
        expressionAttributeValues[':userIdHash'] = acceptedUserIdHash;
      }
      await ddb
        .update({
          TableName: USER_DEVICES_TABLE,
          Key: { userId: userSub, deviceId: id6 },
          UpdateExpression: updateExpression,
          ExpressionAttributeNames: {
            '#st': 'status',
            '#role': 'role',
          },
          ExpressionAttributeValues: expressionAttributeValues,
        })
        .promise();
    } else {
      throw e;
    }
  }

  await writeAudit('invite_accepted', {
    deviceId: id6,
    inviteId,
    userSub,
    role,
    stage: stageDetected,
  });
  return { ok: true, role };
}

async function revokeInvite(inviteId, revokedBy, now = nowMs()) {
  await ddb
    .update({
      TableName: INVITES_TABLE,
      Key: { inviteId },
      UpdateExpression:
        'SET #st = :revoked, revokedBy = :by, revokedAt = :now, updatedAt = :now',
      ConditionExpression: 'attribute_exists(inviteId)',
      ExpressionAttributeNames: {
        '#st': 'status',
      },
      ExpressionAttributeValues: {
        ':revoked': 'revoked',
        ':by': revokedBy,
        ':now': now,
      },
    })
    .promise();
}

async function revokeAllMembersForDevice(deviceId, revokedBy, stage = '') {
  const members = await listMembersByDevice(deviceId, stage);
  const now = nowMs();
  let count = 0;
  for (const m of members) {
    const target = String(m.userSub || '');
    if (!target) continue;
    try {
      await ddb
        .update({
          TableName: USER_DEVICES_TABLE,
          Key: { userId: target, deviceId },
          UpdateExpression:
            'SET #st = :revoked, revokedAt = :now, revokedBy = :by, updatedAt = :now',
          ConditionExpression:
            'attribute_exists(userId) AND attribute_exists(deviceId)',
          ExpressionAttributeNames: {
            '#st': 'status',
          },
          ExpressionAttributeValues: {
            ':revoked': 'revoked',
            ':now': now,
            ':by': revokedBy,
          },
        })
        .promise();
      count += 1;
    } catch (e) {
      logEvent('UNCLAIM', {
        action: 'member_revoke_failed',
        deviceId,
        targetUserSub: target,
        errorCode: e?.code,
        error: e?.message || e,
      });
    }
  }
  return count;
}

async function revokeAllInvitesForDevice(deviceId, revokedBy, stage = '') {
  const invites = await listInvitesByDevice(deviceId, stage);
  const revocable = invites.filter((it) => it.status === 'pending' || it.status === 'active');
  let count = 0;
  for (const inv of revocable) {
    const inviteId = String(inv.inviteId || '');
    if (!inviteId) continue;
    try {
      await revokeInvite(inviteId, revokedBy);
      count += 1;
    } catch (e) {
      logEvent('UNCLAIM', {
        action: 'invite_revoke_failed',
        deviceId,
        inviteId,
        errorCode: e?.code,
        error: e?.message || e,
      });
    }
  }
  return count;
}

async function fetchMemberLink(deviceId, userSub) {
  if (!USER_DEVICES_TABLE) return null;
  try {
    const out = await ddb
      .get({
        TableName: USER_DEVICES_TABLE,
        Key: { userId: userSub, deviceId },
      })
      .promise();
    return out?.Item || null;
  } catch (_) {
    return null;
  }
}

async function publishRevokeUserToDevice({
  id6,
  callerUserIdHash,
  targetUserIdHash,
  actorId = '',
  stage = '',
}) {
  if (!IOT_ENDPOINT) return { published: false };
  const targetHash = String(targetUserIdHash || '').trim().toLowerCase();
  const callerHash = String(callerUserIdHash || '').trim().toLowerCase();
  if (!/^[0-9a-f]{16,128}$/.test(targetHash)) return { published: false };
  if (!/^[0-9a-f]{16,128}$/.test(callerHash)) return { published: false };
  try {
    await iot
      .publish({
        topic: `aac/${id6}/cmd`,
        payload: JSON.stringify({
          type: 'REVOKE_USER',
          // MQTT auth on device uses userIdHash to resolve caller role.
          userIdHash: callerHash,
          // Separate target for the actual revoke operation.
          targetUserIdHash: targetHash,
          source: 'cloud',
          by: String(actorId || ''),
        }),
        qos: 0,
      })
      .promise();
    logEvent('IOT', {
      action: 'revoke_user_published',
      id6,
      callerUserIdHash: callerHash.slice(0, 8) + '...',
      targetUserIdHash: targetHash.slice(0, 8) + '...',
      stage,
    });
    return { published: true };
  } catch (e) {
    logEvent('IOT', {
      action: 'revoke_user_publish_failed',
      id6,
      errorCode: awsErrCode(e),
      error: e?.message || e,
      stage,
    });
    return { published: false };
  }
}

async function getOwnerUserIdHashForDevice(id6, stage = '') {
  try {
    const ownership = await fetchOwnership(id6, stage);
    const raw =
      ownership?.ownerUserIdHash ??
      ownership?.owner_user_id_hash ??
      ownership?.ownerKeyHash ??
      ownership?.owner_key_hash ??
      '';
    const s = String(raw || '').trim().toLowerCase();
    return /^[0-9a-f]{16,128}$/.test(s) ? s : '';
  } catch (_) {
    return '';
  }
}

async function resolveActorUserIdHash({
  id6,
  userSub,
  role = 'USER',
  body = null,
  stage = '',
}) {
  let actorUserIdHash = pickUserIdHash(body);
  if (actorUserIdHash) return actorUserIdHash;

  const memberLink = await fetchMemberLink(id6, userSub);
  actorUserIdHash = normalizeUserIdHashFromItem(memberLink);
  if (actorUserIdHash) return actorUserIdHash;

  if (String(role || '').toUpperCase() === 'OWNER') {
    actorUserIdHash = await getOwnerUserIdHashForDevice(id6, stage);
    if (actorUserIdHash) return actorUserIdHash;
  }
  return '';
}

async function backfillMemberUserIdHash({
  deviceId,
  userSub,
  membership = null,
  actorUserIdHash = '',
  role = 'USER',
  stage = '',
}) {
  if (!USER_DEVICES_TABLE) return false;
  const hash = normalizeHex(String(actorUserIdHash || ''));
  if (!/^[0-9a-f]{16,128}$/.test(hash)) return false;
  const existingHash = normalizeUserIdHashFromItem(membership);
  const hasHashAlready = existingHash.length > 0 && existingHash === hash;
  if (hasHashAlready) return false;

  const now = nowMs();
  const normalizedRole = roleNorm(role, 'USER');
  try {
    await ddb
      .update({
        TableName: USER_DEVICES_TABLE,
        Key: { userId: userSub, deviceId },
        UpdateExpression:
          'SET userIdHash = :hash, #st = if_not_exists(#st, :active), #role = if_not_exists(#role, :role), updatedAt = :now',
        ConditionExpression:
          'attribute_exists(userId) AND attribute_exists(deviceId)',
        ExpressionAttributeNames: {
          '#st': 'status',
          '#role': 'role',
        },
        ExpressionAttributeValues: {
          ':hash': hash,
          ':active': 'active',
          ':role': normalizedRole,
          ':now': now,
        },
      })
      .promise();

    logEvent('MEMBERS', {
      action: 'member_useridhash_backfilled',
      deviceId,
      userSub: maskSub(userSub),
      role: normalizedRole,
      stage,
    });
    return true;
  } catch (e) {
    logEvent('MEMBERS', {
      action: 'member_useridhash_backfill_failed',
      deviceId,
      userSub: maskSub(userSub),
      role: normalizedRole,
      stage,
      errorCode: e?.code,
      error: e?.message || e,
    });
    return false;
  }
}

async function listUserDeviceLinksRawByDevice(deviceId, stage = '') {
  if (!USER_DEVICES_TABLE) return [];
  const tableName = USER_DEVICES_TABLE;
  let items = [];
  try {
    const q = await ddb
      .query({
        TableName: tableName,
        IndexName: USER_DEVICES_BY_DEVICE_GSI,
        KeyConditionExpression: 'deviceId = :did',
        ExpressionAttributeValues: {
          ':did': deviceId,
        },
      })
      .promise();
    items = Array.isArray(q?.Items) ? q.Items : [];
  } catch (e) {
    logEvent('MEMBERS', {
      action: 'acl_query_fallback_scan',
      table: tableName,
      index: USER_DEVICES_BY_DEVICE_GSI,
      deviceId,
      stage,
      errorCode: e?.code,
    });
    const s = await ddb
      .scan({
        TableName: tableName,
        FilterExpression: 'deviceId = :did',
        ExpressionAttributeValues: {
          ':did': deviceId,
        },
      })
      .promise();
    items = Array.isArray(s?.Items) ? s.Items : [];
  }
  return items;
}

function normalizeUserIdHashFromItem(item) {
  const raw =
    item?.userIdHash ??
    item?.user_id_hash ??
    item?.userKeyHash ??
    item?.user_key_hash ??
    '';
  const s = String(raw || '').trim().toLowerCase();
  return /^[0-9a-f]{16,128}$/.test(s) ? s : '';
}

async function pushShadowAclDesiredState(deviceId, stage = '') {
  if (!FEATURE_SHADOW_ACL_SYNC) return { pushed: false, reason: 'disabled' };
  if (!IOT_ENDPOINT) return { pushed: false, reason: 'iot_endpoint_not_configured' };
  if (!USER_DEVICES_TABLE) return { pushed: false, reason: 'user_devices_table_not_configured' };

  try {
    const nowS = Math.floor(nowMs() / 1000);
    const rawLinks = await listUserDeviceLinksRawByDevice(deviceId, stage);
    const ownership = await fetchOwnership(deviceId, stage);
    const usersByHash = new Map();

    const upsertAclUser = (candidate) => {
      const userIdHash = normalizeUserIdHashFromItem(candidate);
      if (!userIdHash) return;
      const next = {
        userSub: String(candidate?.userSub || candidate?.userId || ''),
        userIdHash,
        status: statusNorm(candidate?.status, 'active'),
        role: roleNorm(candidate?.role, 'USER'),
      };
      const existing = usersByHash.get(userIdHash);
      if (!existing) {
        usersByHash.set(userIdHash, next);
        return;
      }
      const merged = { ...existing, ...next };
      if (existing.role !== 'OWNER' && next.role === 'OWNER') {
        merged.role = 'OWNER';
      }
      if (existing.status !== 'active' && next.status === 'active') {
        merged.status = 'active';
      }
      usersByHash.set(userIdHash, merged);
    };

    for (const it of rawLinks) {
      upsertAclUser({
        userId: String(it?.userId || it?.userSub || ''),
        userIdHash: it?.userIdHash || it?.user_id_hash || '',
        status: it?.status,
        role: it?.role,
      });
    }

    const ownerPrincipal = ownership?.ownerUserId || ownership?.ownerSub || '';
    if (ownerPrincipal) {
      upsertAclUser({
        userId: ownerPrincipal,
        userIdHash:
          ownership?.ownerUserIdHash ||
          ownership?.owner_user_id_hash ||
          ownership?.ownerKeyHash ||
          ownership?.owner_key_hash ||
          '',
        status: ownership?.status || 'active',
        role: 'OWNER',
      });
    }

    const users = Array.from(usersByHash.values()).sort((a, b) =>
      String(a.userIdHash || '').localeCompare(String(b.userIdHash || '')),
    );

    const thingName = thingNameFromId6(deviceId);
    const acl = {
      v: 1,
      version: nowS,
      users,
    };
    await iot
      .updateThingShadow({
        thingName,
        payload: JSON.stringify({
          state: {
            desired: {
              acl,
            },
          },
        }),
      })
      .promise();

    logEvent('SHADOW', {
      action: 'acl_desired_pushed',
      deviceId,
      thingName,
      version: nowS,
      userCount: users.length,
      stage,
    });
    await writeAudit('shadow_acl_push', {
      deviceId,
      version: nowS,
      userCount: users.length,
      payloadHash: payloadHash(acl),
    });
    return { pushed: true, version: nowS, userCount: users.length };
  } catch (e) {
    logEvent('SHADOW', {
      action: 'acl_desired_push_failed',
      deviceId,
      errorCode: awsErrCode(e),
      error: e?.message || e,
      stage,
    });
    return { pushed: false, reason: 'push_failed' };
  }
}

exports.handler = async (event) => {
  const method =
    event?.requestContext?.http?.method ||
    event?.httpMethod ||
    'GET';
  if (method === 'OPTIONS') return resp(204, {});

  const rawPath =
    event?.rawPath || event?.path || '';
  const stageDetected =
    event?.requestContext?.stage ||
    event?.requestContext?.http?.stage ||
    '';
  const routeKey =
    event?.requestContext?.routeKey || `${method} ${rawPath}`;
  const id6 =
    event?.pathParameters?.id6 ||
    event?.pathParameters?.deviceId ||
    '';

  const isHealth =
    routeMatches(method, rawPath, routeKey, 'GET /health', /^\/health\/?$/) ||
    routeMatches(method, rawPath, routeKey, 'GET /healthz', /^\/healthz\/?$/);
  if (isHealth) {
    return resp(200, {
      ok: true,
      service: 'aac-cloud-api',
      ts: nowMs(),
      config: {
        ownershipTable: !!OWNERSHIP_TABLE,
        stateTable: !!STATE_TABLE,
        userDevicesTable: !!USER_DEVICES_TABLE,
        invitesTable: !!INVITES_TABLE,
        signedInvites: FEATURE_SIGNED_INVITES,
        integrationLinksTable: !!INTEGRATION_LINKS_TABLE,
        auditTable: !!AUDIT_TABLE,
        idempotencyTable: !!CMD_IDEMPOTENCY_TABLE,
        rateLimitTable: !!RATE_LIMIT_TABLE,
        iotEndpoint: !!IOT_ENDPOINT,
        thingNamePrefix: THING_NAME_PREFIX,
        otaJobs: FEATURE_OTA_JOBS,
        thingArnPrefix: !!IOT_THING_ARN_PREFIX,
      },
    });
  }

  const claims = event?.requestContext?.authorizer?.jwt?.claims || {};
  const principalType = String(
    claims.principalType ||
      claims.principal_type ||
      'user',
  )
    .trim()
    .toLowerCase();
  const userSub = String(claims.sub || '').trim();
  const integrationId =
    principalType === 'integration'
      ? String(claims.integrationId || claims.integration_id || claims.client_id || claims.sub || '').trim()
      : '';
  if (principalType === 'integration' && !integrationId) {
    return resp(401, { error: 'unauthorized' });
  }
  if (principalType !== 'integration' && !userSub) {
    return resp(401, { error: 'unauthorized' });
  }
  const userEmail = claims.email || '';
  const actorId =
    principalType === 'integration'
      ? `integration:${integrationId}`
      : userSub;
  logEvent('REQ', {
    method,
    routeKey,
    path: rawPath,
    id6,
    userSub: actorId,
    principalType,
    integrationId,
    userEmail,
    stage: stageDetected,
  });

  try {
    if (routeMatches(method, rawPath, routeKey, 'GET /me', /^\/device\/me\/?$/) ||
        routeMatches(method, rawPath, routeKey, 'GET /me', /^\/me\/?$/)) {
      const devices = await listDevicesForUser(userSub, stageDetected);
      return resp(200, {
        ok: true,
        me: {
          sub: userSub,
          email: userEmail,
        },
        cloud: {
          state: cloudStateFromCounts(devices.length),
          deviceCount: devices.length,
          iotEndpoint: IOT_ENDPOINT || '',
          features: currentFeatureFlags(),
        },
      });
    }

    if (routeMatches(method, rawPath, routeKey, 'GET /devices', /^\/devices\/?$/)) {
      if (principalType === 'integration') return resp(403, { error: 'forbidden' });
      const devices = await listDevicesForUser(userSub, stageDetected);
      return resp(200, {
        ok: true,
        devices,
        count: devices.length,
        cloud: {
          state: cloudStateFromCounts(devices.length),
          iotEndpoint: IOT_ENDPOINT || '',
          features: currentFeatureFlags(),
        },
      });
    }

    if (routeMatches(method, rawPath, routeKey, 'GET /me/invites', /^\/me\/invites\/?$/)) {
      if (!FEATURE_INVITES) return resp(404, { error: 'not_found' });
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      const email = normalizeInviteeEmail(userEmail || '');
      if (!email) {
        return resp(200, {
          ok: true,
          invites: [],
          count: 0,
        });
      }
      const invites = await listInvitesByInviteeEmail(email, stageDetected);
      return resp(200, {
        ok: true,
        invites,
        count: invites.length,
      });
    }

    if (routeMatches(method, rawPath, routeKey, 'POST /device/{id6}/invite', /\/device\/[0-9]{6}\/invite\/?$/)) {
      if (!FEATURE_INVITES) return resp(404, { error: 'not_found' });
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      await requireOwner(id6, userSub, stageDetected);
      const tableName = requireTable('invites', INVITES_TABLE);
      const body = parseBody(event);
      const role = roleNorm(body?.role, 'USER');
      const inviteId = genInviteId();
      const now = nowMs();
      const nowSec = Math.floor(now / 1000);
      const validUntil = nowSec + INVITE_TTL_SEC_FIXED;
      const recordDeleteAt = nowSec + INVITE_RECORD_RETENTION_SEC;
      const inviterUserIdHash = pickUserIdHash(body);
      const inviteeEmail = normalizeInviteeEmail(
        body?.inviteeEmail ?? body?.invitee_email ?? body?.email ?? '',
      );

      // Best-effort: persist owner's local key hash on the ownership record so cloud can
      // later propagate ACL changes to the device via MQTT in an authenticated way.
      if (inviterUserIdHash) {
        try {
          const ownershipTable = requireTable('ownership', OWNERSHIP_TABLE);
          await ddb
            .update({
              TableName: ownershipTable,
              Key: { deviceId: id6 },
              UpdateExpression:
                'SET ownerUserIdHash = if_not_exists(ownerUserIdHash, :h), updatedAt = :now',
              ConditionExpression:
                // Some deployments store the owner identity under ownerSub instead of ownerUserId.
                // This is best-effort only; failure should not block invite creation.
                'attribute_exists(deviceId) AND (ownerUserId = :me OR ownerSub = :me)',
              ExpressionAttributeValues: {
                ':h': inviterUserIdHash,
                ':now': now,
                ':me': userSub,
              },
            })
            .promise();
        } catch (_) {
          // ignore: optional optimization only
        }
      }
      const invite = {
        inviteId,
        deviceId: id6,
        role,
        status: 'pending',
        inviterUserId: userSub,
        inviterUserIdHash: inviterUserIdHash || undefined,
        inviterEmail: userEmail || '',
        inviteeEmail: inviteeEmail || undefined,
        createdAt: now,
        updatedAt: now,
        // Invite usability window (10 minutes).
        validUntil,
        // DynamoDB TTL attribute (physical cleanup around 24h, async by AWS).
        expiresAt: recordDeleteAt,
      };
      await ddb
        .put({
          TableName: tableName,
          Item: invite,
          ConditionExpression: 'attribute_not_exists(inviteId)',
        })
        .promise();
      await writeAudit('invite_created', {
        deviceId: id6,
        inviteId,
        role,
        inviterUserId: userSub,
        inviteeEmail: inviteeEmail || undefined,
      });
      const inviteToken = buildInviteToken(invite);
      return resp(200, {
        ok: true,
        invite: {
          inviteId,
          deviceId: id6,
          role,
          expiresAt: validUntil,
          inviteeEmail: inviteeEmail || undefined,
          inviteToken: inviteToken || undefined,
          inviteQr: {
            v: 1,
            t: 'device_invite',
            source: 'cloud',
            cloud: true,
            deviceId: id6,
            inviteId,
            inviteeEmail: inviteeEmail || undefined,
            inviteToken: inviteToken || undefined,
            exp: validUntil,
          },
        },
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /device/{id6}/invite/{inviteId}/revoke',
      /\/device\/[0-9]{6}\/invite\/[^/]+\/revoke\/?$/,
    )) {
      if (!FEATURE_INVITES) return resp(404, { error: 'not_found' });
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      await requireOwner(id6, userSub, stageDetected);
      const inviteId =
        routeParamFromPath(rawPath, /\/device\/[0-9]{6}\/invite\/([^/]+)\/revoke\/?$/) ||
        String(parseBody(event)?.inviteId || '').trim();
      if (!inviteId) return resp(400, { err: 'invite_id_required' });
      const invite = await fetchInvite(inviteId);
      if (!invite) return resp(404, { err: 'invite_not_found' });
      if (String(invite.deviceId || '') !== id6) return resp(403, { err: 'forbidden' });
      await revokeInvite(inviteId, userSub);
      await writeAudit('invite_revoked', {
        deviceId: id6,
        inviteId,
        revokedBy: userSub,
      });
      return resp(200, {
        ok: true,
        inviteId,
        revoked: true,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /device/{id6}/claim/recover',
      /\/device\/[0-9]{6}\/claim\/recover\/?$/,
    )) {
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      const body = parseBody(event);
      const requestedPresentation = pickDevicePresentation(body);
      const confirmed = parseBoolean(
        body?.confirmRecovery ?? body?.confirm_recovery,
        false,
      );
      if (!confirmed) {
        return resp(400, { err: 'recovery_confirmation_required' });
      }
      const claimProof = pickClaimProof(body);
      const providedUserIdHash = resolveOwnerUserIdHash(body);
      const recovered = await recoverOwnershipForDevice({
        id6,
        userSub,
        claimProof,
        userIdHash: providedUserIdHash,
        deviceBrand: requestedPresentation.brand,
        deviceSuffix: requestedPresentation.suffix,
        stageDetected,
      });
      if (!recovered.ok) {
        return resp(recovered.code || 400, {
          err: recovered.err || 'ownership_recovery_failed',
        });
      }
      await pushShadowAclDesiredState(id6, stageDetected);
      return resp(200, {
        ok: true,
        deviceId: id6,
        linked: true,
        role: 'OWNER',
        recovered: true,
        previousOwner: recovered.previousOwner || '',
        previousStatus: recovered.previousStatus || '',
        membersRevoked: recovered.membersRevoked || 0,
        invitesRevoked: recovered.invitesRevoked || 0,
        hashSource: recovered.liveClaimHashSource || 'state',
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /device/{id6}/name',
      /\/device\/[0-9]{6}\/name\/?$/,
    )) {
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      await requireOwner(id6, userSub, stageDetected);
      const body = parseBody(event);
      const requestedPresentation = pickDevicePresentation(body);
      if (!requestedPresentation.brand) {
        return resp(400, { err: 'device_brand_required' });
      }
      const ownershipTable = requireTable('ownership', OWNERSHIP_TABLE);
      const now = nowMs();
      await ddb
        .update({
          TableName: ownershipTable,
          Key: { deviceId: id6 },
          UpdateExpression:
            'SET deviceBrand = :brand, deviceSuffix = :suffix, deviceDisplayName = :displayName, updatedAt = :now',
          ConditionExpression:
            'attribute_exists(deviceId) AND (ownerUserId = :me OR ownerSub = :me)',
          ExpressionAttributeValues: {
            ':brand': requestedPresentation.brand,
            ':suffix': requestedPresentation.suffix,
            ':displayName': requestedPresentation.displayName,
            ':now': now,
            ':me': userSub,
          },
        })
        .promise();
      await writeAudit('device_name_updated', {
        deviceId: id6,
        userSub,
        brand: requestedPresentation.brand,
        suffix: requestedPresentation.suffix,
        displayName: requestedPresentation.displayName,
      });
      return resp(200, {
        ok: true,
        deviceId: id6,
        brand: requestedPresentation.brand,
        suffix: requestedPresentation.suffix,
        displayName: requestedPresentation.displayName,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /device/{id6}/claim-proof/sync',
      /\/device\/[0-9]{6}\/claim-proof\/sync\/?$/,
    )) {
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      const now = nowMs();
      const rate = FEATURE_RATE_LIMIT
        ? await enforceClaimProofSyncRateLimit(id6, userSub, now)
        : {
          enforced: false,
          limited: false,
          count: 0,
          max: CLAIM_PROOF_SYNC_RATE_LIMIT_MAX,
          windowSec: CLAIM_PROOF_SYNC_RATE_LIMIT_WINDOW_SEC,
          retryAfterSec: 0,
        };
      if (rate.limited) {
        await writeAudit('claim_proof_sync_rate_limited', {
          deviceId: id6,
          userSub,
          requestCount: rate.count,
          max: rate.max,
          windowSec: rate.windowSec,
          retryAfterSec: rate.retryAfterSec,
        });
        return resp(429, {
          error: 'rate_limited',
          retryAfterSec: rate.retryAfterSec,
        }, {
          'Retry-After': String(rate.retryAfterSec),
          'X-RateLimit-Limit': String(rate.max),
          'X-RateLimit-Window': String(rate.windowSec),
        });
      }
      const body = parseBody(event);
      const claimProof = pickClaimProof(body);
      const providedUserIdHash = resolveOwnerUserIdHash(body);
      const synced = await syncClaimProofForDevice({
        id6,
        userSub,
        claimProof,
        stageDetected,
      });
      if (!synced.ok) {
        return resp(synced.code || 400, { err: synced.err || 'claim_proof_sync_failed' });
      }
      return resp(200, {
        ok: true,
        deviceId: id6,
        claimProofSynced: true,
        hashSource: synced.hashSource || 'provided',
      });
    }

    if (routeKey === 'POST /device/{id6}/claim') {
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      const now = Date.now();
      const ownershipTable = requireTable('ownership', OWNERSHIP_TABLE);
      const userDevicesTable = USER_DEVICES_TABLE;
      const body = parseBody(event);
      const claimProof = pickClaimProof(body);
      const providedUserIdHash = resolveOwnerUserIdHash(body);
      const requestedPresentation = pickDevicePresentation(body);
      logEvent('CLAIM', {
        action: 'start',
        id6,
        userSub,
        userEmail,
        table: ownershipTable,
        hasProof: claimProof.length > 0,
        stage: stageDetected,
      });
      const deviceRecord = await ddb
        .get({
          TableName: ownershipTable,
          Key: { deviceId: id6 },
        })
        .promise();
      if (!deviceRecord?.Item) {
        if (FEATURE_CLAIM_AUTO_BOOTSTRAP) {
          const boot = await bootstrapClaimOwnership({
            id6,
            userSub,
            now,
            claimProof,
            userIdHash: providedUserIdHash,
            deviceBrand: requestedPresentation.brand,
            deviceSuffix: requestedPresentation.suffix,
            stageDetected,
          });
          if (!boot.ok) {
            if (boot.code === 409) {
              return resp(409, { err: 'claim_race_retry' });
            }
            return resp(boot.code || 500, { err: boot.err || 'claim_bootstrap_failed' });
          }
          await pushShadowAclDesiredState(id6, stageDetected);
          return resp(200, {
            ok: true,
            linked: true,
            role: 'OWNER',
            deviceId: id6,
            bootstrapped: true,
            proofValidated: !!claimProof,
            debug: {
              ownerSub: maskSub(userSub),
              stageDetected,
            },
          });
        }
        logEvent('CLAIM', {
          action: 'device_missing',
          id6,
          table: ownershipTable,
        });
        return resp(404, { err: 'device_not_found' });
      }
      if (body && body.inviteId) {
        if (!FEATURE_INVITES) return resp(404, { error: 'not_found' });
        const inviteId = String(body.inviteId).trim();
        if (!inviteId) return resp(400, { err: 'invalid_invite' });
        const invite = await fetchInvite(inviteId);
        if (!invite) return resp(404, { err: 'invite_not_found' });
        const userIdHash = pickUserIdHash(body);
        const accepted = await acceptInvite({
          invite: {
            ...invite,
            inviteToken: pickInviteToken(body),
            userIdHash: userIdHash || undefined,
          },
          id6,
          userSub,
          userEmail,
          stageDetected,
        });
        if (!accepted.ok) {
          return resp(accepted.code || 400, { err: accepted.err || 'invite_failed' });
        }
        // Best-effort: push updated ACL to device shadow (eventual revoke/consistency).
        await pushShadowAclDesiredState(id6, stageDetected);
        return resp(200, {
          ok: true,
          linked: true,
          role: accepted.role,
          deviceId: id6,
          invited: true,
        });
      }
      const currentOwner = (deviceRecord.Item.ownerUserId || deviceRecord.Item.ownerSub || '').toString();
      const currentStatus = statusNorm(deviceRecord.Item.status, 'active');
      let expectedClaimHash = getClaimSecretHash(deviceRecord.Item);
      let expectedClaimHashSource = 'ownership';
      if (!expectedClaimHash) {
        const resolved = await resolveClaimHashFromState(id6, stageDetected);
        if (resolved.hash) {
          expectedClaimHash = resolved.hash;
          expectedClaimHashSource = resolved.source || 'state';
        }
      }
      const hasStoredProof = expectedClaimHash.length === 64;
      const providedClaimHash = claimProof ? normalizeHex64(sha256Hex(claimProof)) : '';
      const proofMatchesStored =
        hasStoredProof && providedClaimHash && safeEqualHex(providedClaimHash, expectedClaimHash);
      const isCurrentOwner = currentOwner && currentOwner === userSub && currentStatus !== 'deleted';
      const canRotateProof =
        !!providedClaimHash && (!currentOwner || currentStatus === 'deleted');
      const proofValid = !!proofMatchesStored || !!canRotateProof;
      if (!proofValid && !isCurrentOwner) {
        if ((FEATURE_CLAIM_PROOF && CLAIM_PROOF_REQUIRED) || hasStoredProof) {
          const errCode = hasStoredProof
            ? 'claim_proof_required'
            : 'claim_proof_not_initialized';
          await writeAudit('claim_denied', {
            deviceId: id6,
            userSub,
            reason: errCode,
            hasStoredProof,
          });
          logEvent('CLAIM', {
            action: 'proof_failed',
            id6,
            userSub,
            hasStoredProof,
            expectedClaimHashSource,
            hasProof: claimProof.length > 0,
            canRotateProof,
            err: errCode,
            stage: stageDetected,
          });
          return resp(403, {
            err: errCode,
            hasStoredProof,
            proofInitRequired: !hasStoredProof,
          });
        }
        logEvent('CLAIM', {
          action: 'proof_skipped_legacy_mode',
          id6,
          userSub,
          hasStoredProof,
          stage: stageDetected,
        });
      }

      try {
        let updateExpression =
          'SET ownerUserId = :me, ' +
          'ownerSub = :me, ' +
          'claimedAt = :now, ' +
          '#st = :active, ' +
          'lastClaimedBy = :me, ' +
          'lastClaimedAt = :now, ' +
          'createdAt = if_not_exists(createdAt, :now)';
        const exprValues = {
          ':me': userSub,
          ':now': now,
          ':active': 'active',
          ':deleted': 'deleted',
        };
        const exprNames = {
          '#st': 'status',
        };
        if (providedUserIdHash) {
          updateExpression += ', ownerUserIdHash = if_not_exists(ownerUserIdHash, :userIdHash)';
          exprValues[':userIdHash'] = providedUserIdHash;
        }
        if (requestedPresentation.brand) {
          updateExpression += ', deviceBrand = :deviceBrand';
          exprValues[':deviceBrand'] = requestedPresentation.brand;
        }
        updateExpression += ', deviceSuffix = :deviceSuffix';
        exprValues[':deviceSuffix'] = requestedPresentation.suffix;
        if (requestedPresentation.displayName) {
          updateExpression += ', deviceDisplayName = :deviceDisplayName';
          exprValues[':deviceDisplayName'] = requestedPresentation.displayName;
        }
        const claimHashToPersist = proofValid ? providedClaimHash : '';
        if (claimHashToPersist) {
          updateExpression += ', claimSecretHash = :claimHash';
          exprValues[':claimHash'] = claimHashToPersist;
        }
        await ddb
          .update({
            TableName: ownershipTable,
            Key: { deviceId: id6 },
            UpdateExpression: updateExpression,
            ConditionExpression:
              'attribute_exists(deviceId) AND (attribute_not_exists(ownerUserId) OR ownerUserId = :me OR #st = :deleted)',
            ExpressionAttributeNames: exprNames,
            ExpressionAttributeValues: exprValues,
          })
          .promise();
        logEvent('CLAIM', {
          action: currentStatus === 'deleted' ? 'reclaimed_deleted' : 'claimed_active',
          id6,
          userSub,
          previousOwner: currentOwner || '',
          previousStatus: currentStatus,
          stage: stageDetected,
        });
      } catch (e) {
        if (isConditionalCheckFailed(e)) {
          logEvent('CLAIM', {
            action: 'owner_conflict',
            id6,
            userSub,
            table: ownershipTable,
            stage: stageDetected,
            errorCode: awsErrCode(e),
            error: e.message,
          });
          return resp(403, { err: 'already_claimed' });
        }
        logEvent('CLAIM', {
          action: 'device_update_error',
          id6,
          errorCode: awsErrCode(e),
          error: e?.message || e,
          table: ownershipTable,
          stage: stageDetected,
        });
        throw e;
      }
      if (userDevicesTable) {
        const userDevicesKey = { userId: userSub, deviceId: id6 };
        try {
          await ddb
            .put({
              TableName: userDevicesTable,
              Item: {
                userId: userSub,
                deviceId: id6,
                role: 'OWNER',
                status: 'active',
                claimedAt: now,
                updatedAt: now,
                userIdHash: providedUserIdHash || undefined,
              },
              ConditionExpression:
                'attribute_not_exists(userId) AND attribute_not_exists(deviceId)',
            })
            .promise();
          logEvent('CLAIM', {
            action: 'user_device_linked',
            table: userDevicesTable,
            key: userDevicesKey,
            stage: stageDetected,
          });
        } catch (e) {
          if (isConditionalCheckFailed(e)) {
            const exprNames = {
              '#st': 'status',
              '#role': 'role',
            };
            const exprValues = {
              ':active': 'active',
              ':owner': 'OWNER',
              ':now': now,
            };
            let updateExpression =
              'SET #st = :active, #role = :owner, updatedAt = :now';
            if (providedUserIdHash) {
              updateExpression += ', userIdHash = if_not_exists(userIdHash, :userIdHash)';
              exprValues[':userIdHash'] = providedUserIdHash;
            }
            await ddb
              .update({
                TableName: userDevicesTable,
                Key: userDevicesKey,
                UpdateExpression: updateExpression,
                ExpressionAttributeNames: exprNames,
                ExpressionAttributeValues: exprValues,
              })
              .promise();
            logEvent('CLAIM', {
              action: 'user_device_exists',
              table: userDevicesTable,
              key: userDevicesKey,
              stage: stageDetected,
            });
          } else {
            logEvent('CLAIM', {
              action: 'user_device_error',
              table: userDevicesTable,
              key: userDevicesKey,
              errorCode: awsErrCode(e),
              error: e?.message || e,
              stage: stageDetected,
            });
            throw e;
          }
        }
      }

      await pushShadowAclDesiredState(id6, stageDetected);
      return resp(200, {
        ok: true,
        linked: true,
        role: 'OWNER',
        deviceId: id6,
        proofValidated: proofValid || isCurrentOwner,
        debug: {
          ownerSub: maskSub(userSub),
          stageDetected,
        },
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /device/{id6}/member/{userSub}/revoke',
      /\/device\/[0-9]{6}\/member\/[^/]+\/revoke\/?$/,
    )) {
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      await requireOwner(id6, userSub, stageDetected);
      if (!USER_DEVICES_TABLE) {
        return resp(500, { err: 'user_devices_table_not_configured' });
      }
      const targetUserSub =
        routeParamFromPath(rawPath, /\/device\/[0-9]{6}\/member\/([^/]+)\/revoke\/?$/) ||
        String(parseBody(event)?.userSub || '').trim();
      if (!targetUserSub) return resp(400, { err: 'target_user_required' });
      if (targetUserSub === userSub) return resp(400, { err: 'cannot_revoke_self' });
      const now = nowMs();

      // Read member link first to optionally propagate revoke to the device.
      const memberLink = await fetchMemberLink(id6, targetUserSub);
      await ddb
        .update({
          TableName: USER_DEVICES_TABLE,
          Key: { userId: targetUserSub, deviceId: id6 },
          UpdateExpression:
            'SET #st = :revoked, revokedAt = :now, revokedBy = :by, updatedAt = :now',
          ConditionExpression:
            'attribute_exists(userId) AND attribute_exists(deviceId)',
          ExpressionAttributeNames: {
            '#st': 'status',
          },
          ExpressionAttributeValues: {
            ':revoked': 'revoked',
            ':now': now,
            ':by': userSub,
          },
        })
        .promise();

      const memberUserIdHash =
        memberLink && typeof memberLink === 'object'
          ? String(memberLink.userIdHash || memberLink.user_id_hash || '').trim().toLowerCase()
          : '';
      const ownerUserIdHash = await getOwnerUserIdHashForDevice(id6, stageDetected);
      const pub =
        ownerUserIdHash && memberUserIdHash
          ? await publishRevokeUserToDevice({
              id6,
              callerUserIdHash: ownerUserIdHash,
              targetUserIdHash: memberUserIdHash,
              actorId,
              stage: stageDetected,
            })
          : { published: false };
      await writeAudit('member_revoked', {
        deviceId: id6,
        targetUserSub,
        revokedBy: userSub,
        propagatedToDevice: !!pub.published,
      });
      // Best-effort: update shadow ACL so the revoke is eventually enforced
      // even if the device was offline when the MQTT command was published.
      await pushShadowAclDesiredState(id6, stageDetected);
      return resp(200, {
        ok: true,
        deviceId: id6,
        userSub: targetUserSub,
        revoked: true,
        propagatedToDevice: !!pub.published,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /device/{id6}/unclaim',
      /\/device\/[0-9]{6}\/unclaim\/?$/,
    )) {
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      const ownerMembership = await requireOwner(id6, userSub, stageDetected);
      const ownerSub = String(ownerMembership.ownerUserId || userSub);
      const now = nowMs();
      const ownershipTable = requireTable('ownership', OWNERSHIP_TABLE);
      await ddb
        .update({
          TableName: ownershipTable,
          Key: { deviceId: id6 },
          UpdateExpression:
            'SET #st = :deleted, deletedAt = :now, unclaimedBy = :by, updatedAt = :now REMOVE ownerUserId, ownerSub',
          ConditionExpression:
            'attribute_exists(deviceId) AND (ownerUserId = :owner OR ownerSub = :owner)',
          ExpressionAttributeNames: {
            '#st': 'status',
          },
          ExpressionAttributeValues: {
            ':deleted': 'deleted',
            ':now': now,
            ':by': userSub,
            ':owner': ownerSub,
          },
        })
        .promise();

      let membersRevoked = 0;
      let invitesRevoked = 0;
      if (USER_DEVICES_TABLE) {
        membersRevoked = await revokeAllMembersForDevice(id6, userSub, stageDetected);
      }
      if (INVITES_TABLE) {
        invitesRevoked = await revokeAllInvitesForDevice(id6, userSub, stageDetected);
      }

      await writeAudit('device_unclaimed', {
        deviceId: id6,
        unclaimedBy: userSub,
        membersRevoked,
        invitesRevoked,
      });
      // Best-effort: push shadow ACL after mass revoke/unclaim.
      await pushShadowAclDesiredState(id6, stageDetected);
      return resp(200, {
        ok: true,
        deviceId: id6,
        unclaimed: true,
        membersRevoked,
        invitesRevoked,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'GET /device/{id6}/members',
      /\/device\/[0-9]{6}\/members\/?$/,
    )) {
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      const ownerMembership = await requireOwner(id6, userSub, stageDetected);
      const ownerSub = String(ownerMembership.ownerUserId || userSub);
      const members = await listMembersByDevice(id6, stageDetected);
      if (!members.some((m) => m.userSub === ownerSub)) {
        members.unshift({
          userSub: ownerSub,
          role: 'OWNER',
          status: 'active',
          invitedBy: '',
          invitedAt: null,
          acceptedAt: null,
          updatedAt: null,
        });
      }
      return resp(200, {
        ok: true,
        deviceId: id6,
        members,
        count: members.length,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /device/{id6}/acl/push',
      /\/device\/[0-9]{6}\/acl\/push\/?$/,
    )) {
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      await requireOwner(id6, userSub, stageDetected);
      const out = await pushShadowAclDesiredState(id6, stageDetected);
      return resp(out?.pushed ? 200 : 500, {
        ok: !!out?.pushed,
        deviceId: id6,
        pushed: !!out?.pushed,
        version: out?.version || null,
        userCount: out?.userCount || 0,
        reason: out?.reason || undefined,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'GET /device/{id6}/invites',
      /\/device\/[0-9]{6}\/invites\/?$/,
    )) {
      if (!FEATURE_INVITES) return resp(404, { error: 'not_found' });
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      await requireOwner(id6, userSub, stageDetected);
      const nowS = Math.floor(nowMs() / 1000);
      const invites = (await listInvitesByDevice(id6, stageDetected)).filter((it) => {
        const status = statusNorm(it?.status, 'pending');
        if (status !== 'pending' && status !== 'active') return false;
        const exp = Number(it?.expiresAt || 0);
        if (!Number.isFinite(exp) || exp <= 0) return false;
        return nowS < exp;
      });
      return resp(200, {
        ok: true,
        deviceId: id6,
        invites,
        count: invites.length,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /device/{id6}/integration/link',
      /\/device\/[0-9]{6}\/integration\/link\/?$/,
    )) {
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      await requireOwner(id6, userSub, stageDetected);
      const tableName = requireTable('integration_links', INTEGRATION_LINKS_TABLE);
      const body = parseBody(event);
      const integrationIdRaw = String(body?.integrationId || body?.integration_id || '').trim();
      if (!/^[a-zA-Z0-9._:-]{3,128}$/.test(integrationIdRaw)) {
        return resp(400, { err: 'invalid_integration_id' });
      }
      const scopes = normalizedIntegrationScopes(
        body?.scopes ?? body?.scope,
        [INTEGRATION_SCOPE_READ],
      );
      const ttlSec = parseTtlSec(body?.ttl ?? body?.ttlSec, 30 * 24 * 3600, 300, 365 * 24 * 3600);
      const now = nowMs();
      const expiresAt = Math.floor(now / 1000) + ttlSec;
      await ddb
        .put({
          TableName: tableName,
          Item: {
            integrationId: integrationIdRaw,
            deviceId: id6,
            status: 'active',
            scopes,
            grantedBy: userSub,
            createdAt: now,
            updatedAt: now,
            expiresAt,
          },
        })
        .promise();
      await writeAudit('integration_link_upserted', {
        deviceId: id6,
        integrationId: integrationIdRaw,
        userSub,
        scopes,
        expiresAt,
      });
      return resp(200, {
        ok: true,
        deviceId: id6,
        integrationId: integrationIdRaw,
        scopes,
        expiresAt,
        linked: true,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'GET /device/{id6}/integrations',
      /\/device\/[0-9]{6}\/integrations\/?$/,
    )) {
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      await requireOwner(id6, userSub, stageDetected);
      const integrations = await listIntegrationLinksByDevice(id6, stageDetected);
      return resp(200, {
        ok: true,
        deviceId: id6,
        integrations,
        count: integrations.length,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /device/{id6}/integration/{integrationId}/revoke',
      /\/device\/[0-9]{6}\/integration\/[^/]+\/revoke\/?$/,
    )) {
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      await requireOwner(id6, userSub, stageDetected);
      const integrationIdToRevoke =
        routeParamFromPath(rawPath, /\/device\/[0-9]{6}\/integration\/([^/]+)\/revoke\/?$/) ||
        String(parseBody(event)?.integrationId || '').trim();
      if (!integrationIdToRevoke) return resp(400, { err: 'integration_id_required' });
      const tableName = requireTable('integration_links', INTEGRATION_LINKS_TABLE);
      const now = nowMs();
      await ddb
        .update({
          TableName: tableName,
          Key: { integrationId: integrationIdToRevoke, deviceId: id6 },
          UpdateExpression:
            'SET #st = :revoked, revokedBy = :by, revokedAt = :now, updatedAt = :now',
          ConditionExpression:
            'attribute_exists(integrationId) AND attribute_exists(deviceId)',
          ExpressionAttributeNames: {
            '#st': 'status',
          },
          ExpressionAttributeValues: {
            ':revoked': 'revoked',
            ':by': userSub,
            ':now': now,
          },
        })
        .promise();
      await writeAudit('integration_link_revoked', {
        deviceId: id6,
        integrationId: integrationIdToRevoke,
        revokedBy: userSub,
      });
      return resp(200, {
        ok: true,
        deviceId: id6,
        integrationId: integrationIdToRevoke,
        revoked: true,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /ota/campaign',
      /\/ota\/campaign\/?$/,
    )) {
      if (!FEATURE_OTA_JOBS) return resp(404, { error: 'not_found' });
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      const body = parseBody(event);
      if (!isPlainObject(body)) return resp(400, { error: 'bad_body' });

      const firmwareUrlRaw = String(
        body.firmwareUrl ?? body.url ?? body.artifactUrl ?? '',
      ).trim();
      const sha256 = normalizeHex64(body.sha256 ?? body.sha256Hex ?? '');
      const version = String(body.version ?? '').trim();
      const minVersion = String(body.minVersion ?? '').trim();
      const dryRun = parseBoolean(body.dryRun, false);
      const requiresUserApproval = parseBoolean(
        body.requiresUserApproval ?? body.requireUserApproval ?? body.userApprovalRequired,
        true,
      );
      if (!firmwareUrlRaw || !sha256 || !version) {
        return resp(400, {
          error: 'bad_body',
          required: ['firmwareUrl', 'sha256', 'version'],
        });
      }
      if (!/^https:\/\//i.test(firmwareUrlRaw)) {
        return resp(400, { error: 'firmware_url_must_be_https' });
      }
      const firmwareUrl = await ensureSignedFirmwareUrl(firmwareUrlRaw);

      const includeDeviceIds = normalizeDeviceIdList(
        body.includeDeviceIds ?? body.includeDevices ?? body.deviceIds ?? '',
      );
      const excludeDeviceIds = normalizeDeviceIdList(
        body.excludeDeviceIds ?? body.excludeDevices ?? '',
      );
      const rolloutPercent = normalizeOtaRolloutPercent(
        body?.rollout?.percent ?? body.rolloutPercent ?? 100,
      );
      const rolloutMaxDevices = parsePositiveInt(
        body?.rollout?.maxDevices ?? body.rolloutMaxDevices,
        { min: 1, max: 5000 },
      );
      const reqTarget = pickOtaTargetFromRequest(body);
      const targetKeys = ['product', 'hwRev', 'boardRev', 'fwChannel'];
      const hasTargetFilter = targetKeys.some((k) => !!reqTarget[k]);
      const rolloutSeed = String(
        body?.rollout?.seed ??
        body.rolloutSeed ??
        `${version}:${sha256}`,
      );

      const devices = await listDevicesForUser(userSub, stageDetected);
      const ownedDeviceIds = devices
        .filter((d) => roleNorm(d?.role, 'USER') === 'OWNER')
        .map((d) => String(d?.deviceId || ''))
        .filter((id) => /^[0-9]{6}$/.test(id));
      const ownedSet = new Set(ownedDeviceIds);
      const excludedSet = new Set(excludeDeviceIds);
      const candidateIds = (includeDeviceIds.length ? includeDeviceIds : ownedDeviceIds)
        .filter((id) => ownedSet.has(id) && !excludedSet.has(id))
        .sort((a, b) => a.localeCompare(b));

      if (!candidateIds.length) {
        return resp(400, {
          error: 'ota_no_eligible_devices',
          eligibleOwnedCount: ownedDeviceIds.length,
        });
      }

      const evaluated = await Promise.all(
        candidateIds.map(async (deviceId) => {
          const stateTarget = hasTargetFilter
            ? pickOtaTargetFromState(
              (await loadStateObjectForIntegrations(deviceId, stageDetected)).stateObj,
            )
            : null;
          if (hasTargetFilter && !otaTargetMatchesFilter(stateTarget, reqTarget)) {
            return null;
          }
          if (!matchesRollout(rolloutSeed, deviceId, rolloutPercent)) {
            return null;
          }
          return {
            deviceId,
            stateTarget,
          };
        }),
      );
      let selected = evaluated.filter((v) => !!v);
      if (rolloutMaxDevices && selected.length > rolloutMaxDevices) {
        selected = selected.slice(0, rolloutMaxDevices);
      }

      const selectedDeviceIds = selected.map((v) => String(v.deviceId));
      if (!selectedDeviceIds.length) {
        return resp(400, {
          error: 'ota_no_matching_devices',
          eligibleOwnedCount: ownedDeviceIds.length,
          candidateCount: candidateIds.length,
          rolloutPercent,
          targetFilterApplied: hasTargetFilter,
        });
      }
      const selectedTargets = Array.from(new Set(
        (await Promise.all(
          selectedDeviceIds.map(async (d) => {
            const resolved = await resolveExistingThingArnsForId6(d, stageDetected);
            return resolved.length ? resolved : thingArnCandidatesFromId6(d);
          }),
        )).flat(),
      ));
      if (!selectedTargets.length) {
        return resp(500, { error: 'iot_thing_arn_not_configured' });
      }

      const sampleStateTargetRaw = selected.length ? selected[0].stateTarget : null;
      const sampleStateTarget = isPlainObject(sampleStateTargetRaw)
        ? sampleStateTargetRaw
        : { product: '', hwRev: '', boardRev: '', fwChannel: '' };
      const resolvedTarget = {
        product: reqTarget.product || sampleStateTarget.product,
        hwRev: reqTarget.hwRev || sampleStateTarget.hwRev,
        boardRev: reqTarget.boardRev || sampleStateTarget.boardRev,
        fwChannel: reqTarget.fwChannel || sampleStateTarget.fwChannel,
      };
      const requestedJobId = String(body.jobId ?? '').trim();
      const jobId = /^[a-zA-Z0-9_-]{1,64}$/.test(requestedJobId)
        ? requestedJobId
        : genOtaCampaignJobId();
      const jobDocument = {
        schemaVersion: '1',
        operation: 'OTA',
        firmware: {
          url: firmwareUrl,
          sha256,
          version,
          minVersion: minVersion || undefined,
          requiresUserApproval,
          target: resolvedTarget,
        },
        campaign: {
          scope: 'fleet',
          ownerUserId: userSub,
          rolloutPercent,
          rolloutSeed,
        },
      };

      if (dryRun) {
        return resp(200, {
          ok: true,
          dryRun: true,
          jobId,
          eligibleOwnedCount: ownedDeviceIds.length,
          candidateCount: candidateIds.length,
          selectedCount: selectedDeviceIds.length,
          selectedDeviceIds,
          targetSelection: OTA_JOB_TARGET_SELECTION,
          targets: selectedTargets,
          requiresUserApproval,
          jobDocument,
        });
      }

      await createIotJobWithMissingThingRetry({
        jobId,
        targets: selectedTargets,
        document: JSON.stringify(jobDocument),
        targetSelection: OTA_JOB_TARGET_SELECTION,
        description: `OTA campaign ${version} (${selectedDeviceIds.length} devices)`,
        stage: stageDetected,
      });
      await writeAudit('ota_campaign_created', {
        userSub,
        jobId,
        version,
        minVersion: minVersion || '',
        sha256,
        rolloutPercent,
        rolloutSeed,
        eligibleOwnedCount: ownedDeviceIds.length,
        candidateCount: candidateIds.length,
        selectedCount: selectedDeviceIds.length,
        selectedDeviceIds,
        payloadHash: payloadHash(jobDocument),
      });
      return resp(200, {
        ok: true,
        campaign: true,
        jobId,
        created: true,
        eligibleOwnedCount: ownedDeviceIds.length,
        candidateCount: candidateIds.length,
        selectedCount: selectedDeviceIds.length,
        selectedDeviceIds,
        targetSelection: OTA_JOB_TARGET_SELECTION,
        requiresUserApproval,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /device/{id6}/ota/job',
      /\/device\/[0-9]{6}\/ota\/job\/?$/,
    )) {
      if (!FEATURE_OTA_JOBS) return resp(404, { error: 'not_found' });
      if (principalType !== 'user') return resp(403, { error: 'forbidden' });
      requireId6(id6);
      await requireOwner(id6, userSub, stageDetected);
      const body = parseBody(event);
      if (!isPlainObject(body)) return resp(400, { error: 'bad_body' });

      const firmwareUrlRaw = String(
        body.firmwareUrl ?? body.url ?? body.artifactUrl ?? '',
      ).trim();
      const sha256 = normalizeHex64(body.sha256 ?? body.sha256Hex ?? '');
      const version = String(body.version ?? '').trim();
      const minVersion = String(body.minVersion ?? '').trim();
      const dryRun = parseBoolean(body.dryRun, false);
      const requiresUserApproval = parseBoolean(
        body.requiresUserApproval ?? body.requireUserApproval ?? body.userApprovalRequired,
        true,
      );
      const resolvedThingArns = await resolveExistingThingArnsForId6(id6, stageDetected);
      const thingArns = resolvedThingArns.length ? resolvedThingArns : thingArnCandidatesFromId6(id6);
      if (!thingArns.length) {
        return resp(500, { error: 'iot_thing_arn_not_configured' });
      }
      if (!firmwareUrlRaw || !sha256 || !version) {
        return resp(400, {
          error: 'bad_body',
          required: ['firmwareUrl', 'sha256', 'version'],
        });
      }
      if (!/^https:\/\//i.test(firmwareUrlRaw)) {
        return resp(400, { error: 'firmware_url_must_be_https' });
      }
      const firmwareUrl = await ensureSignedFirmwareUrl(firmwareUrlRaw);
      const { stateObj } = await loadStateObjectForIntegrations(id6, stageDetected);
      const stateTarget = pickOtaTargetFromState(stateObj);
      const reqTarget = pickOtaTargetFromRequest(body);
      const targetKeys = ['product', 'hwRev', 'boardRev', 'fwChannel'];
      for (const k of targetKeys) {
        if (reqTarget[k] && stateTarget[k] && reqTarget[k] !== stateTarget[k]) {
          return resp(409, {
            error: 'ota_target_mismatch',
            field: k,
            requested: reqTarget[k],
            device: stateTarget[k],
          });
        }
      }
      const resolvedTarget = {
        product: reqTarget.product || stateTarget.product,
        hwRev: reqTarget.hwRev || stateTarget.hwRev,
        boardRev: reqTarget.boardRev || stateTarget.boardRev,
        fwChannel: reqTarget.fwChannel || stateTarget.fwChannel,
      };
      const missingTarget = targetKeys.filter((k) => !resolvedTarget[k]);
      if (missingTarget.length) {
        return resp(400, {
          error: 'ota_target_missing',
          required: targetKeys,
          missing: missingTarget,
        });
      }
      const requestedJobId = String(body.jobId ?? '').trim();
      const jobId = /^[a-zA-Z0-9_-]{1,64}$/.test(requestedJobId)
        ? requestedJobId
        : genOtaJobId(id6);
      const jobDocument = {
        schemaVersion: '1',
        operation: 'OTA',
        firmware: {
          url: firmwareUrl,
          sha256,
          version,
          minVersion: minVersion || undefined,
          requiresUserApproval,
          target: resolvedTarget,
        },
      };
      if (dryRun) {
        return resp(200, {
          ok: true,
          dryRun: true,
          jobId,
          targetSelection: OTA_JOB_TARGET_SELECTION,
          targets: thingArns,
          requiresUserApproval,
          jobDocument,
        });
      }

      await createIotJobWithMissingThingRetry({
        jobId,
        targets: thingArns,
        document: JSON.stringify(jobDocument),
        targetSelection: OTA_JOB_TARGET_SELECTION,
        description: `OTA ${id6} ${version}`,
        stage: stageDetected,
        id6,
      });

      await writeAudit('ota_job_created', {
        deviceId: id6,
        userSub,
        jobId,
        version,
        minVersion: minVersion || '',
        sha256,
        requiresUserApproval,
        target: resolvedTarget,
        targets: thingArns,
        payloadHash: payloadHash(jobDocument),
      });
      return resp(200, {
        ok: true,
        deviceId: id6,
        jobId,
        created: true,
        targetSelection: OTA_JOB_TARGET_SELECTION,
        requiresUserApproval,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'GET /device/{id6}/capabilities',
      /\/device\/[0-9]{6}\/capabilities\/?$/,
    )) {
      requireId6(id6);
      if (principalType === 'integration') {
        await requireIntegrationAccess({
          integrationId,
          deviceId: id6,
          requiredScope: INTEGRATION_SCOPE_READ,
          stage: stageDetected,
        });
      } else {
        await requireMember(id6, userSub, stageDetected);
      }
      const { stateObj, source } = await loadStateObjectForIntegrations(
        id6,
        stageDetected,
      );

      const capabilities = inferCapabilitiesFromState(stateObj);
      return resp(200, {
        ok: true,
        deviceId: id6,
        schemaVersion: capabilities.schemaVersion,
        source,
        capabilities,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'GET /device/{id6}/ha/config',
      /\/device\/[0-9]{6}\/ha\/config\/?$/,
    )) {
      requireId6(id6);
      if (principalType === 'integration') {
        await requireIntegrationAccess({
          integrationId,
          deviceId: id6,
          requiredScope: INTEGRATION_SCOPE_READ,
          stage: stageDetected,
        });
      } else {
        await requireMember(id6, userSub, stageDetected);
      }
      const { stateObj, source } = await loadStateObjectForIntegrations(
        id6,
        stageDetected,
      );

      const capabilities = inferCapabilitiesFromState(stateObj);
      const messages = generateHaDiscoveryConfigMessages(id6, capabilities);
      return resp(200, {
        ok: true,
        deviceId: id6,
        schemaVersion: capabilities.schemaVersion || '1',
        source,
        count: messages.length,
        messages,
      });
    }

    if (routeMatches(
      method,
      rawPath,
      routeKey,
      'POST /device/{id6}/desired',
      /\/device\/[0-9]{6}\/desired\/?$/,
    )) {
      if (!FEATURE_SHADOW_DESIRED) return resp(404, { error: 'not_found' });
      requireId6(id6);
      let role = 'INTEGRATION';
      if (principalType === 'integration') {
        await requireIntegrationAccess({
          integrationId,
          deviceId: id6,
          requiredScope: INTEGRATION_SCOPE_WRITE,
          stage: stageDetected,
        });
      } else {
        const membership = await requireMember(id6, userSub, stageDetected);
        role = (membership.role || 'USER').toString().toUpperCase();
      }
      if (role === 'GUEST') return resp(403, { error: 'forbidden' });
      const body = parseBody(event);
      if (!isPlainObject(body)) return resp(400, { error: 'bad_body' });
      // Resolve caller local identity hash for firmware-side MQTT auth.
      // Without this, device treats desired/cmd payloads as unauthenticated.
      let actorUserIdHash = '';
      if (principalType !== 'integration') {
        actorUserIdHash = await resolveActorUserIdHash({
          id6,
          userSub,
          role,
          body,
          stage: stageDetected,
        });
        if (!actorUserIdHash) {
          return resp(409, { err: 'user_id_hash_required' });
        }
      }
      const desiredInput = isPlainObject(body.desired) ? body.desired : body;
      const desiredBase = sanitizeDesiredPayload(desiredInput);
      const cmdOnlyDesired = {
        ...desiredBase,
      };
      const currentDesired = await fetchShadowDesiredState(id6, stageDetected);
      const shadowReported = FEATURE_SHADOW_STATE
        ? await fetchShadowReportedState(id6, stageDetected)
        : null;
      if (actorUserIdHash) {
        cmdOnlyDesired.userIdHash = actorUserIdHash;
      }

      // User principals (OWNER/USER/GUEST already filtered) should act as
      // command-only to avoid leaving command-like keys in desired shadow.
      // Some firmware variants don't mirror all desired keys back to reported
      // with the same shape, which can cause persistent delta replays.
      if (principalType !== 'integration') {
        let cleanedDesired = false;
        const cleanupTransient = desiredCmdTransientCleanupFromCurrent(currentDesired);
        if (Object.keys(cleanupTransient).length > 0) {
          try {
            await updateShadowDesiredState(id6, cleanupTransient, stageDetected);
            cleanedDesired = true;
          } catch (e) {
            logEvent('SHADOW', {
              action: 'desired_cmd_cleanup_failed',
              id6,
              stage: stageDetected,
              errorCode: awsErrCode(e),
              error: e?.message || e,
            });
          }
        }

        let bridgedToCmd = false;
        const cmdPayloadRaw = desiredToCmdPayload(cmdOnlyDesired);
        const cmdPayload = pruneNoopCmdPayload(cmdPayloadRaw, shadowReported);
        try {
          if (Object.keys(cmdPayload).length > 0) {
            await iot
              .publish({
                topic: `aac/${id6}/cmd`,
                payload: JSON.stringify(cmdPayload),
                qos: 0,
              })
              .promise();
            bridgedToCmd = true;
          }
        } catch (e) {
          logEvent('CMD', {
            action: 'desired_cmd_only_publish_failed',
            id6,
            stage: stageDetected,
            errorCode: awsErrCode(e),
            error: e?.message || e,
          });
        }

        await writeAudit('shadow_desired_cmd_only', {
          deviceId: id6,
          userSub: actorId,
          payloadHash: payloadHash(cmdPayload),
          hasActorUserIdHash: !!actorUserIdHash,
          bridgedToCmd,
          cleanedDesired,
        });

        return resp(200, {
          ok: true,
          deviceId: id6,
          desiredUpdated: false,
          bridgedToCmd,
          cmdOnly: true,
          cleanedDesired,
          skippedNoop: Object.keys(cmdPayload).length === 0,
        });
      }

      const cleanupUnknown = desiredCleanupFromCurrent(currentDesired);
      const desired = {
        ...cleanupUnknown,
        ...desiredBase,
      };
      if (actorUserIdHash) {
        desired.userIdHash = actorUserIdHash;
      }
      const effectiveDesiredRaw = buildEffectiveDesiredPatch(currentDesired, desired);
      const effectiveDesired = pruneNoopKeysAgainstReported(
        effectiveDesiredRaw,
        shadowReported,
        ['userIdHash', 'acl'],
      );
      logEvent('SHADOW', {
        action: 'desired_sanitized',
        id6,
        stage: stageDetected,
        baseKeyCount: Object.keys(desiredBase).length,
        cleanupUnknownCount: Object.keys(cleanupUnknown).length,
        effectiveRawKeyCount: Object.keys(effectiveDesiredRaw).length,
        effectiveKeyCount: Object.keys(effectiveDesired).length,
        hasActorUserIdHash: !!actorUserIdHash,
      });
      if (Object.keys(effectiveDesired).length === 0) {
        logEvent('SHADOW', {
          action: 'desired_noop',
          id6,
          stage: stageDetected,
        });
        return resp(200, {
          ok: true,
          deviceId: id6,
          desiredUpdated: false,
          bridgedToCmd: false,
          noop: true,
        });
      }
      const updated = await updateShadowDesiredState(id6, effectiveDesired, stageDetected);
      // Bridge desired writes to cmd topic for immediate device-side apply.
      // Shadow desired remains the source of truth; cmd bridge reduces perceived lag.
      let bridgedToCmd = false;
      const cmdPayloadRaw = desiredToCmdPayload(effectiveDesired);
      const cmdPayload = pruneNoopCmdPayload(cmdPayloadRaw, shadowReported);
      try {
        if (Object.keys(cmdPayload).length > 0) {
          await iot
            .publish({
              topic: `aac/${id6}/cmd`,
              payload: JSON.stringify(cmdPayload),
              qos: 0,
            })
            .promise();
          bridgedToCmd = true;
        }
      } catch (e) {
        logEvent('CMD', {
          action: 'desired_bridge_publish_failed',
          id6,
          stage: stageDetected,
          errorCode: awsErrCode(e),
          error: e?.message || e,
        });
      }
      await writeAudit('shadow_desired_update', {
        deviceId: id6,
        userSub: actorId,
        payloadHash: payloadHash(effectiveDesired),
        hasActorUserIdHash: !!actorUserIdHash,
        bridgedToCmd,
      });
      return resp(200, {
        ok: true,
        deviceId: id6,
        desiredUpdated: true,
        bridgedToCmd,
        version: Number(updated?.version || 0) || undefined,
      });
    }

    if (routeKey === 'GET /device/{id6}/state') {
      requireId6(id6);
      // Opportunistic cleanup: remove stale desired keys that can repeatedly
      // trigger command-like firmware paths (e.g. OPEN_JOIN_WINDOW).
      await cleanupShadowDesiredUnknownKeys(id6, stageDetected);
      let role = 'INTEGRATION';
      let ownerUserId = '';
      let users = [];
      if (principalType === 'integration') {
        await requireIntegrationAccess({
          integrationId,
          deviceId: id6,
          requiredScope: INTEGRATION_SCOPE_READ,
          stage: stageDetected,
        });
        // Ownership metadata is optional for integration callers.
        // If the ownership table isn't configured or lookup fails, still return state.
        try {
          const ownership = await fetchOwnership(id6, stageDetected);
          ownerUserId = String(ownership?.ownerUserId || ownership?.ownerSub || '');
        } catch (_) {
          ownerUserId = '';
        }
        users = [{
          userSub: actorId,
          role,
          status: 'active',
        }];
      } else {
        const membership = await requireMember(id6, userSub, stageDetected);
        role = roleNorm(membership?.role, 'USER');
        ownerUserId = String(membership?.ownerUserId || '');
        users = [{
          userSub,
          role,
          status: statusNorm(membership?.status, 'active'),
        }];
      }
      if (FEATURE_SHADOW_STATE) {
        const persistedState = await fetchPersistedStateObject(id6, stageDetected);
        const persistedUpdatedAtMs = await fetchPersistedStateUpdatedAtMs(id6);
        const shadowReported = await fetchShadowReportedState(id6, stageDetected);
        if ((persistedState && isPlainObject(persistedState)) ||
            (shadowReported && isPlainObject(shadowReported))) {
          let statePayload = {};
          if (shadowReported && isPlainObject(shadowReported)) {
            statePayload = normalizeStateResponseObject(shadowReported);
          }
          if (persistedState && isPlainObject(persistedState)) {
            // Prefer the custom-shadow/DDB pipeline because it is the live state
            // source emitted by the device. AWS thing shadow may be stale or
            // partially populated for some firmware variants.
            statePayload = mergeStateResponseObjects(persistedState, statePayload);
          }
          logEvent('STATE', {
            action: 'state_sources_merged',
            id6,
            stage: stageDetected,
            shadow: extractRgbSummary(shadowReported),
            ddb: extractRgbSummary(persistedState),
            response: extractRgbSummary(statePayload),
            preferredSource: (persistedState && isPlainObject(persistedState)) ? 'ddb' : 'shadow',
          });
          const responsePayload = attachStateFreshness(
            statePayload,
            persistedUpdatedAtMs,
          );
          return resp(200, {
            ...responsePayload,
            auth: { role },
            users,
            owner: {
              hasOwner: !!ownerUserId,
              ownerUserId,
            },
            claim: {
              claimed: !!ownerUserId,
            },
          });
        }
      }

      const stateTable = requireTable('state', STATE_TABLE);
      logEvent('STATE', {
        action: 'fetch',
        table: stateTable,
        key: { deviceId: id6 },
        stage: stageDetected,
      });
      const out = await ddb
        .get({
          TableName: stateTable,
          Key: { deviceId: id6 },
        })
        .promise();
      if (!out || !out.Item) {
        logEvent('STATE', {
          action: 'missing',
          table: stateTable,
          key: { deviceId: id6 },
          stage: stageDetected,
        });
        return resp(404, { err: 'state_not_found' });
      }

      const payloadB64 = out.Item.payload_b64 || '';
      const payloadSize =
        typeof payloadB64 === 'string' ? payloadB64.length : 0;
      logEvent('STATE', {
        action: 'loaded',
        id6,
        payloadSize,
        table: stateTable,
        stage: stageDetected,
      });
      let payloadObj = {};
      if (payloadB64) {
        const jsonStr = Buffer.from(payloadB64, 'base64').toString('utf8');
        try {
          payloadObj = JSON.parse(jsonStr);
        } catch (_) {
          payloadObj = { raw: jsonStr };
        }
      }
      const statePayload = attachStateFreshness(
        normalizeStateResponseObject(payloadObj),
        Number(out.Item.updatedAt || 0) || 0,
      );
      return resp(200, {
        ...statePayload,
        auth: { role },
        users,
        owner: {
          hasOwner: !!ownerUserId,
          ownerUserId,
        },
        claim: {
          claimed: !!ownerUserId,
        },
      });
    }

    if (routeKey === 'POST /device/{id6}/cmd') {
      requireId6(id6);
      if (!IOT_ENDPOINT) return resp(500, { error: 'iot_endpoint_not_configured' });
      let role = 'INTEGRATION';
      let membership = null;
      if (principalType === 'integration') {
        await requireIntegrationAccess({
          integrationId,
          deviceId: id6,
          requiredScope: INTEGRATION_SCOPE_WRITE,
          stage: stageDetected,
        });
      } else {
        membership = await requireMember(id6, userSub, stageDetected);
        role = (membership.role || 'USER').toString().toUpperCase();
      }
      if (role === 'GUEST') return resp(403, { error: 'forbidden' });

      const body = parseBody(event);
      if (!isPlainObject(body)) return resp(400, { error: 'bad_body' });
      if (principalType !== 'integration') {
        const actorUserIdHash = await resolveActorUserIdHash({
          id6,
          userSub,
          role,
          body,
          stage: stageDetected,
        });
        if (!actorUserIdHash) {
          return resp(409, { err: 'user_id_hash_required' });
        }
        if (!pickUserIdHash(body)) body.userIdHash = actorUserIdHash;

        // Auto-heal old invite links where userIdHash was not persisted at accept time.
        // Without this, device-side ACL may miss invited users and reject MQTT commands.
        const backfilled = await backfillMemberUserIdHash({
          deviceId: id6,
          userSub,
          membership,
          actorUserIdHash,
          role,
          stage: stageDetected,
        });
        if (backfilled) {
          await pushShadowAclDesiredState(id6, stageDetected);
        }
      }
      if (!body.cmdId) body.cmdId = genCmdId();
      const now = Date.now();
      const rate = FEATURE_RATE_LIMIT
        ? await enforceCmdRateLimit(id6, actorId, now)
        : {
          enforced: false,
          limited: false,
          count: 0,
          max: CMD_RATE_LIMIT_MAX,
          windowSec: CMD_RATE_LIMIT_WINDOW_SEC,
          retryAfterSec: 0,
        };
      if (rate.limited) {
        await writeAudit('cmd_rate_limited', {
          deviceId: id6,
          userSub: actorId,
          cmdId: body.cmdId,
          requestCount: rate.count,
          max: rate.max,
          windowSec: rate.windowSec,
          retryAfterSec: rate.retryAfterSec,
        });
        return resp(429, {
          error: 'rate_limited',
          retryAfterSec: rate.retryAfterSec,
        }, {
          'Retry-After': String(rate.retryAfterSec),
          'X-RateLimit-Limit': String(rate.max),
          'X-RateLimit-Window': String(rate.windowSec),
        });
      }
      const idem = FEATURE_IDEMPOTENCY
        ? await reserveCmdIdempotency(id6, actorId, body.cmdId, now)
        : { enforced: false, duplicate: false };
      if (idem.duplicate) {
        await writeAudit('cmd_duplicate', {
          deviceId: id6,
          userSub: actorId,
          cmdId: body.cmdId,
          payloadHash: payloadHash(body),
        });
        return resp(200, {
          ok: true,
          cmdId: body.cmdId,
          duplicate: true,
          idempotent: true,
        });
      }

      await iot
        .publish({
          topic: `aac/${id6}/cmd`,
          payload: JSON.stringify(body),
          qos: 0,
        })
        .promise();

      await writeAudit('cmd_publish', {
        deviceId: id6,
        userSub: actorId,
        cmdId: body.cmdId,
        payloadHash: payloadHash(body),
      });

      return resp(200, {
        ok: true,
        cmdId: body.cmdId,
        idempotent: !!idem.enforced,
      });
    }

    return resp(404, { error: 'not_found' });
  } catch (e) {
    const code = e.statusCode || 500;
    return resp(code, { error: e.message || 'server_error' });
  }
};
