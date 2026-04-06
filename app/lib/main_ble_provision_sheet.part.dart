part of 'main.dart';

class BleProvisionSheet extends StatefulWidget {
  const BleProvisionSheet({
    super.key,
    required this.onBaseUrlResolved,
    required this.onSend,
    this.onScanWifi,
    this.initialDevice, // ✅ Bağlı cihazı geç
    this.targetId6, // İsteğe bağlı hedef cihaz ID'si (otomatik bağlanma için)
    this.setupUser, // İsteğe bağlı kurulum user
    this.setupPass, // İsteğe bağlı kurulum pass
    this.pairToken, // İsteğe bağlı doğrulama kodu (Wi-Fi scan için gerekli)
    this.onOwnerClaimed,
    this.onPairTokenDiscovered,
    required this.loadPairToken,
    required this.clearPairToken,
    this.loadSetupCreds,
  });

  final Future<void> Function(String url) onBaseUrlResolved;
  final Future<bool> Function(
    String ssid,
    String pass,
    BluetoothDevice? selectedDevice,
  )
  onSend;
  final Future<void> Function(
    BuildContext context,
    TextEditingController controller,
  )?
  onScanWifi;
  final BluetoothDevice? initialDevice; // ✅ Bağlı cihaz
  final String? targetId6; // İsteğe bağlı hedef cihaz ID'si
  final String? setupUser; // İsteğe bağlı kurulum user
  final String? setupPass; // İsteğe bağlı kurulum pass
  final String? pairToken; // İsteğe bağlı doğrulama kodu
  final Future<void> Function()? onOwnerClaimed;
  final Future<void> Function(String token, String? idHint)?
  onPairTokenDiscovered;
  final Future<String?> Function(String? id6) loadPairToken;
  final Future<void> Function(String? id6) clearPairToken;
  final Future<Map<String, String>?> Function(String id6)? loadSetupCreds;

  @override
  State<BleProvisionSheet> createState() => _BleProvisionSheetState();
}

class _BleProvInfoChars {
  const _BleProvInfoChars({required this.prov, required this.info, this.cmd});
  final BluetoothCharacteristic prov;
  final BluetoothCharacteristic info;
  final BluetoothCharacteristic? cmd;
}

enum _BleScanOutcome {
  success,
  noDevice,
  noCharacteristics,
  empty,
  missingPairToken,
  error,
}

class _BleProvisionSheetState extends State<BleProvisionSheet> {
  bool _scanning = false;
  final Map<DeviceIdentifier, ScanResult> _found = {};
  final Map<DeviceIdentifier, ScanResult> _foundAny = {};
  BluetoothDevice? _selected;
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _autoPickTimer;
  bool _autoConnectInProgress = false;
  String? _autoScannedForRemoteId;
  bool _didAutoRescan = false;
  bool _onlyArt = true; // sadece ArtAir cihazlarını göster
  bool _bleSessionAuthed = false;
  bool _missingProvisionHintShown = false;
  bool _connectInFlight = false;
  String? _connectInFlightId;
  BluetoothDevice? _pendingConnectDevice;
  bool _wifiScanInFlight = false;
  String? _runtimePairToken;
  String? _runtimePairTokenIdHint;
  String? _sessionIdHintFromNonce;

  final TextEditingController _ssidCtl = TextEditingController();
  final TextEditingController _pwdCtl = TextEditingController();
  final FlutterSecureStorage _sheetSecureStorage = const FlutterSecureStorage();

  static const String _kClientPrivD32Key = 'client_priv_d32_b64';
  static const String _kClientPubQ65Key = 'client_pub_q65_b64';
  static const String _kOwnerPrivD32Key = 'owner_priv_d32_b64';
  static const String _kOwnerPubQ65Key = 'owner_pub_q65_b64';

  String? _extractId6FromBleName(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return null;
    final m = RegExp(r'([0-9A-Fa-f]{6})\\s*$').firstMatch(n);
    return m?.group(1)?.toUpperCase();
  }

  String? _normalizedIdHintForSheet(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    final id6 = normalizeDeviceId6(v);
    if (id6 != null && id6.isNotEmpty) return id6;
    return v;
  }

  List<String> _deviceIdCandidates(BluetoothDevice device) {
    final out = <String>[];
    void add(String? raw) {
      final normalized = _normalizedIdHintForSheet(raw);
      if (normalized == null || normalized.isEmpty) return;
      if (!out.contains(normalized)) out.add(normalized);
    }

    final seen = _found[device.remoteId] ?? _foundAny[device.remoteId];
    add(_sessionIdHintFromNonce);
    add(_extractId6FromBleName(device.platformName));
    if (seen != null) {
      add(_extractId6FromBleName(_bestName(seen)));
    }
    add(widget.targetId6);
    return out;
  }

  Future<String?> _peekPairTokenForDevice(BluetoothDevice device) async {
    for (final key in _deviceIdCandidates(device)) {
      final stored = await widget.loadPairToken(key);
      if (stored != null && stored.trim().isNotEmpty) {
        return stored.trim();
      }
    }

    final runtime = _runtimePairToken?.trim();
    if (runtime != null && runtime.isNotEmpty) {
      return runtime;
    }

    final direct = widget.pairToken?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    return null;
  }

  Future<bool> _hasCachedSetupCredsForDevice(BluetoothDevice device) async {
    final inlineUser = widget.setupUser?.trim() ?? '';
    final inlinePass = widget.setupPass?.trim() ?? '';
    if (inlineUser.isNotEmpty && inlinePass.isNotEmpty) {
      return true;
    }
    final loader = widget.loadSetupCreds;
    if (loader == null) return false;
    for (final key in _deviceIdCandidates(device)) {
      final creds = await loader(key);
      final user = (creds?['user'] ?? '').trim();
      final pass = (creds?['pass'] ?? '').trim();
      if (user.isNotEmpty && pass.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _canAttemptBleAuth(BluetoothDevice device) async {
    if (await _hasCachedSetupCredsForDevice(device)) return true;
    if (await _peekPairTokenForDevice(device) != null) return true;
    return await _loadAnyPrivKeyD32() != null;
  }

  Future<bool> _canProvisionViaBle(BluetoothDevice device) async {
    return await _peekPairTokenForDevice(device) != null;
  }

  bool get _allowAutomaticBleConnect {
    final inlineUser = widget.setupUser?.trim() ?? '';
    final inlinePass = widget.setupPass?.trim() ?? '';
    final inlinePair = widget.pairToken?.trim() ?? '';
    final target = widget.targetId6?.trim() ?? '';
    return widget.initialDevice != null ||
        target.isNotEmpty ||
        inlinePair.isNotEmpty ||
        (inlineUser.isNotEmpty && inlinePass.isNotEmpty);
  }

  void _showMissingProvisionHintOnce() {
    if (_missingProvisionHintShown || !mounted) return;
    _missingProvisionHintShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _lt(
            context,
            'Bu cihaz için önce IR ile pair/recovery penceresini açın, sonra Bluetooth ile devam edin.',
          ),
        ),
      ),
    );
  }

  Future<String?> _resolvePairTokenForDevice(BluetoothDevice device) async {
    final seen = _found[device.remoteId];
    final seenName = seen != null ? _bestName(seen) : '';
    final seenId6 = _extractId6FromBleName(seenName);
    // Always prioritize the currently connected device identity first.
    final id6 =
        _normalizedIdHintForSheet(_sessionIdHintFromNonce) ??
        _normalizedIdHintForSheet(
          _extractId6FromBleName(device.platformName),
        ) ??
        _normalizedIdHintForSheet(seenId6) ??
        _normalizedIdHintForSheet(widget.targetId6);
    final fromStorage = await widget.loadPairToken(id6);
    if (fromStorage != null && fromStorage.trim().isNotEmpty) {
      debugPrint('[BLE][TOKEN] Loaded pairToken from storage for id6=$id6');
      return fromStorage.trim();
    }

    // AUTH_SETUP sırasında keşfedilen token (persist gecikmesi için in-memory fallback)
    final runtime = _runtimePairToken?.trim();
    final runtimeHint = _runtimePairTokenIdHint?.trim();
    if (runtime != null && runtime.isNotEmpty) {
      final sameDevice =
          runtimeHint == null ||
          runtimeHint.isEmpty ||
          id6 == null ||
          id6.isEmpty ||
          runtimeHint.toUpperCase() == id6.toUpperCase();
      if (sameDevice) {
        debugPrint('[BLE][TOKEN] Using runtime discovered pairToken');
        return runtime;
      }
    }

    // ✅ Fallback: widget.pairToken (eğer storage'da yoksa)
    final direct = widget.pairToken?.trim();
    if (direct != null && direct.isNotEmpty) {
      debugPrint('[BLE][TOKEN] Using widget.pairToken (fallback)');
      return direct;
    }

    debugPrint('[BLE][TOKEN] No pairToken found for id6=$id6');
    return null;
  }

