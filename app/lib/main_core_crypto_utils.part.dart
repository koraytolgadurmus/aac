part of 'main.dart';

// Core shared helpers: crypto primitives, id normalization and BLE utility constants.
// Goal: keep transport/auth foundations reusable across app variants.

enum _ClaimFlowStage { idle, waitingQr, qrStored, claiming, claimed, failed }

class _OwnerKeypair {
  const _OwnerKeypair({
    required this.privateD32,
    required this.publicUncompressed65,
  });

  final List<int> privateD32; // 32 bytes
  final List<int> publicUncompressed65; // 65 bytes: 0x04 || X || Y

  String get publicB64 => base64Encode(publicUncompressed65);
  String get privateB64 => base64Encode(privateD32);
}

List<int> _randomBytes(int n) {
  final r = math.Random.secure();
  return List<int>.generate(n, (_) => r.nextInt(256));
}

List<int> _bigIntToFixedBytes(BigInt v, int len) {
  final out = List<int>.filled(len, 0);
  var x = v;
  for (int i = len - 1; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}

BigInt _bigIntFromBytes(List<int> bytes) {
  BigInt v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b & 0xff);
  }
  return v;
}

List<int>? _bytesFromHex(String hex) {
  final s = hex.trim();
  if (s.isEmpty || s.length.isOdd) return null;
  final out = <int>[];
  for (int i = 0; i < s.length; i += 2) {
    final part = s.substring(i, i + 2);
    final v = int.tryParse(part, radix: 16);
    if (v == null) return null;
    out.add(v);
  }
  return out;
}