  Future<void> _clearPairTokenForDevice(BluetoothDevice device) async {
    final id6 = _extractId6FromBleName(device.platformName) ?? widget.targetId6;
    await widget.clearPairToken(id6?.trim());
  }

  Future<String?> _getOrCreateClientPubKeyB64() async {
    try {
      final pub = await _sheetSecureStorage.read(key: _kClientPubQ65Key);
      final priv = await _sheetSecureStorage.read(key: _kClientPrivD32Key);
      if (pub != null && pub.isNotEmpty && priv != null && priv.isNotEmpty) {
        return pub;
      }
    } catch (_) {}
    final kp = _generateOwnerKeypairP256();
    try {
      await _sheetSecureStorage.write(
        key: _kClientPrivD32Key,
        value: kp.privateB64,
      );
      await _sheetSecureStorage.write(
        key: _kClientPubQ65Key,
        value: kp.publicB64,
      );
    } catch (_) {}
    return kp.publicB64;
  }

  Future<String?> _getOrCreateOwnerPubKeyB64() async {
    try {
      final pub = await _sheetSecureStorage.read(key: _kOwnerPubQ65Key);
      final priv = await _sheetSecureStorage.read(key: _kOwnerPrivD32Key);
      if (pub != null && pub.isNotEmpty && priv != null && priv.isNotEmpty) {
        return pub;
      }
    } catch (_) {}
    final kp = _generateOwnerKeypairP256();
    try {
      await _sheetSecureStorage.write(
        key: _kOwnerPrivD32Key,
        value: kp.privateB64,
      );
      await _sheetSecureStorage.write(
        key: _kOwnerPubQ65Key,
        value: kp.publicB64,
      );
    } catch (_) {}
    return kp.publicB64;
  }