String _hexOfBytes(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

String _maskId(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return '-';
  if (v.length <= 8) return '***';
  return '${v.substring(0, 6)}...${v.substring(v.length - 4)}';
}

Future<void> safeBleDisconnect(
  BluetoothDevice? device, {
  required String reason,
}) async {
  final id = device?.remoteId.str ?? '-';
  debugPrint(
    '[BLE][DISC] requested reason=$reason device=$id stack=${StackTrace.current}',
  );
  if (device == null) return;
  try {
    await device.disconnect();
  } catch (e) {
    debugPrint('[BLE][DISC] error $e');
  }
}

const bool kBleAuthDebugStaticKey = bool.fromEnvironment(
  'AAC_BLE_DEBUG_STATIC_KEY',
  defaultValue: false,
);
const List<int> kBleAuthDebugPrivKeyP256 = <int>[
  144,
  148,
  181,
  69,
  75,
  143,
  100,
  133,
  135,
  89,
  43,
  203,
  195,
  250,
  49,
  12,
  98,
  180,
  133,
  108,
  234,
  69,
  49,
  48,
  167,
  19,
  112,
  182,
  122,
  77,
  123,
  249,
];

_OwnerKeypair _generateOwnerKeypairP256() {
  final domain = pc.ECDomainParameters('prime256v1');
  final gen = pc.ECKeyGenerator();

  final fortuna = pc.FortunaRandom();
  fortuna.seed(pc.KeyParameter(Uint8List.fromList(_randomBytes(32))));
  gen.init(
    pc.ParametersWithRandom(pc.ECKeyGeneratorParameters(domain), fortuna),
  );

  final pair = gen.generateKeyPair();
  final priv = pair.privateKey as pc.ECPrivateKey;
  final pub = pair.publicKey as pc.ECPublicKey;

  final d32 = _bigIntToFixedBytes(priv.d!, 32);
  final q65 = pub.Q!.getEncoded(false); // uncompressed
  return _OwnerKeypair(privateD32: d32, publicUncompressed65: q65);
}

pc.ECPrivateKey _parsePrivateKeyP256(List<int> d32) {
  final domain = pc.ECDomainParameters('prime256v1');
  BigInt d = BigInt.zero;
  for (final b in d32) {
    d = (d << 8) | BigInt.from(b & 0xff);
  }
  return pc.ECPrivateKey(d, domain);
}

List<int>? _publicKeyBytesFromPrivP256(List<int> d32) {
  try {
    final priv = _parsePrivateKeyP256(d32);
    final params = priv.parameters;
    final d = priv.d;
    if (params == null || d == null) return null;
    final q = params.G * d;
    if (q == null) return null;
    return q.getEncoded(false);
  } catch (_) {
    return null;
  }
}

String _sha256Fingerprint8(List<int> bytes) {
  final digest = pc.Digest('SHA-256');
  final out = digest.process(Uint8List.fromList(bytes));
  final hex = _hexOfBytes(out);
  return hex.length >= 16 ? hex.substring(0, 16) : hex;
}

String _sha256Hex(List<int> bytes) {
  final digest = pc.Digest('SHA-256');
  final out = digest.process(Uint8List.fromList(bytes));
  return _hexOfBytes(out);
}

List<int> _ecdsaSignBytesP256({
  required List<int> privD32,
  required List<int> msgBytes,
}) {
  final priv = _parsePrivateKeyP256(privD32);
  // Deterministic ECDSA keeps runtime stable across devices and avoids RNG dependency.
  final signer = pc.Signer('SHA-256/DET-ECDSA');
  signer.init(true, pc.PrivateKeyParameter<pc.ECPrivateKey>(priv));
  final sig =
      signer.generateSignature(Uint8List.fromList(msgBytes)) as pc.ECSignature;
  final r32 = _bigIntToFixedBytes(sig.r, 32);
  final s32 = _bigIntToFixedBytes(sig.s, 32);
  return <int>[...r32, ...s32];
}

String? _signOwnerInvite({
  required List<int> privD32,
  required String deviceId6,
  required String inviteId,
  required String role,
  required int exp,
}) {
  if (deviceId6.isEmpty || inviteId.isEmpty) return null;
  final canon = '$deviceId6|$inviteId|$role|$exp';
  final msgBytes = utf8.encode(canon);
  final sigBytes = _ecdsaSignBytesP256(privD32: privD32, msgBytes: msgBytes);
  return base64Encode(sigBytes);
}

List<int>? _deriveBlePrivKeyFromPairToken(String pairTokenHex) {
  final tokenBytes = _bytesFromHex(pairTokenHex);
  if (tokenBytes == null || tokenBytes.isEmpty) return null;
  final digest = pc.Digest('SHA-256').process(Uint8List.fromList(tokenBytes));
  final seed = _bigIntFromBytes(digest);
  final domain = pc.ECDomainParameters('prime256v1');
  var d = seed % domain.n;
  if (d == BigInt.zero) d = BigInt.one;
  return _bigIntToFixedBytes(d, 32);
}

String? _bleSignNonceWithPairToken({
  required String pairTokenHex,
  required String deviceId6,
  required String nonceB64,
}) {
  final d32 = _deriveBlePrivKeyFromPairToken(pairTokenHex);
  if (d32 == null) return null;
  final messageToSign = 'AAC1|$deviceId6|$nonceB64';
  final messageBytes = utf8.encode(messageToSign);
  debugPrint('[BLE][AUTH] nonceB64=$nonceB64');
  debugPrint('[BLE][AUTH] deviceId=$deviceId6');
  debugPrint('[BLE][AUTH] messageLen=${messageBytes.length}');
  final pubKeyBytes = _publicKeyBytesFromPrivP256(d32);
  final pubKeyFp = (pubKeyBytes != null)
      ? _sha256Fingerprint8(pubKeyBytes)
      : '';
  final msgHashFp = _sha256Fingerprint8(messageBytes);
  debugPrint('[BLE][AUTHDBG] alg=ECDSA_P256');
  debugPrint('[BLE][AUTHDBG] pubKeyLen=${pubKeyBytes?.length ?? 0}');
  debugPrint('[BLE][AUTHDBG] pubKeyFp=$pubKeyFp');
  debugPrint('[BLE][AUTHDBG] msgHashFp=$msgHashFp');
  final sigBytes = _ecdsaSignBytesP256(privD32: d32, msgBytes: messageBytes);
  debugPrint('[BLE][AUTHDBG] sigLen=${sigBytes.length}');
  return base64Encode(sigBytes);
}

String? _bleSignNonceWithPrivKey({
  required List<int> privD32,
  required String deviceId6,
  required String nonceB64,
}) {
  final messageToSign = 'AAC1|$deviceId6|$nonceB64';
  final messageBytes = utf8.encode(messageToSign);
  debugPrint('[BLE][AUTH] nonceB64=$nonceB64');
  debugPrint('[BLE][AUTH] deviceId=$deviceId6');
  debugPrint('[BLE][AUTH] messageLen=${messageBytes.length}');
  final pubKeyBytes = _publicKeyBytesFromPrivP256(privD32);
  final pubKeyFp = (pubKeyBytes != null)
      ? _sha256Fingerprint8(pubKeyBytes)
      : '';
  final msgHashFp = _sha256Fingerprint8(messageBytes);
  debugPrint('[BLE][AUTHDBG] alg=ECDSA_P256');
  debugPrint('[BLE][AUTHDBG] pubKeyLen=${pubKeyBytes?.length ?? 0}');
  debugPrint('[BLE][AUTHDBG] pubKeyFp=$pubKeyFp');
  debugPrint('[BLE][AUTHDBG] msgHashFp=$msgHashFp');
  final sigBytes = _ecdsaSignBytesP256(
    privD32: privD32,
    msgBytes: messageBytes,
  );
  debugPrint('[BLE][AUTHDBG] sigLen=${sigBytes.length}');
  return base64Encode(sigBytes);
}

Map<String, dynamic> _extractStateCore(Map<String, dynamic> obj) {
  final state = obj['state'];

  Map<String, dynamic>? unwrapReported(dynamic candidate) {
    if (candidate is! Map<String, dynamic>) return null;
    final reported = candidate['reported'];
    if (reported is Map<String, dynamic>) return reported;
    final nestedState = candidate['state'];
    if (nestedState is Map<String, dynamic>) {
      final nestedReported = nestedState['reported'];
      if (nestedReported is Map<String, dynamic>) return nestedReported;
    }
    return null;
  }

  if (state is Map<String, dynamic>) {
    final reported = unwrapReported(state);
    if (reported != null) return reported;
    final inner = state['state'];
    if (inner is String) {
      final s = inner.trim();
      if (s.isNotEmpty && (s.startsWith('{') || s.startsWith('['))) {
        try {
          final decoded = jsonDecode(s);
          final decodedReported = unwrapReported(decoded);
          if (decodedReported != null) return decodedReported;
          if (decoded is Map<String, dynamic>) return decoded;
        } catch (_) {}
      }
    }
    return state;
  }

  if (state is String) {
    final s = state.trim();
    if (s.isNotEmpty && (s.startsWith('{') || s.startsWith('['))) {
      try {
        final decoded = jsonDecode(s);
        final decodedReported = unwrapReported(decoded);
        if (decodedReported != null) return decodedReported;
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
  }

  final objReported = unwrapReported(obj);
  if (objReported != null) return objReported;
  return obj;
}

bool _hasExplicitRgbState(Map<String, dynamic>? core) {
  if (core == null || core.isEmpty) return false;
  final ui = core['ui'];
  if (ui is Map) {
    if (ui.containsKey('rgbOn') ||
        ui.containsKey('rgbR') ||
        ui.containsKey('rgbG') ||
        ui.containsKey('rgbB') ||
        ui.containsKey('rgbBrightness')) {
      return true;
    }
  }
  final rgb = core['rgb'];
  if (rgb is Map) {
    if (rgb.containsKey('on') ||
        rgb.containsKey('r') ||
        rgb.containsKey('g') ||
        rgb.containsKey('b') ||
        rgb.containsKey('brightness')) {
      return true;
    }
  }
  return false;
}

String? normalizeDeviceId6(String raw) {
  var v = raw.trim();
  if (v.isEmpty) return null;
  final lower = v.toLowerCase();
  final prefixed = RegExp(r'^[a-z0-9_-]+-([0-9]{6})$').firstMatch(lower);
  if (prefixed != null) {
    v = prefixed.group(1) ?? v;
  } else if (v.startsWith('aac-') || v.startsWith('AAC-')) {
    v = v.substring(4);
  }
  v = v.replaceAll('_', '').replaceAll('-', '');
  final digits = RegExp(r'^[0-9]+$');
  if (!digits.hasMatch(v)) return null;
  if (v.length != 6) return null;
  return v;
}

String? canonicalizeDeviceId(String raw) {
  final hostLike =
      Uri.tryParse(raw.trim())?.host.toLowerCase() ?? raw.trim().toLowerCase();
  final plain = hostLike.endsWith('.local')
      ? hostLike.substring(0, hostLike.length - 6)
      : hostLike;
  final withSlug = RegExp(
    r'^([a-z0-9][a-z0-9_-]*)-([0-9]{6})$',
  ).firstMatch(plain);
  if (withSlug != null) {
    final slugRaw = (withSlug.group(1) ?? '').trim().toLowerCase();
    final id6 = withSlug.group(2);
    if (id6 != null && id6.length == 6) {
      final normalizedSlug = _canonicalDeviceProductSlug(slugRaw);
      return '$normalizedSlug-$id6';
    }
  }
  final id6 = normalizeDeviceId6(raw);
  if (id6 == null) return null;
  return '$kDefaultDeviceProductSlug-$id6';
}

String deviceProductSlugFromAny(String raw) {
  final canonical = canonicalizeDeviceId(raw);
  if (canonical == null || canonical.isEmpty) return kDefaultDeviceProductSlug;
  final idx = canonical.indexOf('-');
  if (idx <= 0) return kDefaultDeviceProductSlug;
  final slug = canonical.substring(0, idx).trim().toLowerCase();
  if (slug.isEmpty) return kDefaultDeviceProductSlug;
  return _canonicalDeviceProductSlug(slug);
}

String mdnsSlugFromProductSlug(String productSlug) {
  final p = _canonicalDeviceProductSlug(productSlug);
  if (p == kDefaultDeviceProductSlug) return kDefaultMdnsProductSlug;
  return p;
}

String mdnsHostForId6(String id6, {String? rawIdHint}) {
  final n = normalizeDeviceId6(id6) ?? id6.trim();
  if (n.isEmpty) return '';
  final product = rawIdHint == null || rawIdHint.trim().isEmpty
      ? kDefaultDeviceProductSlug
      : deviceProductSlugFromAny(rawIdHint);
  return '${mdnsSlugFromProductSlug(product)}-$n';
}

String cloudThingNameForId6(String id6, {String? rawIdHint}) {
  final n = normalizeDeviceId6(id6) ?? id6.trim();
  if (n.isEmpty) return '';
  final product = rawIdHint == null || rawIdHint.trim().isEmpty
      ? kDefaultDeviceProductSlug
      : deviceProductSlugFromAny(rawIdHint);
  return '$product-$n';
}

String cloudShadowDesiredTopicForId6(String id6, {String? rawIdHint}) {
  final thing = cloudThingNameForId6(id6, rawIdHint: rawIdHint);
  if (thing.isEmpty) return '';
  return '\$aws/things/$thing/shadow/update';
}

String? thingNameFromAny(String raw) {
  return canonicalizeDeviceId(raw);
}

String? mdnsHostFromAny(String raw) {
  final hostLike =
      Uri.tryParse(raw.trim())?.host.toLowerCase() ?? raw.trim().toLowerCase();
  final plain = hostLike.endsWith('.local')
      ? hostLike.substring(0, hostLike.length - 6)
      : hostLike;
  final withSlug = RegExp(
    r'^([a-z0-9][a-z0-9_-]*)-([0-9]{6})$',
  ).firstMatch(plain);
  if (withSlug != null) {
    final slug = (withSlug.group(1) ?? '').trim().toLowerCase();
    final id6 = withSlug.group(2);
    if (slug.isNotEmpty && id6 != null && id6.length == 6) return '$slug-$id6';
  }

  final id6 = normalizeDeviceId6(raw);
  if (id6 == null || id6.isEmpty) return null;
  return mdnsHostForId6(id6, rawIdHint: raw);
}

String _lowerTrim(String v) => v.trim().toLowerCase();

const String kDefaultDeviceBrand = 'ArtAirCleaner';
const String kDoaDeviceBrand = 'Doa';
const String kBoomDeviceBrand = 'Boom';
const String kDefaultManufacturer = 'AAC';
const String kDefaultDeviceProductSlug = 'aac';
const String kDefaultMdnsProductSlug = 'artair';
const List<String> kKnownDeviceBrands = <String>[
  kDefaultDeviceBrand,
  kDoaDeviceBrand,
  kBoomDeviceBrand,
];

String _canonicalDeviceProductSlug(String slugRaw) {
  final slug = slugRaw.trim().toLowerCase();
  if (slug.isEmpty) return kDefaultDeviceProductSlug;
  if (slug == 'aac' || slug == 'artair' || slug == 'artaircleaner') {
    return kDefaultDeviceProductSlug;
  }
  return slug;
}

String _titleCaseWords(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (cleaned.isEmpty) return '';
  return cleaned
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String _brandFromSlug(String slug) {
  final normalized = slug.trim().toLowerCase();
  if (normalized.isEmpty) return '';
  if (normalized == 'doa') return kDoaDeviceBrand;
  if (normalized == 'boom') return kBoomDeviceBrand;
  if (normalized == 'aac' ||
      normalized == 'artaircleaner' ||
      normalized == 'art_air_cleaner' ||
      normalized == 'art-air-cleaner' ||
      normalized == 'artair') {
    return kDefaultDeviceBrand;
  }
  return _titleCaseWords(slug);
}

String brandFromDeviceProduct(String product) {
  return _brandFromSlug(product);
}

String brandFromBleName(String name) {
  final n = _lowerTrim(name);
  if (n.isEmpty) return '';
  final m = RegExp(r'^(.+?)_bt_[0-9a-f]{6}$').firstMatch(n);
  if (m != null) {
    final fromPrefix = _brandFromSlug(m.group(1) ?? '');
    if (fromPrefix.isNotEmpty) return fromPrefix;
  }
  if (n.startsWith('doa_bt') || n.contains('doa')) return kDoaDeviceBrand;
  if (n.startsWith('boom_bt') || n.contains('boom')) return kBoomDeviceBrand;
  if (n.startsWith('artaircleaner_bt') || n.contains('artair')) {
    return kDefaultDeviceBrand;
  }
  return '';
}

String brandFromHostHint(String hostOrUrl) {
  final raw = hostOrUrl.trim();
  if (raw.isEmpty) return '';
  final host = Uri.tryParse(raw)?.host.toLowerCase() ?? raw.toLowerCase();
  if (host.isEmpty) return '';
  final plain = host.endsWith('.local')
      ? host.substring(0, host.length - 6)
      : host;
  final fromAp = RegExp(
    r'^([a-z0-9][a-z0-9_-]*)_ap_[0-9a-f]{6}$',
  ).firstMatch(plain);
  if (fromAp != null) {
    final fromSlug = _brandFromSlug(fromAp.group(1) ?? '');
    if (fromSlug.isNotEmpty) return fromSlug;
  }
  final fromBt = RegExp(
    r'^([a-z0-9][a-z0-9_-]*)_bt_[0-9a-f]{6}$',
  ).firstMatch(plain);
  if (fromBt != null) {
    final fromSlug = _brandFromSlug(fromBt.group(1) ?? '');
    if (fromSlug.isNotEmpty) return fromSlug;
  }
  final m = RegExp(r'^([a-z0-9][a-z0-9-]*)-[0-9a-f]{6}$').firstMatch(plain);
  if (m != null) {
    final fromSlug = _brandFromSlug(m.group(1) ?? '');
    if (fromSlug.isNotEmpty) return fromSlug;
  }
  if (host.startsWith('doa-') || host.contains('.doa-')) {
    return kDoaDeviceBrand;
  }
  if (host.startsWith('boom-') || host.contains('.boom-')) {
    return kBoomDeviceBrand;
  }
  if (host.startsWith('artair-') ||
      host.contains('.artair-') ||
      host.startsWith('aac-') ||
      host.contains('.aac-')) {
    return kDefaultDeviceBrand;
  }
  return '';
}

bool isDefaultDeviceBrand(String brand) {
  final normalized = _lowerTrim(brand);
  if (normalized.isEmpty) return true;
  return normalized == _lowerTrim(kDefaultDeviceBrand);
}

class DeviceBrandResolution {
  final String brand;
  final String source;
  const DeviceBrandResolution(this.brand, this.source);
}

DeviceBrandResolution resolveDeviceBrand({
  required String firmwareProduct,
  required String bleName,
  required String baseUrl,
  required String mdnsHost,
  required String apSsid,
  String currentBrand = '',
}) {
  final candidates = <MapEntry<String, String>>[
    MapEntry('firmware_product', brandFromDeviceProduct(firmwareProduct)),
    MapEntry('mdns_host', brandFromHostHint(mdnsHost)),
    MapEntry('ap_ssid', brandFromHostHint(apSsid)),
    MapEntry('ble_name', brandFromBleName(bleName)),
    MapEntry('base_url', brandFromHostHint(baseUrl)),
  ];

  for (final c in candidates) {
    final b = c.value.trim();
    if (b.isEmpty || isDefaultDeviceBrand(b)) continue;
    return DeviceBrandResolution(b, c.key);
  }

  for (final c in candidates) {
    final b = c.value.trim();
    if (b.isNotEmpty) {
      final current = currentBrand.trim();
      final keepCurrentSpecific =
          current.isNotEmpty &&
          !isDefaultDeviceBrand(current) &&
          isDefaultDeviceBrand(b);
      if (keepCurrentSpecific) {
        return DeviceBrandResolution(current, 'retained_specific');
      }
      return DeviceBrandResolution(b, c.key);
    }
  }
  return DeviceBrandResolution('', 'none');
}

const List<String> kBleDeviceNamePrefixes = <String>[
  '${kDefaultDeviceBrand}_BT',
  '${kDoaDeviceBrand}_BT',
  '${kBoomDeviceBrand}_BT',
];

const List<String> kApSsidPrefixes = <String>[
  '${kDefaultDeviceBrand}_AP_',
  '${kDoaDeviceBrand}_AP_',
  '${kBoomDeviceBrand}_AP_',
];

bool isKnownBleName(String name) {
  final n = _lowerTrim(name);
  if (n.isEmpty) return false;
  if (RegExp(r'^.+_bt_[0-9a-f]{6}$').hasMatch(n)) return true;
  for (final p in kBleDeviceNamePrefixes) {
    if (n.startsWith(p.toLowerCase())) return true;
  }
  return n.contains('artaircleaner_bt') ||
      n.contains('artair') ||
      n.contains('doa_bt') ||
      n.contains('doa') ||
      n.contains('boom_bt') ||
      n.contains('boom');
}

bool isKnownApSsid(String ssid) {
  final s = _lowerTrim(ssid);
  if (s.isEmpty) return false;
  if (RegExp(r'^.+_ap_[0-9a-f]{6}$').hasMatch(s)) return true;
  for (final p in kApSsidPrefixes) {
    if (s.startsWith(p.toLowerCase())) return true;
  }
  return false;
}

String? extractId6FromKnownApSsid(String ssid) {
  final s = ssid.trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(?:.+)_AP_([0-9A-Fa-f]{6})$').firstMatch(s);
  if (m == null) return null;
  return normalizeDeviceId6(m.group(1) ?? '');
}

Future<BluetoothAdapterState> safeAdapterState({
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    return await FlutterBluePlus.adapterState.first.timeout(timeout);
  } catch (_) {
    return FlutterBluePlus.adapterStateNow;
  }
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

bool _guidEq(Guid a, Guid b) {
  return a.str.toLowerCase() == b.str.toLowerCase();
}

const String kBleDeviceNamePrefix = '${kDefaultDeviceBrand}_BT';
final Guid kSvcUuidHint = Guid('12345678-1234-1234-1234-1234567890aa');
final Guid kProvCharUuidHint = Guid('12345678-1234-1234-1234-1234567890a1');
final Guid kInfoCharUuidHint = Guid('12345678-1234-1234-1234-1234567890a2');
final Guid kCmdCharUuidHint = Guid('12345678-1234-1234-1234-1234567890a3');

const Duration kLocalHttpProbeTimeout = Duration(seconds: 2);
const Duration kLocalHttpRequestTimeout = Duration(seconds: 4);
const Duration kCloudHealthWindow = Duration(seconds: 20);
const Duration kCloudPreferWindow = Duration(seconds: 20);
const Duration kCloudConnectTimeout = Duration(seconds: 180);
const Duration kCloudCmdTimeout = Duration(seconds: 4);
const Duration kCloudCooldown = Duration(seconds: 10);
const Duration kPollFastInterval = Duration(seconds: 2);
const Duration kPollNormalInterval = Duration(seconds: 3);
const Duration kPollStableInterval = Duration(seconds: 4);
const Duration kPollFastWindowAfterSend = Duration(seconds: 15);
const Duration kCloudStateMinFetchInterval = Duration(seconds: 3);

const bool kDebugAutoNetOptIn = bool.fromEnvironment(
  'AAC_DEBUG_NET_OPTIN',
  defaultValue: true,
);

const bool kBleClaimOwnerOnQr = bool.fromEnvironment(
  'AAC_BLE_CLAIM_OWNER',
  defaultValue: true,
);