  Future<bool> _bleClaimOwner({
    required BluetoothCharacteristic cmdChar,
    required BluetoothCharacteristic infoChar,
    required String user,
    required String pass,
  }) async {
    StreamSubscription<List<int>>? sub;
    try {
      final ownerPub = await _getOrCreateOwnerPubKeyB64();
      if (ownerPub == null || ownerPub.isEmpty) return false;

      final completer = Completer<Map<String, dynamic>>();
      final framer = _BleJsonFramer();
      sub = infoChar.lastValueStream.listen((data) {
        try {
          final chunk = utf8.decode(data, allowMalformed: true);
          for (final js in framer.feed(chunk)) {
            final obj = jsonDecode(js);
            if (obj is! Map<String, dynamic>) continue;
            final claim = obj['claim'];
            if (claim is Map) {
              if (!completer.isCompleted) {
                completer.complete(claim.cast<String, dynamic>());
              }
              return;
            }
          }
        } catch (_) {}
      });

      debugPrint(
        '[BLE][AUTH][sheet] CLAIM_REQUEST send (pubLen=${ownerPub.length})',
      );
      final payload = jsonEncode(<String, dynamic>{
        'type': 'CLAIM_REQUEST',
        'user': user,
        'pass': pass,
        'owner_pubkey': ownerPub,
      });
      await cmdChar.write(
        utf8.encode(payload),
        withoutResponse: !cmdChar.properties.write,
      );

      final claim = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => <String, dynamic>{'ok': false, 'err': 'timeout'},
      );
      final ok = claim['ok'] == true;
      if (!ok) {
        debugPrint(
          '[BLE][AUTH][sheet] CLAIM_REQUEST failed err=${claim['err'] ?? 'unknown'}',
        );
      } else {
        final claimToken = (claim['pairToken'] ?? claim['qrToken'] ?? '')
            .toString()
            .trim();
        final claimIdRaw = (claim['id6'] ?? claim['deviceId'] ?? '')
            .toString()
            .trim();
        if (claimToken.isNotEmpty && widget.onPairTokenDiscovered != null) {
          try {
            await widget.onPairTokenDiscovered!(
              claimToken,
              claimIdRaw.isNotEmpty ? claimIdRaw : _sessionIdHintFromNonce,
            );
            _runtimePairToken = claimToken;
            _runtimePairTokenIdHint = claimIdRaw.isNotEmpty
                ? claimIdRaw
                : _sessionIdHintFromNonce;
            debugPrint(
              '[BLE][AUTH][sheet] CLAIM_REQUEST persisted pairToken len=${claimToken.length}',
            );
          } catch (e) {
            debugPrint(
              '[BLE][AUTH][sheet] CLAIM_REQUEST pairToken persist error: $e',
            );
          }
        }
        debugPrint('[BLE][AUTH][sheet] CLAIM_REQUEST ok');
      }
      return ok;
    } catch (e) {
      debugPrint('[BLE][AUTH][sheet] CLAIM_REQUEST error: $e');
      return false;
    } finally {
      await sub?.cancel();
    }
  }

  @override
  void initState() {
    super.initState();
    // SSID'yi geçmişten doldur
    Future.microtask(() => _prefillLastSsid());

    // ✅ Eğer bağlı bir cihaz varsa, onu kullan ve WiFi listesini otomatik çek
    if (widget.initialDevice != null) {
      Future.microtask(() async {
        // Cihaz zaten bağlı olabilir, kontrol et
        final device = widget.initialDevice!;
        try {
          // Cihazın bağlantı durumunu kontrol et
          final isConnected = await _safeConnectionState(
            device,
            timeout: const Duration(milliseconds: 500),
          );

          if (isConnected == BluetoothConnectionState.connected) {
            // Zaten bağlı, sadece seç
            if (mounted) setState(() => _selected = device);
            if (mounted && _scanning) {
              setState(() => _scanning = false);
            }
            debugPrint(
              '[BLE][PROV] Using already connected device: ${device.remoteId.str}',
            );
          } else {
            // Bağlı değil, bağlan
            await _connect(device);
          }

          // Bağlantı başarılı olduktan sonra WiFi listesini otomatik çek
          if (_selected != null &&
              mounted &&
              await _canProvisionViaBle(device)) {
            await _autoScanWifiViaBle();
          } else if (mounted) {
            // initialDevice başarısız olursa kullanıcıyı manuel butona zorlamadan
            // cihaz listesini otomatik doldur.
            await _startScan();
          }
        } catch (e) {
          debugPrint('[BLE][PROV] Error using initial device: $e');
          // Hata olursa normal taramaya geç
          if (mounted) Future.microtask(() => _startScan());
        }
      });
    } else if (widget.targetId6 != null) {
      // Hedef cihaz ID'si varsa tarama yap ve otomatik bağlan.
      Future.microtask(() async {
        try {
          await _startScan();

          // Hedef ID'ye sahip cihazı bul (biraz bekleyerek).
          final expectedSuffix = '_${widget.targetId6}'.toLowerCase();
          BluetoothDevice? targetDevice;

          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (mounted &&
              targetDevice == null &&
              DateTime.now().isBefore(deadline)) {
            for (final result in _foundAny.values) {
              final name = _bestName(result);
              final lowerName = name.toLowerCase();
              if ((isKnownBleName(lowerName) &&
                      lowerName.endsWith(expectedSuffix)) ||
                  lowerName.contains(widget.targetId6!.toLowerCase())) {
                targetDevice = result.device;
                debugPrint('[BLE][PROV] Found hinted device: $name');
                break;
              }
            }
            if (targetDevice != null) break;
            await Future.delayed(const Duration(milliseconds: 400));
          }

          await _stopScan();

          // İsim/ADV yayınlamayan iOS durumlarında son fallback:
          // filtre bağımsız toplanan sonuçlardan en güçlü uyumlu aday seç.
          if (targetDevice == null) {
            final candidates = _foundAny.values.where((r) {
              final name = _bestName(r);
              return _matchesArtAir(name, r.advertisementData);
            }).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
            if (candidates.isNotEmpty) {
              targetDevice = candidates.first.device;
              debugPrint(
                '[BLE][PROV] Fallback picked strongest compatible candidate: ${targetDevice.remoteId.str}',
              );
            }
          }

          // Eğer bulunduysa bağlan
          if (targetDevice != null && mounted) {
            await _connect(targetDevice);
            // Bağlantı sonrası WiFi listesini çek
            if (_selected != null &&
                mounted &&
                await _canProvisionViaBle(targetDevice)) {
              await _autoScanWifiViaBle();
            }
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Hedef cihaz bulunamadı (ID: ${widget.targetId6}). Manuel seçin.',
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          debugPrint('[BLE][PROV] targetId6 auto-flow error: $e');
          if (mounted) {
            Future.microtask(() => _startScan());
          }
        }
      });
    } else {
      // Başlangıçta taramayı başlat (yeni cihaz arıyorsa)
      Future.microtask(() => _startScan());
    }
  }

  @override
  void dispose() {
    _autoPickTimer?.cancel();
    _scanSub?.cancel();
    _stopScan();
    unawaited(safeBleDisconnect(_selected, reason: 'ble_prov_sheet_dispose'));
    _ssidCtl.dispose();
    _pwdCtl.dispose();
    super.dispose();
  }

  Future<_BleProvInfoChars?> _resolveProvInfoChars(
    BluetoothDevice device,
  ) async {
    final services = await device.discoverServices();
    debugPrint('[BLE][sheet] discoverServices -> ${services.length} services');
    if (services.isEmpty) return null;

    BluetoothService? svc;
    for (final service in services) {
      if (_guidEq(service.uuid, kSvcUuidHint)) {
        svc = service;
        break;
      }
    }
    svc ??= services.first;
    if (svc.characteristics.isEmpty) {
      for (final service in services) {
        if (service.characteristics.isNotEmpty) {
          svc = service;
          break;
        }
      }
    }
    final resolvedSvc = svc;
    if (resolvedSvc == null || resolvedSvc.characteristics.isEmpty) {
      debugPrint('[BLE][sheet] no service with characteristics found');
      return null;
    }

    BluetoothCharacteristic? chProv;
    BluetoothCharacteristic? chInfo;
    BluetoothCharacteristic? chCmd;

    for (final ch in resolvedSvc.characteristics) {
      debugPrint(
        '[BLE][sheet] char ${ch.uuid.str} props: w=${ch.properties.write} wNR=${ch.properties.writeWithoutResponse} notify=${ch.properties.notify}',
      );
      if (chProv == null &&
          (_guidEq(ch.uuid, kProvCharUuidHint) ||
              ch.properties.write ||
              ch.properties.writeWithoutResponse)) {
        chProv = ch;
      }
      if (chInfo == null &&
          (_guidEq(ch.uuid, kInfoCharUuidHint) || ch.properties.notify)) {
        chInfo = ch;
      }
      if (chCmd == null &&
          !_guidEq(ch.uuid, kProvCharUuidHint) &&
          !_guidEq(ch.uuid, kInfoCharUuidHint) &&
          (ch.properties.write || ch.properties.writeWithoutResponse)) {
        chCmd = ch;
      }
    }

    if (chProv == null || chInfo == null) {
      for (final service in services) {
        for (final ch in service.characteristics) {
          debugPrint(
            '[BLE][sheet] fallback char ${ch.uuid.str} props: w=${ch.properties.write} wNR=${ch.properties.writeWithoutResponse} notify=${ch.properties.notify}',
          );
          if (chProv == null &&
              (_guidEq(ch.uuid, kProvCharUuidHint) ||
                  ch.properties.write ||
                  ch.properties.writeWithoutResponse)) {
            chProv = ch;
          }
          if (chInfo == null &&
              (_guidEq(ch.uuid, kInfoCharUuidHint) || ch.properties.notify)) {
            chInfo = ch;
          }
          if (chCmd == null &&
              !_guidEq(ch.uuid, kProvCharUuidHint) &&
              !_guidEq(ch.uuid, kInfoCharUuidHint) &&
              (ch.properties.write || ch.properties.writeWithoutResponse)) {
            chCmd = ch;
          }
        }
      }
    }

    if (chProv == null || chInfo == null) return null;
    final resolved = _BleProvInfoChars(prov: chProv, info: chInfo, cmd: chCmd);
    debugPrint(
      '[BLE][sheet] resolved prov=${resolved.prov.uuid.str} info=${resolved.info.uuid.str} cmd=${resolved.cmd?.uuid.str ?? 'null'}',
    );
    return resolved;
  }

  void _collectSsidsFromJson(dynamic source, Set<String> out) {
    String? asString(dynamic value) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
      return null;
    }

    if (source is String) {
      final s = asString(source);
      if (s != null) out.add(s);
      return;
    }

    if (source is List) {
      for (final item in source) {
        if (item is Map) {
          _collectSsidsFromJson(item['ssid'], out);
          _collectSsidsFromJson(item['name'], out);
          _collectSsidsFromJson(item['aps'], out);
          _collectSsidsFromJson(item['scan'], out);
          _collectSsidsFromJson(item['wifi_scan'], out);
          _collectSsidsFromJson(item['networks'], out);
          _collectSsidsFromJson(item['wifi'], out);
        } else {
          _collectSsidsFromJson(item, out);
        }
      }
      return;
    }

    if (source is Map) {
      _collectSsidsFromJson(source['ssid'], out);
      _collectSsidsFromJson(source['aps'], out);
      _collectSsidsFromJson(source['scan'], out);
      _collectSsidsFromJson(source['wifi_scan'], out);
      _collectSsidsFromJson(source['networks'], out);
      _collectSsidsFromJson(source['wifi'], out);
      _collectSsidsFromJson(source['list'], out);
      _collectSsidsFromJson(source['data'], out);
    }
  }

  Future<_BleScanOutcome> _scanWifiViaBle() async {
    if (_wifiScanInFlight) {
      debugPrint('[BLE][SSID][sheet] scan ignored: already in progress');
      return _BleScanOutcome.success;
    }

    final device = _selected;
    if (device == null) {
      debugPrint('[BLE][SSID][sheet] scan aborted: no device selected');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_lt(context, 'Önce BLE cihazı seçin.'))),
        );
      }
      return _BleScanOutcome.noDevice;
    }

    debugPrint(
      '[BLE][SSID][sheet] scan start for device ${device.remoteId.str}',
    );

    bool dialogShown = false;
    if (mounted) {
      dialogShown = true;
      // Show a lightweight progress indicator while collecting SSIDs
      // ignore: use_build_context_synchronously
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    Future<void> closeDialog() async {
      if (!dialogShown || !mounted) return;
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      dialogShown = false;
    }

    final ssids = <String>{};
    final framer = _BleJsonFramer();
    var rawScanWindow = '';
    var malformedFrameCount = 0;
    StreamSubscription<List<int>>? notifySub;
    bool linkLost = false;
    void collectSsidsFromRawChunk(String chunk) {
      if (chunk.isEmpty) return;
      rawScanWindow += chunk;
      if (rawScanWindow.length > 12288) {
        rawScanWindow = rawScanWindow.substring(rawScanWindow.length - 8192);
      }
      final re = RegExp(r'"ssid"\s*:\s*"([^"]*)"');
      for (final m in re.allMatches(rawScanWindow)) {
        final raw = m.group(1);
        if (raw == null || raw.isEmpty) continue;
        try {
          final decoded = jsonDecode('"$raw"');
          if (decoded is String && decoded.trim().isNotEmpty) {
            ssids.add(decoded.trim());
          }
        } catch (_) {
          final s = raw.trim();
          if (s.isNotEmpty) ssids.add(s);
        }
      }
    }

    bool isLikelyScanPayload(dynamic obj) {
      if (obj is! Map) return false;
      return obj.containsKey('aps') ||
          obj.containsKey('scan') ||
          obj.containsKey('wifi_scan') ||
          obj.containsKey('networks') ||
          (obj['source']?.toString() == 'ble' && obj.containsKey('count'));
    }

    try {
      _wifiScanInFlight = true;
      // ✅ Bağlantı durumunu kontrol et ve gerekirse yeniden bağlan
      try {
        final connState = await _safeConnectionState(
          device,
          timeout: const Duration(milliseconds: 500),
        );
        if (connState != BluetoothConnectionState.connected) {
          debugPrint(
            '[BLE][SSID][sheet] Device not connected, reconnecting...',
          );
          await device.connect(timeout: const Duration(seconds: 5));
          await Future.delayed(const Duration(milliseconds: 400));
          await _ensureBleSessionAuthed(device);
        }
      } catch (e) {
        debugPrint('[BLE][SSID][sheet] Connection check failed: $e');
      }
      // Always authenticate first. For unowned devices this can discover/persist
      // a fresh pairToken during AUTH_SETUP flow.
      if (!_bleSessionAuthed) {
        final authed = await _ensureBleSessionAuthed(device);
        if (!authed) {
          await closeDialog();
          return _BleScanOutcome.error;
        }
      }

      try {
        await device.requestMtu(185);
      } catch (_) {}

      final chars = await _resolveProvInfoChars(device);
      if (chars == null) {
        await closeDialog();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _lt(
                  context,
                  'Gerekli BLE özellikleri bulunamadı (WRITE/NOTIFY).',
                ),
              ),
            ),
          );
        }
        return _BleScanOutcome.noCharacteristics;
      }

      final provChar = chars.prov;
      final infoChar = chars.info;
      final cmdChar = chars.cmd ?? provChar;
      final usingProvForCmd = identical(cmdChar, provChar);
      debugPrint(
        '[BLE][SSID][sheet] using cmd uuid=${cmdChar.uuid.str} (prov=${provChar.uuid.str})',
      );
      if (usingProvForCmd) {
        debugPrint(
          '[BLE][SSID][sheet] cmd characteristic fallback to provisioning characteristic',
        );
      }

      try {
        await infoChar.setNotifyValue(true);
        debugPrint('[BLE][SSID][sheet] notify enabled on ${infoChar.uuid.str}');
      } catch (e) {
        debugPrint('[BLE][SSID][sheet] failed to enable notify: $e');
      }

      notifySub = infoChar.lastValueStream.listen((data) {
        try {
          final chunk = utf8.decode(data, allowMalformed: true);
          debugPrint('[BLE][SSID][sheet] notify chunk: $chunk');
          // Defensive fallback: capture SSIDs even if framed JSON parse fails.
          collectSsidsFromRawChunk(chunk);
          final completed = framer.feed(chunk);
          for (final js in completed) {
            try {
              final obj = jsonDecode(js);
              malformedFrameCount = 0;
              if (obj is Map) {
                final auth = obj['auth'];
                if (auth is Map) {
                  final err = auth['err']?.toString() ?? '';
                  if (err == 'invalid_qr_token' || err == 'qr_token_required') {
                    unawaited(_clearPairTokenForDevice(device));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _lt(
                              context,
                              'Cihaz doğrulama kodu geçersiz veya eski. Soft recovery açıp tekrar deneyin.',
                            ),
                          ),
                        ),
                      );
                    }
                  }
                  if (err == 'insufficient_role') {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _lt(
                              context,
                              'Bu işlem için owner yetkisi gerekli.',
                            ),
                          ),
                        ),
                      );
                    }
                  }
                }
                if (!isLikelyScanPayload(obj)) {
                  // Ignore high-frequency status frames during scan; they can
                  // interleave with scan payload and create noisy partial data.
                  continue;
                }
              }
              _collectSsidsFromJson(obj, ssids);
            } catch (e) {
              debugPrint('[BLE][SSID][sheet] framed JSON decode error: $e');
              malformedFrameCount++;
              if (malformedFrameCount >= 2 || framer.bufferedLength > 8192) {
                framer.reset();
                malformedFrameCount = 0;
              }
            }
          }
        } catch (e) {
          debugPrint('[BLE][SSID][sheet] chunk decode error: $e');
        }
      });

      // ✅ WiFi scan komutları: firmware QR token (pairToken) ister.
      final resolvedQr = await _resolvePairTokenForDevice(device);
      debugPrint(
        '[BLE][SSID][sheet] Resolved qrToken: ${resolvedQr != null && resolvedQr.isNotEmpty ? "${resolvedQr.substring(0, 8)}..." : "null/empty"}',
      );
      final hasQrToken = resolvedQr != null && resolvedQr.isNotEmpty;
      final allowAuthedWithoutQr = _bleSessionAuthed;
      if (!hasQrToken && !allowAuthedWithoutQr) {
        await closeDialog();
        _showMissingProvisionHintOnce();
        return _BleScanOutcome.missingPairToken;
      }

      Future<bool> writeCmd(Map<String, dynamic> cmd) async {
        final connState = await _safeConnectionState(
          device,
          timeout: const Duration(milliseconds: 500),
        );
        if (connState != BluetoothConnectionState.connected) {
          linkLost = true;
          return false;
        }

        final payload = Map<String, dynamic>.from(cmd);
        final isProv = identical(cmdChar, provChar);
        final body = jsonEncode(payload);
        final supportsNoResp = cmdChar.properties.writeWithoutResponse;
        final supportsWithResp = cmdChar.properties.write;

        Future<bool> tryWrite(bool withoutResponse) async {
          try {
            await cmdChar.write(
              utf8.encode(body),
              withoutResponse: withoutResponse,
            );
            debugPrint(
              '[BLE][SSID][sheet] requested via write${withoutResponse ? ' (no resp)' : ''}: $body',
            );
            return true;
          } catch (e) {
            debugPrint(
              '[BLE][SSID][sheet] write error (noResp=$withoutResponse): $e',
            );
            if ('$e'.contains('device is not connected')) {
              linkLost = true;
            }
            return false;
          }
        }

        bool attempted = false;

        // iOS tarafında no-response flood timeout üretebildiği için
        // önce write-with-response dene, no-response'u fallback yap.
        if (supportsWithResp || isProv) {
          attempted = true;
          if (await tryWrite(false)) return true;
        }

        if (!isProv && supportsNoResp) {
          attempted = true;
          if (await tryWrite(true)) return true;
        }

        if (!attempted) {
          debugPrint(
            '[BLE][SSID][sheet] write skipped: characteristic has no writable property',
          );
        }
        return false;
      }

      // Tek istek gönder; ESP32 scan sonucunu NOTIFY ile push eder.
      // Not: "get:wifi_scan" firmware tarafında yeni scan'i tetikleyebilir,
      // bu yüzden burada polling yapmıyoruz.
      final scanCmd = <String, dynamic>{'cmd': 'scan_wifi'};
      if (hasQrToken) {
        scanCmd['qrToken'] = resolvedQr;
      } else {
        debugPrint(
          '[BLE][SSID][sheet] scan_wifi without qrToken (session already authed)',
        );
      }
      if (!await writeCmd(scanCmd)) {
        if (linkLost) {
          throw Exception('ble_disconnected');
        }
      }

      // BLE notify parçaları bazı iOS oturumlarında kaybolabildiği için
      // aynı oturumda kısa aralıklarla yeniden scan tetikleyip sonucu bekle.
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          if (!await writeCmd(scanCmd)) {
            if (linkLost) {
              throw Exception('ble_disconnected');
            }
          }
          debugPrint('[BLE][SSID][sheet] scan retry attempt=${attempt + 1}');
        }
        final attemptDeadline = DateTime.now().add(const Duration(seconds: 4));
        while (DateTime.now().isBefore(attemptDeadline)) {
          if (ssids.isNotEmpty || linkLost) break;
          await Future.delayed(const Duration(milliseconds: 250));
        }
        if (ssids.isNotEmpty || linkLost) break;
      }
      // If the peripheral drops right after publishing scan results,
      // keep the collected list instead of failing hard.
      if (linkLost && ssids.isEmpty) {
        throw Exception('ble_disconnected');
      }
    } catch (e) {
      debugPrint('[BLE][SSID][sheet] scan error: $e');
      await closeDialog();
      await notifySub?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_lt(context, 'Wi-Fi taraması başarısız')}: ${'$e'.contains('ble_disconnected') ? _lt(context, 'Bluetooth bağlantısı koptu, tekrar deneyin.') : e}',
            ),
          ),
        );
      }
      return _BleScanOutcome.error;
    } finally {
      await closeDialog();
      await notifySub?.cancel();
      _wifiScanInFlight = false;
    }

    final list = ssids.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    String? selectedId6Hint() {
      final fromTarget = widget.targetId6?.trim();
      if (fromTarget != null && fromTarget.isNotEmpty) return fromTarget;
      final fromSession = _sessionIdHintFromNonce?.trim();
      if (fromSession != null && fromSession.isNotEmpty) return fromSession;
      final fromName = _extractId6FromBleName(_selected?.platformName);
      if (fromName != null && fromName.isNotEmpty) return fromName;
      final seen = _selected != null ? _found[_selected!.remoteId] : null;
      if (seen != null) {
        final v = _extractId6FromBleName(_bestName(seen));
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final id6 = selectedId6Hint();
    final expectedApSsids = (id6 != null && id6.isNotEmpty)
        ? kApSsidPrefixes.map((p) => '$p$id6').toList(growable: false)
        : const <String>[];
    final apOnly = list.where((s) => isKnownApSsid(s)).toList();
    String? expectedFound;
    if (expectedApSsids.isNotEmpty) {
      for (final s in apOnly) {
        if (expectedApSsids.any(
          (candidate) => s.toLowerCase() == candidate.toLowerCase(),
        )) {
          expectedFound = s;
          break;
        }
      }
    }

    if (expectedFound != null) {
      _ssidCtl.text = expectedFound;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_ssid', expectedFound);
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _lt(
                context,
                'Cihaz AP ağı bulundu. Telefonunuzu bu ağa bağlayıp devam edin.',
              ),
            ),
          ),
        );
      }
      return _BleScanOutcome.success;
    }

    if (list.isEmpty) {
      debugPrint('[BLE][SSID][sheet] BLE scan yielded empty list');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_lt(context, 'Wi-Fi ağları bulunamadı'))),
        );
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(_lt(context, 'Wi-Fi ağları bulunamadı')),
            content: Text(
              _lt(
                context,
                'Wi-Fi ağları bulunamadı. Cihaza daha yakın olun veya cihazın yanında tekrar deneyin.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_lt(context, 'Tamam')),
              ),
            ],
          ),
        );
      }
      final fallback = widget.onScanWifi;
      if (fallback != null && mounted) {
        debugPrint('[BLE][SSID][sheet] invoking captive portal fallback');
        await fallback(context, _ssidCtl);
      }
      return _BleScanOutcome.empty;
    }

    if (!mounted) return _BleScanOutcome.success;

    final normalWifi = list.where((s) => !isKnownApSsid(s)).toList(
      growable: false,
    );
    final displayList = <String>[
      ...normalWifi,
      ...apOnly.where((s) => !normalWifi.contains(s)),
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: displayList.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final ssid = displayList[i];
              return ListTile(
                leading: const Icon(Icons.wifi),
                title: Text(ssid, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context).pop(ssid),
              );
            },
          ),
        );
      },
    );

    if (selected != null && selected.trim().isNotEmpty) {
      final ssid = selected.trim();
      debugPrint('[BLE][SSID][sheet] user picked ssid=$ssid');
      _ssidCtl.text = ssid;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_ssid', ssid);
      } catch (_) {}
      try {
        await Clipboard.setData(ClipboardData(text: ssid));
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_lt(context, 'SSID seçildi')}: $ssid')),
        );
      }
      final pass = _pwdCtl.text;
      if (pass.isNotEmpty) {
        debugPrint(
          '[BLE][SSID][sheet] auto provisioning after SSID pick (ssid=$ssid, passLen=${pass.length})',
        );
        try {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_lt(context, 'Wi-Fi ayarlari gonderiliyor...')),
              ),
            );
          }
          final ok = await widget.onSend(ssid, pass, _selected);
          if (mounted && ok) {
            Navigator.of(context).pop();
          } else if (mounted && !ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _lt(
                    context,
                    'Wi-Fi baglantisi kurulamadı. Lutfen SSID/sifreyi kontrol edip tekrar deneyin.',
                  ),
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint('[BLE][SSID][sheet] auto provisioning failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${_lt(context, 'Wi-Fi gonderimi basarisiz')}: $e',
                ),
              ),
            );
          }
        }
      }
    }

    return _BleScanOutcome.success;
  }

  // Prefill SSID from previously picked/stored value
  Future<void> _prefillLastSsid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('last_ssid');
      if (last != null && last.trim().isNotEmpty) {
        _ssidCtl.text = last.trim();
        debugPrint('[BLE][UI] Prefilled SSID from last_ssid="$last"');
      } else {
        debugPrint('[BLE][UI] No stored SSID found.');
      }
    } catch (e, st) {
      debugPrint('[BLE][UI] Failed to prefill SSID: $e');
      debugPrint(st.toString());
    }
  }

  String _bestName(ScanResult r) {
    final adv = r.advertisementData.advName.trim();
    final plat = r.device.platformName.trim();
    return adv.isNotEmpty
        ? adv
        : (plat.isNotEmpty ? plat : r.device.remoteId.str);
  }

  bool _matchesArtAir(String name, AdvertisementData adv) {
    final okName = isKnownBleName(name);
    final okSvc = adv.serviceUuids.any((u) => _guidEq(u, kSvcUuidHint));
    return okName || okSvc;
  }

  void _scheduleAutoPickIfSingleCandidate() {
    if (!mounted ||
        _selected != null ||
        _autoConnectInProgress ||
        !_allowAutomaticBleConnect) {
      return;
    }
    final candidates = _found.values
        .where((r) {
          final name = _bestName(r);
          return _matchesArtAir(name, r.advertisementData);
        })
        .toList(growable: false);

    _autoPickTimer?.cancel();
    if (candidates.length != 1) return;

    final only = candidates.first.device;
    _autoPickTimer = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted || _selected != null || _autoConnectInProgress) return;
      final nowCandidates = _found.values
          .where((r) {
            final name = _bestName(r);
            return _matchesArtAir(name, r.advertisementData);
          })
          .toList(growable: false);
      if (nowCandidates.length != 1) return;
      if (nowCandidates.first.device.remoteId != only.remoteId) return;

      _autoConnectInProgress = true;
      try {
        debugPrint(
          '[BLE][AUTO] single ArtAir candidate -> auto connect ${only.remoteId.str}',
        );
        await _connect(only, autoScanAfterConnect: true);
      } finally {
        _autoConnectInProgress = false;
      }
    });
  }

  Future<void> _autoScanWifiViaBle() async {
    if (!mounted || _selected == null) return;
    if (_wifiScanInFlight) return;
    final rid = _selected!.remoteId.str;
    if (_autoScannedForRemoteId == rid) return;
    // Cihaz bağlandıktan hemen sonra GATT/notify hazır olmayabiliyor.
    // Bu nedenle kısa gecikme ile 2 denemeye kadar otomatik SSID taraması yap.
    for (var i = 0; i < 2; i++) {
      if (!mounted || _selected == null) return;
      await Future<void>.delayed(Duration(milliseconds: i == 0 ? 700 : 1100));
      final outcome = await _scanWifiViaBle();
      if (outcome == _BleScanOutcome.success) {
        _autoScannedForRemoteId = rid;
        return;
      }
      if (outcome == _BleScanOutcome.missingPairToken) {
        debugPrint(
          '[BLE][SSID][sheet] auto scan stopped: missing pair token for selected device',
        );
        return;
      }
      debugPrint(
        '[BLE][SSID][sheet] auto scan retry=${i + 1} outcome=$outcome',
      );
    }
  }

  Future<void> _startScan({bool fromAutoRetry = false}) async {
    if (_scanning) return;
    if (mounted) setState(() => _scanning = true);
    _found.clear();
    _foundAny.clear();

    // iOS'ta no-op olabilir ama deneriz
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {}

    // Adapter state'i güvenli şekilde al (iOS'ta kısa süre stale/off gelebiliyor)
    var st = await safeAdapterState(timeout: const Duration(seconds: 5));
    if (st != BluetoothAdapterState.on) {
      final becameOn = await _waitForAdapterOn(
        timeout: const Duration(seconds: 3),
      );
      if (becameOn) {
        st = BluetoothAdapterState.on;
      }
    }
    for (var i = 0; i < 2 && st == BluetoothAdapterState.off; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
      st = await safeAdapterState(timeout: const Duration(seconds: 1));
    }
    final definitelyOff =
        st == BluetoothAdapterState.off &&
        FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off;
    if (definitelyOff) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_lt(context, 'Bluetooth kapalı. Lütfen açın.')),
          ),
        );
        setState(() => _scanning = false);
      }
      if (!fromAutoRetry && !_didAutoRescan) {
        _didAutoRescan = true;
        Future<void>.delayed(const Duration(milliseconds: 900), () async {
          if (!mounted || _selected != null) return;
          debugPrint('[BLE][AUTO] initial scan could not start, retrying once');
          await _startScan(fromAutoRetry: true);
        });
      }
      return;
    }

    // Eski dinleyiciyi kapat
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      bool changed = false;
      for (final r in results) {
        final id = r.device.remoteId;
        final prevAny = _foundAny[id];
        if (prevAny == null || prevAny.rssi != r.rssi) {
          _foundAny[id] = r;
        }

        final name = _bestName(r);
        final isOurs = _matchesArtAir(name, r.advertisementData);
        if (!_onlyArt || isOurs) {
          final prev = _found[id];
          if (prev == null || prev.rssi != r.rssi) {
            _found[id] = r;
            changed = true;
          }
        }
      }
      if (changed && mounted) {
        setState(() {});
        _scheduleAutoPickIfSingleCandidate();
      }
    });

    // Yeni tarama öncesi emin ol: durdur
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        androidUsesFineLocation: true,
      );
      // Single-candidate auto-connect is handled by _scheduleAutoPickIfSingleCandidate.
      // Keep a single strategy to avoid duplicate connect attempts on iOS.
      if (!fromAutoRetry) {
        Future<void>.delayed(const Duration(seconds: 2), () async {
          if (!mounted || _selected != null || _didAutoRescan) return;
          final hasAny = _foundAny.isNotEmpty;
          final hasArt = _found.values.any((r) {
            final name = _bestName(r);
            return _matchesArtAir(name, r.advertisementData);
          });
          if (hasAny || hasArt) return;
          _didAutoRescan = true;
          debugPrint('[BLE][AUTO] initial scan empty -> auto refresh once');
          try {
            await _stopScan();
          } catch (_) {}
          await _startScan(fromAutoRetry: true);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_lt(context, 'BLE tarama başlatılamadı')}: $e'),
          ),
        );
      }
      if (!fromAutoRetry && !_didAutoRescan) {
        _didAutoRescan = true;
        Future<void>.delayed(const Duration(milliseconds: 900), () async {
          if (!mounted || _selected != null) return;
          debugPrint('[BLE][AUTO] scan start failed -> retry once');
          await _startScan(fromAutoRetry: true);
        });
      }
    }

    // Her ihtimale karşı süre bitince kapat (platform bazen otomatik kapatmaz)
    Future.delayed(const Duration(seconds: 12)).whenComplete(() async {
      try {
        await _stopScan();
      } catch (_) {}
    });
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
    final wasScanning = _scanning;
    if (mounted && _scanning) {
      setState(() => _scanning = false);
    } else {
      _scanning = false;
    }

    // İlk otomatik tarama boş bittiyse, kullanıcı refresh'e basmadan önce
    // bir kez daha otomatik tarama yap (refresh etkisini otomatikleştir).
    if (wasScanning &&
        _selected == null &&
        _foundAny.isEmpty &&
        !_didAutoRescan &&
        mounted) {
      _didAutoRescan = true;
      Future<void>.delayed(const Duration(milliseconds: 450), () async {
        if (!mounted || _selected != null) return;
        debugPrint('[BLE][AUTO] scan completed empty -> auto refresh once');
        await _startScan(fromAutoRetry: true);
      });
    }
  }

  Future<void> _connect(
    BluetoothDevice d, {
    bool autoScanAfterConnect = false,
  }) async {
    final rid = d.remoteId.str;
    if (_connectInFlight) {
      _pendingConnectDevice = d;
      if (_connectInFlightId == rid) {
        debugPrint('[BLE][UI] connect ignored (already in-flight) -> $rid');
      } else {
        debugPrint(
          '[BLE][UI] connect queued (in-flight=$_connectInFlightId) -> $rid',
        );
      }
      return;
    }
    _connectInFlight = true;
    _connectInFlightId = rid;
    _pendingConnectDevice = null;
    await _stopScan();
    debugPrint('[BLE][UI] connect requested -> ${d.remoteId.str}');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_lt(context, 'Bağlanılıyor')}: ${d.remoteId.str}'),
        ),
      );
    }
    try {
      try {
        final cur = await _safeConnectionState(
          d,
          timeout: const Duration(milliseconds: 800),
        );
        if (cur != BluetoothConnectionState.connected) {
          await d.connect(timeout: const Duration(seconds: 10));
        }
      } catch (e) {
        // Some stacks throw "already_connected"; treat as connected.
        final s = e.toString().toLowerCase();
        if (!(s.contains('already') && s.contains('connect'))) rethrow;
      }
      if (!mounted) return;
      setState(() => _selected = d);
      debugPrint('[BLE][UI] connected to ${d.remoteId.str}');

      final canAuth = await _canAttemptBleAuth(d);
      if (canAuth) {
        await _ensureBleSessionAuthed(d);
      } else {
        debugPrint(
          '[BLE][UI] connected without auth material; skipping auto auth idHints=${_deviceIdCandidates(d).join(",")}',
        );
        _showMissingProvisionHintOnce();
      }
      if (autoScanAfterConnect && await _canProvisionViaBle(d)) {
        await _autoScanWifiViaBle();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_lt(context, 'BLE bağlanamadı')}: $e')),
      );
      debugPrint('[BLE][UI] connect failed: $e');
    } finally {
      _connectInFlight = false;
      _connectInFlightId = null;
      final next = _pendingConnectDevice;
      if (next != null && next.remoteId != d.remoteId) {
        _pendingConnectDevice = null;
        unawaited(_connect(next));
      }
    }
  }

  Future<Map<String, dynamic>?> _bleRequestNonce({
    required BluetoothCharacteristic cmdChar,
    required BluetoothCharacteristic infoChar,
  }) async {
    final framer = _BleJsonFramer();
    final completer = Completer<Map<String, dynamic>>();
    StreamSubscription<List<int>>? sub;
    try {
      try {
        await infoChar.setNotifyValue(true);
      } catch (_) {}
      sub = infoChar.lastValueStream.listen((data) {
        try {
          final chunk = utf8.decode(data, allowMalformed: true);
          for (final js in framer.feed(chunk)) {
            final obj = jsonDecode(js);
            if (obj is! Map<String, dynamic>) continue;
            final auth = obj['auth'];
            if (auth is Map) {
              final a = auth.cast<String, dynamic>();
              if (a['nonce'] is String) {
                if (!completer.isCompleted) completer.complete(a);
                return;
              }
            }
          }
        } catch (_) {}
      });

      final payload = jsonEncode({'cmd': 'GET_NONCE'});
      await cmdChar.write(
        utf8.encode(payload),
        withoutResponse: !cmdChar.properties.write,
      );

      return await completer.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[BLE][AUTH][sheet] GET_NONCE error: $e');
      return null;
    } finally {
      await sub?.cancel();
    }
  }

  Future<List<int>?> _loadAnyPrivKeyD32() async {
    try {
      final ownerB64 = await _sheetSecureStorage.read(
        key: 'owner_priv_d32_b64',
      );
      if (ownerB64 != null && ownerB64.trim().isNotEmpty) {
        final d = base64Decode(ownerB64.trim());
        if (d.length == 32) return d;
      }
    } catch (_) {}
    try {
      final clientB64 = await _sheetSecureStorage.read(key: _kClientPrivD32Key);
      if (clientB64 != null && clientB64.trim().isNotEmpty) {
        final d = base64Decode(clientB64.trim());
        if (d.length == 32) return d;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _bleAuthWithSignature({
    required BluetoothCharacteristic cmdChar,
    required BluetoothCharacteristic infoChar,
    required String nonceB64,
    required String deviceId,
  }) async {
    final useDebugKey = kDebugMode && kBleAuthDebugStaticKey;
    final priv = useDebugKey
        ? kBleAuthDebugPrivKeyP256
        : await _loadAnyPrivKeyD32();
    if (priv == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bu telefonda BLE imza anahtarı yok. Owner/davet kurulumu gerekli.',
            ),
          ),
        );
      }
      return false;
    }

    final messageToSign = 'AAC1|$deviceId|$nonceB64';
    final messageBytes = utf8.encode(messageToSign);
    debugPrint('[BLE][AUTH] nonceB64=$nonceB64');
    debugPrint('[BLE][AUTH] deviceId=$deviceId');
    debugPrint('[BLE][AUTH] messageLen=${messageBytes.length}');
    final pubKeyBytes = _publicKeyBytesFromPrivP256(priv);
    final pubKeyFp = (pubKeyBytes != null)
        ? _sha256Fingerprint8(pubKeyBytes)
        : '';
    final msgHashFp = _sha256Fingerprint8(messageBytes);
    debugPrint('[BLE][AUTHDBG] alg=ECDSA_P256');
    debugPrint('[BLE][AUTHDBG] pubKeyLen=${pubKeyBytes?.length ?? 0}');
    debugPrint('[BLE][AUTHDBG] pubKeyFp=$pubKeyFp');
    debugPrint('[BLE][AUTHDBG] msgHashFp=$msgHashFp');

    if (useDebugKey) {
      debugPrint('[BLE][AUTH] using debug static key');
    }
    final sigBytes = _ecdsaSignBytesP256(privD32: priv, msgBytes: messageBytes);
    debugPrint('[BLE][AUTHDBG] sigLen=${sigBytes.length}');
    final sigB64 = base64Encode(sigBytes);
    debugPrint('[BLE][AUTH] signatureLen=${sigBytes.length}');
    final framer = _BleJsonFramer();
    final completer = Completer<bool>();
    StreamSubscription<List<int>>? sub;
    try {
      try {
        await infoChar.setNotifyValue(true);
      } catch (_) {}
      sub = infoChar.lastValueStream.listen((data) {
        try {
          final chunk = utf8.decode(data, allowMalformed: true);
          for (final js in framer.feed(chunk)) {
            final obj = jsonDecode(js);
            if (obj is! Map<String, dynamic>) continue;
            final auth = obj['auth'];
            if (auth is Map) {
              final a = auth.cast<String, dynamic>();
              if (a['ok'] is bool) {
                if (!completer.isCompleted) completer.complete(a['ok'] == true);
                return;
              }
            }
          }
        } catch (_) {}
      });

      final payload = jsonEncode(<String, dynamic>{
        'cmd': 'AUTH',
        'nonce': nonceB64,
        'sig': sigB64,
      });
      await cmdChar.write(
        utf8.encode(payload),
        withoutResponse: !cmdChar.properties.write,
      );

      return await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('[BLE][AUTH][sheet] AUTH error: $e');
      return false;
    } finally {
      await sub?.cancel();
    }
  }

  Future<bool> _bleAuthWithSignaturePayload({
    required BluetoothCharacteristic cmdChar,
    required BluetoothCharacteristic infoChar,
    required String nonceB64,
    required String sigB64,
  }) async {
    final framer = _BleJsonFramer();
    final completer = Completer<bool>();
    StreamSubscription<List<int>>? sub;
    try {
      try {
        await infoChar.setNotifyValue(true);
      } catch (_) {}
      sub = infoChar.lastValueStream.listen((data) {
        try {
          final chunk = utf8.decode(data, allowMalformed: true);
          for (final js in framer.feed(chunk)) {
            final obj = jsonDecode(js);
            if (obj is! Map<String, dynamic>) continue;
            final auth = obj['auth'];
            if (auth is Map) {
              final a = auth.cast<String, dynamic>();
              if (a['ok'] is bool) {
                if (!completer.isCompleted) completer.complete(a['ok'] == true);
                return;
              }
            }
          }
        } catch (_) {}
      });

      final payload = jsonEncode(<String, dynamic>{
        'cmd': 'AUTH',
        'nonce': nonceB64,
        'sig': sigB64,
      });
      await cmdChar.write(
        utf8.encode(payload),
        withoutResponse: !cmdChar.properties.write,
      );

      return await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('[BLE][AUTH][sheet] AUTH error: $e');
      return false;
    } finally {
      await sub?.cancel();
    }
  }

  Future<bool> _bleAuthWithQrToken({
    required BluetoothCharacteristic cmdChar,
    required BluetoothCharacteristic infoChar,
    required String pairToken,
  }) async {
    final framer = _BleJsonFramer();
    final completer = Completer<bool>();
    StreamSubscription<List<int>>? sub;
    try {
      try {
        await infoChar.setNotifyValue(true);
      } catch (_) {}
      sub = infoChar.lastValueStream.listen((data) {
        try {
          final chunk = utf8.decode(data, allowMalformed: true);
          for (final js in framer.feed(chunk)) {
            final obj = jsonDecode(js);
            if (obj is! Map<String, dynamic>) continue;
            final auth = obj['auth'];
            if (auth is Map) {
              final a = auth.cast<String, dynamic>();
              if (a['ok'] is bool) {
                if (!completer.isCompleted) completer.complete(a['ok'] == true);
                return;
              }
            }
          }
        } catch (_) {}
      });

      final payload = jsonEncode(<String, dynamic>{
        'cmd': 'AUTH',
        'qrToken': pairToken,
      });
      await cmdChar.write(
        utf8.encode(payload),
        withoutResponse: !cmdChar.properties.write,
      );

      return await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('[BLE][AUTH][sheet] AUTH(qr) error: $e');
      return false;
    } finally {
      await sub?.cancel();
    }
  }

  Future<bool> _bleAuthWithSetup({
    required BluetoothCharacteristic cmdChar,
    required BluetoothCharacteristic infoChar,
    required String user,
    required String pass,
    String? idHint,
  }) async {
    final framer = _BleJsonFramer();
    final completer = Completer<bool>();
    String? discoveredPairToken;
    String? discoveredIdHint;
    StreamSubscription<List<int>>? sub;
    try {
      try {
        await infoChar.setNotifyValue(true);
      } catch (_) {}
      sub = infoChar.lastValueStream.listen((data) {
        try {
          final chunk = utf8.decode(data, allowMalformed: true);
          for (final js in framer.feed(chunk)) {
            final obj = jsonDecode(js);
            if (obj is! Map<String, dynamic>) continue;
            final auth = obj['auth'];
            if (auth is Map) {
              final a = auth.cast<String, dynamic>();
              final pairToken = (a['pairToken'] ?? '').toString().trim();
              if (pairToken.isNotEmpty) {
                discoveredPairToken = pairToken;
                final id6 = (a['id6'] ?? '').toString().trim();
                final deviceId = (a['deviceId'] ?? '').toString().trim();
                discoveredIdHint = id6.isNotEmpty
                    ? id6
                    : (deviceId.isNotEmpty ? deviceId : idHint);
                _runtimePairToken = pairToken;
                _runtimePairTokenIdHint = discoveredIdHint;
              }
              if (a['ok'] is bool) {
                if (!completer.isCompleted) completer.complete(a['ok'] == true);
                return;
              }
            }
          }
        } catch (_) {}
      });

      final payload = jsonEncode(<String, dynamic>{
        'type': 'AUTH_SETUP',
        'user': user,
        'pass': pass,
      });
      await cmdChar.write(
        utf8.encode(payload),
        withoutResponse: !cmdChar.properties.write,
      );

      final ok = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      if (ok &&
          discoveredPairToken != null &&
          discoveredPairToken!.isNotEmpty &&
          widget.onPairTokenDiscovered != null) {
        try {
          await widget.onPairTokenDiscovered!(
            discoveredPairToken!,
            discoveredIdHint ?? idHint,
          );
        } catch (e) {
          debugPrint('[BLE][AUTH][sheet] pairToken persist error: $e');
        }
      }
      return ok;
    } catch (e) {
      debugPrint('[BLE][AUTH][sheet] AUTH_SETUP error: $e');
      return false;
    } finally {
      await sub?.cancel();
    }
  }

  // Establishes an authorized BLE session.
  // - Owned devices require signature AUTH (owner/user key).
  // - Unowned devices require AUTH_SETUP (factory user/pass).
  Future<bool> _ensureBleSessionAuthed(BluetoothDevice device) async {
    try {
      final chars = await _resolveProvInfoChars(device);
      if (chars == null) {
        debugPrint('[BLE][AUTH][sheet] Failed to resolve characteristics');
        return false;
      }

      final cmdChar = chars.cmd ?? chars.prov;
      final infoChar = chars.info;

      final nonceObj = await _bleRequestNonce(
        cmdChar: cmdChar,
        infoChar: infoChar,
      );
      final nonceB64 = (nonceObj?['nonce'] as String?)?.trim();
      final owned = nonceObj?['owned'] == true;
      final nonceId6Raw = (nonceObj?['id6'] as String?)?.trim();
      final nonceDeviceIdRaw = (nonceObj?['deviceId'] as String?)?.trim();
      final noncePairTokenRaw = (nonceObj?['pairToken'] as String?)?.trim();
      final nonceId6 = (nonceId6Raw != null && nonceId6Raw.isNotEmpty)
          ? (normalizeDeviceId6(nonceId6Raw) ?? nonceId6Raw)
          : ((nonceDeviceIdRaw != null && nonceDeviceIdRaw.isNotEmpty)
                ? (normalizeDeviceId6(nonceDeviceIdRaw) ?? nonceDeviceIdRaw)
                : null);
      if (nonceId6 != null && nonceId6.isNotEmpty) {
        _sessionIdHintFromNonce = nonceId6;
      }
      if (noncePairTokenRaw != null && noncePairTokenRaw.isNotEmpty) {
        _runtimePairToken = noncePairTokenRaw;
        _runtimePairTokenIdHint = nonceId6;
        if (widget.onPairTokenDiscovered != null) {
          try {
            await widget.onPairTokenDiscovered!(noncePairTokenRaw, nonceId6);
          } catch (e) {
            debugPrint('[BLE][AUTH][sheet] nonce pairToken persist error: $e');
          }
        }
      }
      if (nonceB64 == null || nonceB64.isEmpty) {
        debugPrint('[BLE][AUTH][sheet] GET_NONCE returned empty');
        return false;
      }

      final widgetId6 = _normalizedIdHintForSheet(widget.targetId6);
      final deviceNameId6 = _normalizedIdHintForSheet(
        _extractId6FromBleName(device.platformName),
      );
      final actualId6 =
          _normalizedIdHintForSheet(nonceId6) ??
          _normalizedIdHintForSheet(_sessionIdHintFromNonce) ??
          deviceNameId6;

      bool ok = false;
      if (owned) {
        final id6 = (actualId6 ?? widgetId6 ?? '').trim();
        ok = await _bleAuthWithSignature(
          cmdChar: cmdChar,
          infoChar: infoChar,
          nonceB64: nonceB64,
          deviceId: id6,
        );
      } else {
        String u = widget.setupUser?.trim() ?? '';
        String p = widget.setupPass?.trim() ?? '';
        final derivedIdHint = (actualId6 ?? widgetId6 ?? '').trim();

        // Never send setup creds if they clearly belong to another device.
        if (actualId6 != null &&
            widgetId6 != null &&
            actualId6.isNotEmpty &&
            widgetId6.isNotEmpty &&
            actualId6 != widgetId6) {
          debugPrint(
            '[BLE][AUTH][sheet] setup creds target mismatch widget=$widgetId6 actual=$actualId6; ignoring widget setup creds',
          );
          u = '';
          p = '';
        }

        // QR ekranından gelmeyen akışta setup creds'i id6 bazlı cache'den yükle.
        if ((u.isEmpty || p.isEmpty) &&
            derivedIdHint.isNotEmpty &&
            widget.loadSetupCreds != null) {
          try {
            final creds = await widget.loadSetupCreds!(derivedIdHint);
            u = (creds?['user'] ?? '').trim();
            p = (creds?['pass'] ?? '').trim();
            if (u.isNotEmpty && p.isNotEmpty) {
              debugPrint(
                '[BLE][AUTH][sheet] setup creds loaded from cache id6=$derivedIdHint',
              );
            }
          } catch (e) {
            debugPrint('[BLE][AUTH][sheet] setup creds load failed: $e');
          }
        }

        // IR-first flow fallback: when no cached setup creds exist yet,
        // derive legacy setup credentials from id6 and try AUTH_SETUP.
        if ((u.isEmpty || p.isEmpty) && derivedIdHint.isNotEmpty) {
          u = 'AAC';
          p = 'aac$derivedIdHint';
          debugPrint(
            '[BLE][AUTH][sheet] using fallback setup creds for id6=$derivedIdHint (auto)',
          );
        }

        if (u.isEmpty || p.isEmpty) {
          // Eğer daha önce token keşfedildiyse/setup cache yoksa QR token ile auth dene.
          final qr = await _resolvePairTokenForDevice(device);
          if (qr != null && qr.isNotEmpty) {
            ok = await _bleAuthWithQrToken(
              cmdChar: cmdChar,
              infoChar: infoChar,
              pairToken: qr,
            );
          }
        } else {
          ok = await _bleAuthWithSetup(
            cmdChar: cmdChar,
            infoChar: infoChar,
            user: u,
            pass: p,
            idHint: derivedIdHint,
          );
          if (ok && kBleClaimOwnerOnQr) {
            final claimed = await _bleClaimOwner(
              cmdChar: cmdChar,
              infoChar: infoChar,
              user: u,
              pass: p,
            );
            if (claimed && widget.onOwnerClaimed != null) {
              try {
                await widget.onOwnerClaimed!();
              } catch (_) {}
            }
            if (!claimed && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Owner atanamadı (CLAIM_REQUEST).'),
                ),
              );
            }
          }
        }

        if (!ok && (u.isEmpty || p.isEmpty)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Kurulum bilgisi bulunamadı. Soft recovery açıp cihazı tekrar eşleştirin.',
                ),
              ),
            );
          }
        }
      }

      _bleSessionAuthed = ok;
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_lt(context, 'BLE doğrulama başarısız.'))),
        );
      }
      return ok;
    } catch (e) {
      debugPrint('[BLE][AUTH][sheet] Authentication error: $e');
      return false;
    }
  }

  Future<BluetoothConnectionState> _safeConnectionState(
    BluetoothDevice device, {
    Duration timeout = const Duration(milliseconds: 700),
  }) async {
    try {
      return await device.connectionState.first.timeout(
        timeout,
        onTimeout: () => BluetoothConnectionState.disconnected,
      );
    } catch (_) {
      return BluetoothConnectionState.disconnected;
    }
  }

  Future<bool> _waitForAdapterOn({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
      return true;
    }
    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(timeout);
      return true;
    } catch (_) {
      return FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
    }
  }

  Future<void> _disconnect() async {
    final d = _selected;
    if (d == null) return;
    try {
      await safeBleDisconnect(d, reason: 'ble_ui_disconnect');
    } catch (_) {}
    _autoScannedForRemoteId = null;
    if (mounted) setState(() => _selected = null);
    debugPrint('[BLE][UI] disconnected');
  }

  Future<void> _joinWithInvite() async {
    final d = _selected;
    if (d == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_lt(context, 'Önce BLE cihazı seçin.'))),
        );
      }
      return;
    }

    final ctl = TextEditingController();
    final inviteStr = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(_lt(context, 'Davet JSON ile katıl (BLE)')),
          content: TextField(
            controller: ctl,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'QR içeriğini buraya yapıştırın',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(_lt(context, 'İptal')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
              child: Text(_lt(context, 'Katıl')),
            ),
          ],
        );
      },
    );
    if (inviteStr == null || inviteStr.isEmpty) return;

    Map<String, dynamic>? inviteObj;
    try {
      final obj = jsonDecode(inviteStr);
      if (obj is Map<String, dynamic>) {
        inviteObj = obj;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_lt(context, 'Geçersiz JSON')}: $e')),
        );
      }
      return;
    }
    if (inviteObj == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_lt(context, 'Geçersiz davet nesnesi'))),
        );
      }
      return;
    }

    try {
      final pub = await _getOrCreateClientPubKeyB64();
      if (pub != null && pub.isNotEmpty) inviteObj['user_pubkey'] = pub;
      final chars = await _resolveProvInfoChars(d);
      if (chars == null || chars.cmd == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _lt(
                  context,
                  'Gerekli BLE özellikleri bulunamadı (CMD karakteristiği).',
                ),
              ),
            ),
          );
        }
        return;
      }
      final cmd = chars.cmd!;
      final payload = jsonEncode(<String, dynamic>{
        'type': 'JOIN',
        'invite': inviteObj,
      });
      await cmd.write(
        utf8.encode(payload),
        withoutResponse: !cmd.properties.write,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_lt(context, 'JOIN komutu BLE üzerinden gönderildi')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_lt(context, 'JOIN hatası')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = _found.values.toList()
      ..sort((a, b) => (b.rssi).compareTo(a.rssi));

    // iOS: klavye açılınca sheet’i yukarı it
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bluetooth, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _lt(context, 'BLE ile Kurulum'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  FilterChip(
                    label: Text(
                      _onlyArt
                          ? _lt(context, 'Filtre: ArtAir')
                          : _lt(context, 'Filtre: Tümü'),
                    ),
                    selected: _onlyArt,
                    onSelected: (v) {
                      setState(() {
                        _onlyArt = v;
                        _found.clear();
                      });
                      if (!_scanning) {
                        _startScan();
                      } // filtre değişince otomatik yeniden tara
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _lt(context, 'Yeniden Tara'),
                    onPressed: _scanning ? null : _startScan,
                    icon: _scanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: devices.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _scanning
                              ? _lt(context, '[BLE] Tarama yapılıyor...')
                              : (_onlyArt
                                    ? _lt(
                                        context,
                                        'Yakında ArtAir cihazı bulunamadı (Filtre açık).',
                                      )
                                    : _lt(context, 'Yakında cihaz bulunamadı')),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: devices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = devices[i];
                          final name = _bestName(r);
                          final sel = _selected?.remoteId == r.device.remoteId;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              sel
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                            ),
                            title: Text(name),
                            subtitle: Text(
                              '${r.device.remoteId.str}   RSSI ${r.rssi}',
                            ),
                            onTap: () async {
                              final prev = _selected;
                              if (mounted) {
                                // Reflect selection immediately; connection may still be in-flight.
                                setState(() => _selected = r.device);
                              }
                              if (sel) return;
                              if (_connectInFlight) {
                                _pendingConnectDevice = r.device;
                                return;
                              }
                              if (prev != null &&
                                  prev.remoteId != r.device.remoteId) {
                                try {
                                  await safeBleDisconnect(
                                    prev,
                                    reason: 'ble_sheet_switch_device',
                                  );
                                } catch (_) {}
                              }
                              await _connect(r.device);
                            },
                          );
                        },
                      ),
              ),

              const SizedBox(height: 12),

              TextField(
                controller: _ssidCtl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.wifi),
                  labelText: _lt(context, 'Wi-Fi SSID'),
                  hintText: _lt(context, 'Ağ adını girin veya tara'),
                  suffixIcon: IconButton(
                    tooltip: _lt(context, 'Ağları tara'),
                    icon: _wifiScanInFlight
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find),
                    onPressed: _wifiScanInFlight
                        ? null
                        : () async {
                            // Önce BLE üzerinden WiFi listesini çekmeyi dene
                            final outcome = await _scanWifiViaBle();
                            // Eğer BLE başarısız olursa veya boş dönerse, HTTP fallback kullan
                            if (outcome != _BleScanOutcome.success) {
                              final scan = widget.onScanWifi;
                              if (scan != null) {
                                await scan(context, _ssidCtl);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _lt(
                                        context,
                                        'WiFi tarama başarısız. Cihaz seçili olduğundan emin olun.',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            }
                            // Eğer BLE başarılıysa, _scanWifiViaBle zaten modal gösteriyor
                          },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pwdCtl,
                obscureText: true,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline),
                  labelText: _lt(context, 'Wi-Fi Şifre'),
                ),
              ),

              const SizedBox(height: 12),
              // ✅ Butonları Wrap ile sarmalayarak overflow'u önle
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceEvenly,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      final ssid = _ssidCtl.text.trim();
                      final pass = _pwdCtl.text;

                      debugPrint('[UI] BLE SEND tapped (ssid="' + ssid + '")');

                      if (ssid.isEmpty) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('SSID boş olamaz')),
                          );
                        }
                        return;
                      }

                      debugPrint('[BLE] calling onSend callback from sheet');
                      final ok = await widget.onSend(ssid, pass, _selected);
                      if (!mounted) return;
                      if (ok) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Gönder'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _selected != null ? _joinWithInvite : null,
                    icon: const Icon(Icons.text_snippet_outlined, size: 18),
                    label: const Text('Davet JSON'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _selected != null ? _disconnect : null,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('Kes'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _scanning ? '[BLE] Tarama yapılıyor...' : '[BLE] Hazır',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
