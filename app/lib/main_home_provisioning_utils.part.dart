part of 'main.dart';

String _bleSetupUserKey(String id6) => 'ble_setup_user_$id6';
String _bleSetupPassKey(String id6) => 'ble_setup_pass_$id6';

extension _HomeScreenProvisioningUtilsPart on _HomeScreenState {
  static const String _bleTargetId6Key = 'ble_target_id6';

  String _preferredBrandForDeviceHint(String rawHint) {
    final activeBrand = _activeDevice?.brand.trim() ?? '';
    if (activeBrand.isNotEmpty) return activeBrand;
    final runtimeBrand = brandFromDeviceProduct(
      state?.deviceProduct ?? '',
    ).trim();
    if (runtimeBrand.isNotEmpty) return runtimeBrand;
    final hintedBrand = brandFromDeviceProduct(
      deviceProductSlugFromAny(rawHint),
    ).trim();
    if (hintedBrand.isNotEmpty) return hintedBrand;
    return kDefaultDeviceBrand;
  }

  void _allowNetworkAutoPolling() {
    if (_networkAutoPollingAllowed) return;
    _networkAutoPollingAllowed = true;
    debugPrint('[NET] user opted into network polling');
    _startPolling();
  }

  bool _shouldAutoStartConnectivity() {
    if (_cloudLoggedIn()) return true;
    if (_devices.isNotEmpty) return true;
    final typedBase = _normalizeBaseUrl(_urlCtl.text);
    final currentBase = _normalizeBaseUrl(baseUrl);
    final candidate = typedBase ?? currentBase ?? '';
    if (candidate.isEmpty) return false;
    final host = Uri.tryParse(candidate)?.host.trim() ?? '';
    if (host.isEmpty) return false;
    return true;
  }

  Future<void> _storeBleSetupCredsForId6({
    required String id6,
    required String user,
    required String pass,
  }) async {
    final normalized = normalizeDeviceId6(id6) ?? id6.trim();
    if (normalized.isEmpty) return;
    try {
      await _secureStorage.write(
        key: _bleSetupUserKey(normalized),
        value: user,
      );
      await _secureStorage.write(
        key: _bleSetupPassKey(normalized),
        value: pass,
      );
    } catch (_) {}
  }

  Future<void> _clearBleSetupCredsForId6(String id6) async {
    final normalized = normalizeDeviceId6(id6) ?? id6.trim();
    try {
      if (normalized.isNotEmpty) {
        await _secureStorage.delete(key: _bleSetupUserKey(normalized));
        await _secureStorage.delete(key: _bleSetupPassKey(normalized));
      }
      if (id6.trim().isNotEmpty && id6.trim() != normalized) {
        await _secureStorage.delete(key: _bleSetupUserKey(id6.trim()));
        await _secureStorage.delete(key: _bleSetupPassKey(id6.trim()));
      }
    } catch (_) {}
  }

  Future<Map<String, String>?> _loadBleSetupCredsForId6(String id6) async {
    final normalized = normalizeDeviceId6(id6) ?? id6.trim();
    if (normalized.isEmpty) return null;
    try {
      final user = await _secureStorage.read(key: _bleSetupUserKey(normalized));
      final pass = await _secureStorage.read(key: _bleSetupPassKey(normalized));
      final legacyUser = await _secureStorage.read(key: _bleSetupUserKey(id6));
      final legacyPass = await _secureStorage.read(key: _bleSetupPassKey(id6));
      final resolvedUser = (user != null && user.trim().isNotEmpty)
          ? user
          : legacyUser;
      final resolvedPass = (pass != null && pass.trim().isNotEmpty)
          ? pass
          : legacyPass;
      if (resolvedUser == null || resolvedUser.trim().isEmpty) return null;
      if (resolvedPass == null || resolvedPass.trim().isEmpty) return null;
      final passTrim = resolvedPass.trim();
      if (passTrim.length >= 9 &&
          passTrim.toLowerCase().startsWith('aac') &&
          RegExp(r'^[aA][aA][cC][0-9]{6}$').hasMatch(passTrim)) {
        final passId6 = passTrim.substring(3).toUpperCase();
        if (passId6 != normalized.toUpperCase()) {
          debugPrint(
            '[BLE][SETUP] stale cached pass ignored id6=$normalized passId6=$passId6',
          );
          return null;
        }
      }
      if ((legacyUser != null || legacyPass != null) && normalized != id6) {
        await _secureStorage.write(
          key: _bleSetupUserKey(normalized),
          value: resolvedUser.trim(),
        );
        await _secureStorage.write(
          key: _bleSetupPassKey(normalized),
          value: resolvedPass.trim(),
        );
      }
      return <String, String>{
        'user': resolvedUser.trim(),
        'pass': resolvedPass.trim(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<bool> _ensurePairTokenForAp({required bool prompt}) async {
    final u = Uri.tryParse(api.baseUrl);
    final onDeviceAp = (u != null && u.host == '192.168.4.1');
    if (!onDeviceAp) return true;
    final headers = api.authHeaders();
    final hasLocalAuth =
        headers.containsKey('Authorization') ||
        ((headers['X-Session-Token'] ?? '').isNotEmpty &&
            (headers['X-Session-Nonce'] ?? '').isNotEmpty);
    if (hasLocalAuth) return true;
    if (!prompt || !mounted) return false;

    _pauseBackground(reason: 'pair-qr');
    try {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(t.literal('Yetkilendirme gerekli')),
            content: const Text(
              'AP kurulumu için önce Bluetooth ile cihaza bağlanıp '
              'soft recovery penceresini açın.\n\n'
              'Bluetooth ekranına gidip tekrar deneyin.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(t.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop('ble'),
                child: Text(t.literal('Bluetooth')),
              ),
            ],
          );
        },
      );
      if (choice == 'ble') {
        await _openBleManageAndProvision();
      }
      final updated = api.authHeaders();
      return updated.containsKey('Authorization') ||
          ((updated['X-Session-Token'] ?? '').isNotEmpty &&
              (updated['X-Session-Nonce'] ?? '').isNotEmpty);
    } finally {
      _resumeBackground(reason: 'pair-qr');
    }
  }

  String? _normalizeDeviceId6(String raw) => normalizeDeviceId6(raw);

  String? _canonicalInviteId(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final canon = s.toLowerCase();
    final hexInviteId = RegExp(r'^[0-9a-f]{16}$|^[0-9a-f]{32}$');
    if (!hexInviteId.hasMatch(canon)) return null;
    return canon;
  }

  String _maskInviteId(String v) {
    final s = v.trim();
    if (s.length <= 6) return s;
    return '${s.substring(0, 4)}…${s.substring(s.length - 4)}';
  }

  Future<void> _ensureActiveDeviceForId6(String id6) async {
    final normalized = _normalizeDeviceId6(id6);
    if (normalized == null) return;
    final canonicalId = canonicalizeDeviceId(normalized) ?? normalized;

    _SavedDevice? found;
    for (final d in _devices) {
      final d6 = _normalizeDeviceId6(d.id);
      if (d6 == normalized) {
        found = d;
        break;
      }
    }

    found ??= _promotePlaceholderDeviceToCanonical(
      canonicalId: canonicalId,
      preferredPlaceholderId: _activeDeviceId,
      brandHint: _activeDevice?.brand,
      suffixHint: _activeDevice?.suffix,
      baseUrlHint: baseUrl,
    );

    if (found == null) {
      final thingName = thingNameFromAny(canonicalId);
      final storedPair =
          await _loadPairToken(normalized) ??
          await _loadPairToken(canonicalId) ??
          (thingName != null ? await _loadPairToken(thingName) : null);
      found = _SavedDevice(
        id: canonicalId,
        brand: _preferredBrandForDeviceHint(canonicalId),
        baseUrl: baseUrl,
        thingName: thingName,
        pairToken: storedPair,
      );
    }

    if (_activeDeviceId != found.id) {
      await _setActiveDevice(found);
    } else if (found.pairToken != null && found.pairToken!.trim().isNotEmpty) {
      api.setPairToken(found.pairToken!.trim());
    }
  }

  Future<bool> _bleProvisionSend({
    required String ssid,
    required String pass,
    BluetoothDevice? preferredDevice,
  }) async {
    if (_bleBusy) {
      debugPrint('[BLE] _bleProvisionSend ignored: already running');
      return false;
    }
    _bleBusy = true;
    debugPrint(
      '[BLE] ENTER _bleProvisionSend ssid=$ssid passLen=${pass.length}',
    );
    _setBlockingProgress(
      title: t.t('please_wait'),
      body: t.t('onb_wait_device_wifi'),
    );

    StreamSubscription<List<ScanResult>>? scanSub;
    BluetoothDevice? target = preferredDevice;
    try {
      final bleReady = await _ensureBluetoothOnWithUi();
      debugPrint(
        '[BLE] adapterReady=$bleReady now=${FlutterBluePlus.adapterStateNow}',
      );
      if (!bleReady) return false;

      HapticFeedback.lightImpact();
      _showSnack(t.t('connecting'));

      if (target == null) {
        try {
          final connected = FlutterBluePlus.connectedDevices;
          for (final d in connected) {
            if (isKnownBleName(d.platformName)) {
              target = d;
              break;
            }
          }
        } catch (_) {
          target = null;
        }
      } else {
        debugPrint(
          '[BLE] preferred device requested: ${target.remoteId.str} (${target.platformName})',
        );
      }
      if (target == null) {
        final collected = <ScanResult>[];
        scanSub = FlutterBluePlus.scanResults.listen((batch) {
          for (final r in batch) {
            if (!collected.any(
              (e) => e.device.remoteId.str == r.device.remoteId.str,
            )) {
              collected.add(r);
              debugPrint(
                '[BLE] seen: id=${r.device.remoteId.str} name=${r.device.platformName} adv=${r.advertisementData.advName}',
              );
            }
          }
        });
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
        await Future.delayed(const Duration(seconds: 6));
        await FlutterBluePlus.stopScan();
        try {
          await scanSub.cancel();
        } catch (_) {}

        BluetoothDevice? chosen;
        for (final r in collected) {
          final n1 = r.device.platformName;
          final n2 = r.advertisementData.advName;
          if (isKnownBleName(n1) || isKnownBleName(n2)) {
            chosen = r.device;
            break;
          }
        }

        if (chosen == null) {
          debugPrint('[BLE] no matching devices found');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Yakında uyumlu BLE cihazı bulunamadı.'),
              ),
            );
          }
          return false;
        }
        target = chosen;
        debugPrint(
          '[BLE] selected device: ${target.platformName} (${target.remoteId.str})',
        );
      }

      try {
        await target.connect(timeout: const Duration(seconds: 8));
      } catch (_) {}

      final services = await target.discoverServices();
      debugPrint('[BLE] discovered ${services.length} services');

      BluetoothService? prefSvc;
      try {
        prefSvc = services.firstWhere((s) => _guidEq(s.uuid, kSvcUuidHint));
        debugPrint('[BLE] preferred service found: ${kSvcUuidHint.str}');
      } catch (_) {
        prefSvc = null;
        debugPrint('[BLE] preferred service NOT found, fallback all services');
      }

      BluetoothCharacteristic? provChar;
      BluetoothCharacteristic? infoChar;
      BluetoothCharacteristic? cmdRecoveryChar;
      Iterable<BluetoothCharacteristic> scanChars(
        Iterable<BluetoothService> ss,
      ) sync* {
        for (final s in ss) {
          for (final c in s.characteristics) {
            yield c;
          }
        }
      }

      final scope = prefSvc != null ? [prefSvc] : services;
      for (final c in scanChars(scope)) {
        final canWrite =
            c.properties.write || c.properties.writeWithoutResponse;
        final canNotify = c.properties.notify;
        debugPrint(
          '[BLE] char ${c.uuid.str} props: write=$canWrite notify=$canNotify',
        );
        if (_guidEq(c.uuid, kProvCharUuidHint) && canWrite) provChar = c;
        if (_guidEq(c.uuid, kInfoCharUuidHint) && canNotify) infoChar = c;
        if (_guidEq(c.uuid, kCmdCharUuidHint) && canWrite) cmdRecoveryChar = c;
      }
      provChar ??= _firstWhereOrNull<BluetoothCharacteristic>(
        scanChars(scope),
        (c) => c.properties.write || c.properties.writeWithoutResponse,
      );
      infoChar ??= _firstWhereOrNull<BluetoothCharacteristic>(
        scanChars(scope),
        (c) => c.properties.notify,
      );
      if (provChar == null || infoChar == null) {
        debugPrint('[BLE] missing required characteristics');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Gerekli BLE özellikleri bulunamadı (WRITE/NOTIFY).',
              ),
            ),
          );
        }
        return false;
      }

      debugPrint(
        '[BLE] using provChar=${provChar.uuid.str} infoChar=${infoChar.uuid.str}',
      );

      await infoChar.setNotifyValue(true);
      final completer = Completer<String?>();
      String? capturedDeviceId;
      String? capturedMdnsHost;
      _installBleNotifyListener(
        infoChar,
        completer,
        onDeviceId: (deviceId) {
          if (deviceId != null && deviceId.isNotEmpty) {
            capturedDeviceId = deviceId;
            debugPrint('[BLE] captured deviceId from notify: $deviceId');
          }
        },
        onHost: (host) {
          if (host != null && host.isNotEmpty) {
            capturedMdnsHost = host.trim();
            debugPrint(
              '[BLE] captured mdnsHost from notify: $capturedMdnsHost',
            );
            unawaited(_updateActiveDeviceMdnsHost(capturedMdnsHost!));
          }
        },
      );

      String? deriveId6FromBleName(String? rawName) {
        final name = (rawName ?? '').trim();
        if (name.isEmpty) return null;
        final m = RegExp(r'_(\d{6})$').firstMatch(name);
        if (m == null) return null;
        return m.group(1);
      }

      Future<String?> tryRecoverPairTokenFromBle() async {
        if (cmdRecoveryChar == null) return null;
        Future<String?> awaitAuthTokenAfterWrite(
          Map<String, dynamic> cmd, {
          Duration timeout = const Duration(seconds: 4),
        }) async {
          final framer = _BleJsonFramer();
          final completer = Completer<String?>();
          StreamSubscription<List<int>>? sub;
          try {
            sub = infoChar!.lastValueStream.listen((data) {
              try {
                final chunk = utf8.decode(data, allowMalformed: true);
                for (final js in framer.feed(chunk)) {
                  final obj = jsonDecode(js);
                  if (obj is! Map<String, dynamic>) continue;
                  final auth = obj['auth'];
                  if (auth is Map) {
                    final a = auth.cast<String, dynamic>();
                    final tok = (a['pairToken'] ?? a['qrToken'] ?? '')
                        .toString()
                        .trim();
                    if (tok.isNotEmpty && !completer.isCompleted) {
                      completer.complete(tok);
                      return;
                    }
                  }
                }
              } catch (_) {}
            });
            await cmdRecoveryChar!.write(
              utf8.encode(jsonEncode(cmd)),
              withoutResponse: !(cmdRecoveryChar.properties.write),
            );
            return await completer.future.timeout(
              timeout,
              onTimeout: () => null,
            );
          } catch (_) {
            return null;
          } finally {
            await sub?.cancel();
          }
        }

        String? id6 = deriveId6FromBleName(target!.platformName);
        id6 ??= _deviceId6ForMqtt();
        id6 = (id6 ?? '').trim();
        if (id6.isEmpty) return null;

        final nonceToken = await awaitAuthTokenAfterWrite(const {
          'cmd': 'GET_NONCE',
        });
        if (nonceToken != null && nonceToken.isNotEmpty) {
          await _applyPairToken(nonceToken, deviceListId: id6);
          return nonceToken;
        }

        String user = '';
        String pass = '';
        try {
          final cached = await _loadBleSetupCredsForId6(id6);
          user = (cached?['user'] ?? '').trim();
          pass = (cached?['pass'] ?? '').trim();
        } catch (_) {}
        if (user.isEmpty || pass.isEmpty) {
          user = 'AAC';
          pass = 'aac$id6';
        }
        if (user.isEmpty || pass.isEmpty) return null;

        final authToken = await awaitAuthTokenAfterWrite(<String, dynamic>{
          'type': 'AUTH_SETUP',
          'user': user,
          'pass': pass,
        }, timeout: const Duration(seconds: 5));
        if (authToken != null && authToken.isNotEmpty) {
          await _applyPairToken(authToken, deviceListId: id6);
          return authToken;
        }
        return null;
      }

      String? pairToken;
      if (_activeDeviceId != null && _activeDeviceId!.trim().isNotEmpty) {
        final canonical = canonicalizeDeviceId(_activeDeviceId!.trim());
        if (canonical != null) pairToken = await _loadPairToken(canonical);
      }
      if (pairToken == null || pairToken.isEmpty) {
        pairToken = api.pairToken?.trim();
      }
      if (pairToken == null || pairToken.isEmpty) {
        final id6FromBle = deriveId6FromBleName(target.platformName);
        if (id6FromBle != null && id6FromBle.isNotEmpty) {
          pairToken = await _pairTokenForBleSheet(id6FromBle);
        }
      }
      if (pairToken == null || pairToken.isEmpty) {
        final id6 = _deviceId6ForMqtt();
        if (id6 != null && id6.isNotEmpty) {
          pairToken = await _pairTokenForBleSheet(id6);
        }
      }
      if (pairToken == null || pairToken.isEmpty) {
        pairToken = await tryRecoverPairTokenFromBle();
        if (pairToken != null && pairToken.isNotEmpty) {
          debugPrint(
            '[BLE] pairToken recovered from BLE auth/nonce len=${pairToken.length}',
          );
        }
      }
      debugPrint('[BLE] pairToken loaded len=${pairToken?.length ?? 0}');
      var hasPairToken = pairToken != null && pairToken.isNotEmpty;
      if (!hasPairToken) {
        final refreshed = await _resolveActivePairToken();
        if (refreshed != null && refreshed.trim().isNotEmpty) {
          pairToken = refreshed.trim();
          hasPairToken = true;
          debugPrint(
            '[BLE] pairToken recovered just-in-time len=${pairToken.length}',
          );
        }
      }
      if (!hasPairToken) {
        debugPrint(
          '[BLE] pairToken missing; abort provisioning to avoid claim_proof mismatch',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cihaz doğrulama kodu bulunamadı. BLE üzerinden yeniden eşleştirip tekrar deneyin.',
              ),
            ),
          );
        }
        return false;
      }
      api.setPairToken(pairToken!.trim());

      final payloadMap = <String, dynamic>{
        'ssid': ssid,
        'pass': pass,
        'qrToken': pairToken,
      };
      debugPrint(
        '[BLE] provisioning payload includes qrTokenLen=${pairToken.length}',
      );
      final payload = jsonEncode(payloadMap);
      debugPrint('[BLE] writing provisioning payload to ${provChar.uuid.str}');
      try {
        await provChar.write(utf8.encode(payload), withoutResponse: false);
      } catch (e) {
        debugPrint('[BLE] prov write error: $e');
      }
      _blePollCmdTimer?.cancel();
      int blePollCount = 0;
      int bleDisconnectedWriteErrors = 0;
      _blePollCmdTimer = Timer.periodic(const Duration(milliseconds: 1200), (
        _,
      ) async {
        blePollCount++;
        final body = jsonEncode({'get': 'status'});
        try {
          await provChar!.write(utf8.encode(body), withoutResponse: true);
          bleDisconnectedWriteErrors = 0;
          debugPrint('[BLE] poll status via write: $body');
        } catch (e) {
          debugPrint('[BLE] poll write error: ${e.toString()}');
          final es = e.toString().toLowerCase();
          if (es.contains('not connected') || es.contains('disconnected')) {
            bleDisconnectedWriteErrors++;
            if (bleDisconnectedWriteErrors >= 2) {
              try {
                _blePollCmdTimer?.cancel();
              } catch (_) {}
              _blePollCmdTimer = null;
            }
          }
        }
        if (blePollCount >= 4) {
          try {
            _blePollCmdTimer?.cancel();
          } catch (_) {}
          _blePollCmdTimer = null;
        }
      });

      final apFuture = _pollApForStaIp(
        apBase: 'http://192.168.4.1',
        total: const Duration(seconds: 6),
        step: const Duration(milliseconds: 500),
        onHost: (host) {
          if (host.trim().isNotEmpty) {
            capturedMdnsHost = host.trim();
            debugPrint('[AP] captured mdnsHost: $capturedMdnsHost');
            unawaited(_updateActiveDeviceMdnsHost(capturedMdnsHost!));
          }
        },
      );

      String? ip = await completer.future.timeout(
        const Duration(seconds: 18),
        onTimeout: () => null,
      );
      ip = (ip ?? '').trim();
      if (ip.isEmpty || ip == '0.0.0.0') {
        final apIp = await apFuture.timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        );
        final apTrimmed = (apIp ?? '').trim();
        if (apTrimmed.isNotEmpty && apTrimmed != '0.0.0.0') {
          ip = apTrimmed;
        } else {
          ip = null;
        }
      }

      try {
        _bleReadTimer?.cancel();
      } catch (_) {}
      _bleReadTimer = null;
      try {
        notifySub?.cancel();
      } catch (_) {}
      notifySub = null;

      if (ip == null || ip.isEmpty || ip == '0.0.0.0') {
        debugPrint('[BLE] ip from notify/AP = NULL');
        if (capturedDeviceId == null || capturedDeviceId!.isEmpty) {
          final fallbackId6 = _deviceId6ForMqtt();
          if (fallbackId6 != null && fallbackId6.isNotEmpty) {
            capturedDeviceId = fallbackId6;
          }
        }
        if ((capturedMdnsHost ?? '').trim().isEmpty) {
          debugPrint(
            '[BLE] no mdns host yet; continuing readiness wait without early disconnect',
          );
        } else {
          debugPrint(
            '[BLE] mdns host present despite null ip -> keep flow alive (${capturedMdnsHost!.trim()})',
          );
        }
      }
      if (capturedDeviceId != null && capturedDeviceId!.isNotEmpty) {
        final deviceId = capturedDeviceId!.trim();
        await _ensureActiveDeviceForId6(deviceId);
        final normalizedId6 = _normalizeDeviceId6(deviceId);
        if (normalizedId6 != null && normalizedId6.isNotEmpty) {
          await _setBleTargetId6InPrefs(normalizedId6);
        }
        debugPrint(
          '[BLE] activeDeviceId resolved from provision: $deviceId -> ${_activeDeviceId ?? '-'}',
        );
        final tokenToPersist = pairToken.trim();
        if (tokenToPersist.isNotEmpty) {
          await _applyPairToken(tokenToPersist, deviceListId: _activeDeviceId);
          debugPrint(
            '[BLE] persisted provisioning pairToken for ${_activeDeviceId ?? deviceId}',
          );
        }
      }

      if (ip != null && ip.isNotEmpty && ip != '0.0.0.0') {
        unawaited(_updateActiveDeviceLastIp(ip));
      }

      if (ip != null && ip.isNotEmpty && ip != '0.0.0.0') {
        final newBase = 'http://$ip';
        await _applyProvisionedBaseUrl(newBase, showSnack: true);
      }
      final host = capturedMdnsHost;
      if (host != null && host.isNotEmpty) {
        unawaited(_promoteProvisionedMdnsBaseInBackground(host));
      }
      final ok = await _awaitProvisionedDeviceReady(
        ip: ip,
        mdnsHost: host,
        deviceId: capturedDeviceId,
        total: const Duration(seconds: 20),
      );
      if (!ok) {
        final id6FromCaptured = _normalizeDeviceId6(capturedDeviceId ?? '');
        final id6FromActive = _normalizeDeviceId6(
          _activeDevice?.id ?? _activeDeviceId ?? '',
        );
        final id6FromBleName = _normalizeDeviceId6(
          deriveId6FromBleName(target.platformName) ?? '',
        );
        final stableId6 = id6FromCaptured ?? id6FromActive ?? id6FromBleName;
        final stableHost = (capturedMdnsHost ?? '').trim();
        final stableLocalBase = stableHost.isNotEmpty
            ? 'http://${stableHost.endsWith('.local') ? stableHost : '$stableHost.local'}'
            : (stableId6 != null && stableId6.isNotEmpty)
            ? 'http://${mdnsHostForId6(stableId6, rawIdHint: stableId6)}.local'
            : null;
        final apStillReachable = await _probeInfoReachable(
          'http://192.168.4.1',
          timeout: const Duration(milliseconds: 1200),
        );
        if (!apStillReachable && stableLocalBase != null) {
          debugPrint(
            '[BLE] provisioning accepted; local readiness deferred base=$stableLocalBase',
          );
          if (stableId6 != null && stableId6.isNotEmpty) {
            await _ensureActiveDeviceForId6(stableId6);
            await _setBleTargetId6InPrefs(stableId6);
            if (pairToken.trim().isNotEmpty) {
              await _applyPairToken(pairToken.trim(), deviceListId: stableId6);
            }
          }
          await _applyProvisionedBaseUrl(stableLocalBase, showSnack: false);
          if (mounted) {
            _showSnack(
              'Wi-Fi ayarları kaydedildi. Telefon aynı ağa geçtiğinde yerel bağlantı otomatik kurulacak.',
            );
          }
          return true;
        }
        _clearBlockingProgress();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t.t('reachable_no'))));
        }
        return false;
      }
      return true;
    } catch (e, st) {
      debugPrint('[BLE] provision error: $e');
      debugPrint(st.toString());
      _clearBlockingProgress();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.t('command_failed'))));
      }
      return false;
    } finally {
      try {
        _bleReadTimer?.cancel();
      } catch (_) {}
      _bleReadTimer = null;
      try {
        _blePollCmdTimer?.cancel();
      } catch (_) {}
      _blePollCmdTimer = null;
      try {
        await notifySub?.cancel();
      } catch (_) {}
      notifySub = null;
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      try {
        await scanSub?.cancel();
      } catch (_) {}
      scanSub = null;
      _bleBusy = false;
      _clearBlockingProgress();
    }
  }

  Future<ApProvisionResult> _apProvisionSend(String ssid, String pass) async {
    const apBase = 'http://192.168.4.1';
    try {
      final resp = await http
          .post(
            Uri.parse('$apBase/api/prov'),
            headers: api.authHeaders(json: true),
            body: jsonEncode({'ssid': ssid, 'pass': pass}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        Map<String, dynamic>? obj;
        try {
          if (resp.body.isNotEmpty) {
            final decoded = jsonDecode(resp.body);
            if (decoded is Map<String, dynamic>) obj = decoded;
          }
        } catch (_) {}

        final staOk = obj?['sta'] == true || obj?['ok'] == true;
        final ipCandidate = (obj?['ip'] ?? obj?['sta_ip'])?.toString().trim();
        final statusMsg = obj?['status']?.toString();

        if (staOk &&
            ipCandidate != null &&
            ipCandidate.isNotEmpty &&
            ipCandidate != '0.0.0.0') {
          final newBase = ipCandidate.startsWith('http')
              ? ipCandidate
              : 'http://$ipCandidate';
          await _applyProvisionedBaseUrl(newBase, showSnack: false);
          return ApProvisionResult(
            success: true,
            message: '${t.t('base_url_updated')}: $newBase',
            ip: ipCandidate,
            showReconnectHint: true,
          );
        }

        if (staOk) {
          return ApProvisionResult(
            success: true,
            message: '${t.t('reachable_yes')} (IP bekleniyor)',
            ip: ipCandidate,
          );
        }

        return ApProvisionResult(
          success: false,
          message:
              '${t.t('command_failed')}${statusMsg != null ? ' ($statusMsg)' : ''}',
        );
      }

      return ApProvisionResult(
        success: false,
        message: '${t.t('command_failed')} (HTTP ${resp.statusCode})',
      );
    } catch (e) {
      return ApProvisionResult(
        success: false,
        message: '${t.t('command_failed')}: $e',
      );
    }
  }

  Future<String?> _getBleTargetId6FromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_bleTargetId6Key);
      if (raw == null || raw.trim().isEmpty) return null;
      return _normalizeDeviceId6(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _setBleTargetId6InPrefs(String id6) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_bleTargetId6Key, id6);
    } catch (_) {}
  }

  Future<void> _clearBleTargetId6InPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bleTargetId6Key);
    } catch (_) {}
  }

  void _useFallbackIpIfAny(String hostLabel) {
    if (_apStickyActive() || api.baseUrl == 'http://192.168.4.1') {
      return;
    }
    final ip = _getActiveDeviceLastIp();
    if (ip == null) {
      debugPrint('[NET] no lastIp available for fallback ($hostLabel)');
      return;
    }
    final fallback = 'http://$ip';
    if (api.baseUrl != fallback) {
      api.baseUrl = fallback;
      debugPrint('[NET] fallback to lastIp -> $fallback (host=$hostLabel)');
    }
  }

  String? _getActiveDeviceLastIp() {
    final dev = _activeDevice;
    final stored = dev?.lastIp?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final host = Uri.tryParse(api.baseUrl)?.host ?? '';
    if (_baseHostLooksLikeIpv4(host)) return host;
    return null;
  }

  Future<void> _updateActiveDeviceLastIp(String host) async {
    if (!_baseHostLooksLikeIpv4(host)) return;
    if (_devices.isEmpty || _activeDeviceId == null) return;
    final idx = _devices.indexWhere((d) => d.id == _activeDeviceId);
    if (idx == -1) return;
    if (_devices[idx].lastIp == host) return;
    _devices[idx].lastIp = host;
    await _saveDevicesToPrefs();
  }

  Future<void> _updateActiveDeviceMdnsHost(String host) async {
    var trimmed = host.trim();
    if (trimmed.isEmpty || _devices.isEmpty || _activeDeviceId == null) return;
    if (trimmed.endsWith('.local')) {
      trimmed = trimmed.substring(0, trimmed.length - 6);
    }
    if (!RegExp(r'^[a-z0-9-]+-[0-9]{6}$').hasMatch(trimmed.toLowerCase())) {
      return;
    }
    final idx = _devices.indexWhere((d) => d.id == _activeDeviceId);
    if (idx == -1) return;
    if ((_devices[idx].mdnsHost ?? '').trim() == trimmed) return;
    _devices[idx].mdnsHost = trimmed;
    _devices[idx].baseUrl = _normalizedStoredBaseForDevice(
      _devices[idx],
      _devices[idx].baseUrl,
    );
    await _saveDevicesToPrefs();
  }

  String? _deviceId6ForMqtt() {
    final direct = normalizeDeviceId6(
      _activeDevice?.id ?? _activeDeviceId ?? '',
    );
    if (direct != null && direct.isNotEmpty) return direct;

    final baseUrl = _safeApiBaseUrl();
    if (baseUrl == null || baseUrl.isEmpty) return null;

    final host = Uri.tryParse(baseUrl)?.host ?? '';
    final fromHost = normalizeDeviceId6(host);
    if (fromHost != null && fromHost.isNotEmpty) return fromHost;

    final recent = _recentEndpointId6ForCurrentBase(
      maxAge: const Duration(minutes: 8),
    );
    if (recent != null && recent.isNotEmpty) return recent;

    final fromInventory = _inferLikelyActiveId6FromInventory();
    if (fromInventory != null && fromInventory.isNotEmpty) return fromInventory;
    return null;
  }

  String? _inferLikelyActiveId6FromInventory() {
    if (_devices.isEmpty) return null;
    if (_devices.length == 1) {
      final only = normalizeDeviceId6(_devices.first.id);
      if (only != null && only.isNotEmpty) return only;
    }

    final baseUrl = _safeApiBaseUrl() ?? '';
    final host = (Uri.tryParse(baseUrl)?.host ?? '').trim().toLowerCase();
    if (host.isNotEmpty) {
      for (final d in _devices) {
        final dHost = (d.mdnsHost ?? '').trim().toLowerCase();
        if (dHost.isNotEmpty && (host == '$dHost.local' || host == dHost)) {
          final hit = normalizeDeviceId6(d.id);
          if (hit != null && hit.isNotEmpty) return hit;
        }
        final ip = (d.lastIp ?? '').trim();
        if (ip.isNotEmpty && host == ip) {
          final hit = normalizeDeviceId6(d.id);
          if (hit != null && hit.isNotEmpty) return hit;
        }
      }
    }
    return null;
  }

  String? _safeApiBaseUrl() {
    try {
      return api.baseUrl;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveDeviceId6ForCloudAction() async {
    final direct = _deviceId6ForMqtt();
    if (direct != null && direct.isNotEmpty) return direct;

    final fromEndpoint = await _readEndpointId6(
      timeout: const Duration(milliseconds: 900),
    );
    if (fromEndpoint != null && fromEndpoint.isNotEmpty) return fromEndpoint;

    final recent = _recentEndpointId6ForCurrentBase(
      maxAge: const Duration(minutes: 10),
    );
    if (recent != null && recent.isNotEmpty) return recent;

    debugPrint('[CLOUD] resolve id6 skipped: active device id6 unavailable');
    return null;
  }

  void _installBleNotifyListener(
    BluetoothCharacteristic infoChar,
    Completer<String?> completer, {
    ValueSetter<String?>? onDeviceId,
    ValueSetter<String?>? onHost,
  }) {
    try {
      notifySub?.cancel();
    } catch (_) {}

    _bleProvJsonFramer.reset();
    notifySub = infoChar.lastValueStream.listen((data) {
      void salvageFromRaw(String raw) {
        if (raw.isEmpty) return;
        final ipv4 = RegExp(
          r'"(?:staIp|sta_ip|ip)"\s*:\s*"(\\d{1,3}(?:\\.\\d{1,3}){3})"',
          caseSensitive: false,
        ).firstMatch(raw);
        final ip = ipv4?.group(1)?.trim();
        if (ip != null && ip.isNotEmpty && ip != '0.0.0.0') {
          if (!completer.isCompleted) {
            debugPrint('[BLE] notify salvage ip=$ip');
            completer.complete(ip);
          }
        }

        final host = RegExp(
          r'"(?:mdnsHost|host)"\s*:\s*"([^"]+)"',
          caseSensitive: false,
        ).firstMatch(raw)?.group(1)?.trim();
        if (host != null && host.isNotEmpty) {
          try {
            debugPrint('[BLE] notify salvage host=$host');
            onHost?.call(host);
          } catch (_) {}
        }

        if (onDeviceId != null) {
          final id = RegExp(
            r'"(?:deviceId|id6)"\s*:\s*"([A-Za-z0-9_-]+)"',
            caseSensitive: false,
          ).firstMatch(raw)?.group(1)?.trim();
          if (id != null && id.isNotEmpty) {
            try {
              debugPrint('[BLE] notify salvage id=$id');
              onDeviceId(id);
            } catch (_) {}
          }
        }
      }

      try {
        final chunk = utf8.decode(data, allowMalformed: true);
        final completed = _bleProvJsonFramer.feed(chunk);
        for (final jsonStr in completed) {
          final last = jsonStr.trim();
          debugPrint('[BLE] notify (framed): $last');
          dynamic obj;
          try {
            obj = jsonDecode(last);
          } catch (_) {
            final markers = <String>[
              '{"fwVersion"',
              '{"auth"',
              '{"prov"',
              '{"network"',
              '{"wifi"',
            ];
            String? recovered;
            for (final m in markers) {
              final idx = last.lastIndexOf(m);
              if (idx > 0 && idx < last.length - 2) {
                recovered = last.substring(idx).trim();
                break;
              }
            }
            if (recovered == null) {
              salvageFromRaw(last);
              rethrow;
            }
            obj = jsonDecode(recovered);
            debugPrint('[BLE] notify recovered from malformed frame');
          }
          if (obj is Map) {
            if (onDeviceId != null) {
              final meta = obj['meta'];
              if (meta is Map) {
                final deviceId = (meta['deviceId'] ?? meta['id6'] ?? '')
                    .toString()
                    .trim();
                if (deviceId.isNotEmpty) {
                  onDeviceId(deviceId);
                }
              }
              final directDeviceId = (obj['deviceId'] ?? obj['id6'] ?? '')
                  .toString()
                  .trim();
              if (directDeviceId.isNotEmpty) {
                onDeviceId(directDeviceId);
              }
            }

            final flatIp = obj['ip'];
            if (flatIp is String && flatIp.isNotEmpty && flatIp != '0.0.0.0') {
              if (!completer.isCompleted) completer.complete(flatIp.trim());
              return;
            }
            final mdnsHost = (obj['mdnsHost'] ?? obj['host'])
                ?.toString()
                .trim();
            if (mdnsHost != null && mdnsHost.isNotEmpty) {
              debugPrint('[BLE] mdns host from notify = $mdnsHost');
              try {
                onHost?.call(mdnsHost);
              } catch (_) {}
            }
            final prov = obj['prov'];
            if (prov is Map) {
              final pHost = (prov['mdnsHost'] ?? prov['host'])
                  ?.toString()
                  .trim();
              if (pHost != null && pHost.isNotEmpty) {
                debugPrint('[BLE] prov host from notify = $pHost');
                try {
                  onHost?.call(pHost);
                } catch (_) {}
              }
              final pIp =
                  (prov['ip'] ?? prov['sta_ip'])?.toString().trim() ?? '';
              final pSta = prov['sta'] == true || prov['sta_ok'] == true;
              if (pSta && pIp.isNotEmpty && pIp != '0.0.0.0') {
                if (!completer.isCompleted) completer.complete(pIp);
                return;
              }
            }
            final wifi = obj['wifi'];
            if (wifi is Map) {
              final staOk = wifi['sta_ok'] == true || wifi['sta'] == 3;
              final host = (wifi['host'] is String)
                  ? (wifi['host'] as String).trim()
                  : null;
              final ip1 = (wifi['ip'] is String)
                  ? (wifi['ip'] as String).trim()
                  : '';
              final ip2 = (wifi['sta_ip'] is String)
                  ? (wifi['sta_ip'] as String).trim()
                  : '';
              if (host != null && host.isNotEmpty) {
                debugPrint('[BLE] host from notify = $host');
                try {
                  onHost?.call(host);
                } catch (_) {}
              }
              final chosen = ip1.isNotEmpty ? ip1 : ip2;
              if (staOk && chosen.isNotEmpty && chosen != '0.0.0.0') {
                if (!completer.isCompleted) completer.complete(chosen);
                return;
              }
            }
            final network = obj['network'];
            if (network is Map) {
              final nHost = (network['mdnsHost'] ?? network['host'])
                  ?.toString()
                  .trim();
              if (nHost != null && nHost.isNotEmpty) {
                debugPrint('[BLE] network host from notify = $nHost');
                try {
                  onHost?.call(nHost);
                } catch (_) {}
              }
              final nIp =
                  (network['ip'] ?? network['staIp'] ?? network['sta_ip'])
                      ?.toString()
                      .trim() ??
                  '';
              final nSta =
                  network['wifiConnected'] == true ||
                  network['sta_ok'] == true ||
                  network['sta'] == 3;
              if (nSta && nIp.isNotEmpty && nIp != '0.0.0.0') {
                if (!completer.isCompleted) completer.complete(nIp);
                return;
              }
            }
          }
        }
      } catch (e) {
        try {
          final raw = utf8.decode(data, allowMalformed: true);
          salvageFromRaw(raw);
        } catch (_) {}
        debugPrint('[BLE] notify parse error: $e');
      }
    });

    _bleReadTimer?.cancel();
    _bleReadTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        await infoChar.read();
      } catch (_) {}
    });
  }

  Future<void> _scanWifiNetworks(
    BuildContext context,
    TextEditingController ssidCtl,
  ) async {
    final u = Uri.tryParse(api.baseUrl);
    final onDeviceAp = (u != null && u.host == '192.168.4.1');
    final auth = api.authHeaders();
    final hasLocalAuth =
        auth.containsKey('Authorization') ||
        ((auth['X-Session-Token'] ?? '').isNotEmpty &&
            (auth['X-Session-Nonce'] ?? '').isNotEmpty);
    if (onDeviceAp && !hasLocalAuth) {
      _showSnack('Önce Bluetooth ile cihaza bağlanıp soft recovery açın.');
      return;
    }
    final scaffold = ScaffoldMessenger.of(context);

    Future<List<String>> fetch() async {
      String? normalizeBase(String? raw) {
        if (raw == null) return null;
        var s = raw.trim();
        if (s.isEmpty) return null;
        if (!s.startsWith('http://') && !s.startsWith('https://')) {
          s = 'http://$s';
        }
        final uri = Uri.tryParse(s);
        if (uri == null || uri.host.isEmpty) return null;
        final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
        var host = uri.host;
        if (host == '0.0.0.0') return null;
        if (host.endsWith('.')) {
          final trimmed = host.substring(0, host.length - 1);
          if (trimmed.isEmpty) return null;
          final segments = trimmed.split('.');
          final allNumeric = segments.every(
            (part) => part.isNotEmpty && int.tryParse(part) != null,
          );
          if (allNumeric && segments.length != 4) {
            return null;
          }
          host = trimmed;
        }
        if (RegExp(r'^\d+\.\d+\.\d+\.$').hasMatch(host)) return null;
        final port = (uri.hasPort && uri.port != 80 && uri.port != 443)
            ? ':${uri.port}'
            : '';
        return '$scheme://$host$port';
      }

      final baseCandidates = <String>{'http://192.168.4.1'};
      for (final raw in [api.baseUrl, baseUrl, _urlCtl.text]) {
        final normalized = normalizeBase(raw);
        if (normalized != null) {
          baseCandidates.add(normalized);
        }
      }

      final paths = [
        '/api/scan',
        '/wifi/scan',
        '/scan',
        '/api/wifi_scan',
        '/wifi_scan',
      ];
      for (final b in baseCandidates) {
        for (final p in paths) {
          final uri = Uri.parse(b + p);
          try {
            debugPrint('[AP][SCAN] GET $uri');
            final r = await http
                .get(uri, headers: api.authHeaders())
                .timeout(const Duration(seconds: 8));
            if (r.statusCode >= 200 && r.statusCode < 300) {
              final body = r.body.trim();
              if (body.isEmpty) continue;
              final obj = jsonDecode(body);

              if (obj is List) {
                final out = <String>[];
                for (final e in obj) {
                  if (e is String) {
                    if (e.trim().isNotEmpty) out.add(e.trim());
                  } else if (e is Map && e['ssid'] is String) {
                    final s = (e['ssid'] as String).trim();
                    if (s.isNotEmpty) out.add(s);
                  }
                }
                final uniq = out.toSet().toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                if (uniq.isNotEmpty) return uniq;
              } else if (obj is Map) {
                final nets = obj['networks'];
                if (nets is List) {
                  final out = <String>[];
                  for (final e in nets) {
                    if (e is Map && e['ssid'] is String) {
                      final s = (e['ssid'] as String).trim();
                      if (s.isNotEmpty) out.add(s);
                    }
                  }
                  final uniq = out.toSet().toList()
                    ..sort(
                      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                    );
                  if (uniq.isNotEmpty) return uniq;
                }
              }
            }
          } catch (e) {
            debugPrint('[AP][SCAN] error on $uri: $e');
          }
        }
      }
      return <String>[];
    }

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<String> ssids = const [];
    try {
      ssids = await fetch();
    } finally {
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
    }

    if (ssids.isEmpty) {
      scaffold.showSnackBar(
        const SnackBar(content: Text('Wi-Fi ağları bulunamadı')),
      );
      return;
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: ssids.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = ssids[i];
              return ListTile(
                leading: const Icon(Icons.wifi),
                title: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () async {
                  ssidCtl.text = s;
                  try {
                    final p = await SharedPreferences.getInstance();
                    await p.setString('last_ssid', s);
                  } catch (_) {}
                  if (sheetCtx.mounted && Navigator.of(sheetCtx).canPop()) {
                    Navigator.of(sheetCtx).pop();
                  }
                },
              );
            },
          ),
        );
      },
    );
  }

  String _pairTokenStorageKeyLegacy(String deviceId) => 'pair_token:$deviceId';

  String _pairTokenStorageKeyV2(String canonicalDeviceKey) =>
      'pair_token_v2:$canonicalDeviceKey';

  String _pairTokenStorageKeyLast() => 'pair_token_v2:last';

  List<String> _pairTokenLegacyKeyVariants(String deviceListId) {
    final trimmed = deviceListId.trim();
    if (trimmed.isEmpty) return const <String>[];
    final canonical = canonicalizeDeviceId(trimmed);
    final id6 = normalizeDeviceId6(trimmed);
    final thingName = thingNameFromAny(trimmed);

    final ids = <String>[];
    void add(String id) {
      final v = id.trim();
      if (v.isEmpty) return;
      if (ids.contains(v)) return;
      ids.add(v);
    }

    add(trimmed);
    if (canonical != null) add(canonical);
    if (id6 != null) add(id6);
    if (thingName != null) add(thingName);
    if (trimmed.startsWith('aac-')) add(trimmed.substring(4));

    return ids.map(_pairTokenStorageKeyLegacy).toList(growable: false);
  }

  Future<void> _clearPairTokenForDevice(String deviceListId) async {
    final trimmed = deviceListId.trim();
    if (trimmed.isEmpty) return;
    final canonical = canonicalizeDeviceId(trimmed);
    final id6 = normalizeDeviceId6(trimmed);
    if (canonical == null) return;
    try {
      await _secureStorage.delete(key: _pairTokenStorageKeyV2(canonical));
      if (id6 != null) {
        await _secureStorage.delete(key: _pairTokenStorageKeyV2(id6));
      }
      for (final key in _pairTokenLegacyKeyVariants(trimmed)) {
        await _secureStorage.delete(key: key);
      }
    } catch (_) {}
    final idx = _devices.indexWhere(
      (d) =>
          canonicalizeDeviceId(d.id) == canonical &&
          canonicalizeDeviceId(d.id) != null,
    );
    if (idx != -1) {
      _devices[idx].pairToken = null;
      await _saveDevicesToPrefs();
    }
  }

  Future<void> _persistPairToken(
    String? token, {
    required String deviceListId,
  }) async {
    final trimmedId = deviceListId.trim();
    if (trimmedId.isEmpty) return;
    final canonical = canonicalizeDeviceId(trimmedId);
    final id6 = normalizeDeviceId6(trimmedId);
    if (canonical == null) return;
    final v2Key = _pairTokenStorageKeyV2(canonical);
    final legacyThingName = thingNameFromAny(trimmedId);
    final legacyV2Key =
        (legacyThingName != null && legacyThingName != canonical)
        ? _pairTokenStorageKeyV2(legacyThingName)
        : null;
    final legacyV2Id6Key = (id6 != null && id6 != canonical)
        ? _pairTokenStorageKeyV2(id6)
        : null;
    final v = token?.trim();
    try {
      if (v != null && v.isNotEmpty) {
        await _secureStorage.write(key: v2Key, value: v);
        await _secureStorage.write(key: _pairTokenStorageKeyLast(), value: v);
        if (legacyV2Key != null) {
          await _secureStorage.delete(key: legacyV2Key);
        }
        if (legacyV2Id6Key != null) {
          await _secureStorage.delete(key: legacyV2Id6Key);
        }
        for (final legacyKey in _pairTokenLegacyKeyVariants(trimmedId)) {
          await _secureStorage.delete(key: legacyKey);
        }
      } else {
        await _secureStorage.delete(key: v2Key);
        if (legacyV2Key != null) {
          await _secureStorage.delete(key: legacyV2Key);
        }
        if (legacyV2Id6Key != null) {
          await _secureStorage.delete(key: legacyV2Id6Key);
        }
        for (final legacyKey in _pairTokenLegacyKeyVariants(trimmedId)) {
          await _secureStorage.delete(key: legacyKey);
        }
      }
    } catch (_) {}
  }

  Future<void> _persistLastPairToken(String? token) async {
    final v = token?.trim();
    try {
      if (v != null && v.isNotEmpty) {
        await _secureStorage.write(key: _pairTokenStorageKeyLast(), value: v);
      }
    } catch (_) {}
  }

  Future<String?> _loadLastPairToken() async {
    try {
      final v = await _secureStorage.read(key: _pairTokenStorageKeyLast());
      final t = v?.trim() ?? '';
      if (t.isEmpty) return null;
      return t;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _loadPairToken(String deviceListId) async {
    final trimmedId = deviceListId.trim();
    if (trimmedId.isEmpty) return null;
    final canonical = canonicalizeDeviceId(trimmedId);
    final id6 = normalizeDeviceId6(trimmedId);
    if (canonical == null) return null;
    try {
      final v2 = await _secureStorage.read(
        key: _pairTokenStorageKeyV2(canonical),
      );
      if (v2 != null && v2.trim().isNotEmpty) return v2.trim();

      if (id6 != null) {
        final legacyV2 = await _secureStorage.read(
          key: _pairTokenStorageKeyV2(id6),
        );
        if (legacyV2 != null && legacyV2.trim().isNotEmpty) {
          await _secureStorage.write(
            key: _pairTokenStorageKeyV2(canonical),
            value: legacyV2.trim(),
          );
          await _secureStorage.delete(key: _pairTokenStorageKeyV2(id6));
          return legacyV2.trim();
        }
      }
      final legacyThingName = thingNameFromAny(trimmedId);
      if (legacyThingName != null && legacyThingName != canonical) {
        final legacyV2 = await _secureStorage.read(
          key: _pairTokenStorageKeyV2(legacyThingName),
        );
        if (legacyV2 != null && legacyV2.trim().isNotEmpty) {
          await _secureStorage.write(
            key: _pairTokenStorageKeyV2(canonical),
            value: legacyV2.trim(),
          );
          await _secureStorage.delete(
            key: _pairTokenStorageKeyV2(legacyThingName),
          );
          return legacyV2.trim();
        }
      }

      for (final legacyKey in _pairTokenLegacyKeyVariants(trimmedId)) {
        final legacy = await _secureStorage.read(key: legacyKey);
        final lv = legacy?.trim() ?? '';
        if (lv.isEmpty) continue;
        await _secureStorage.write(
          key: _pairTokenStorageKeyV2(canonical),
          value: lv,
        );
        for (final k in _pairTokenLegacyKeyVariants(trimmedId)) {
          await _secureStorage.delete(key: k);
        }
        return lv;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _applyPairToken(String? token, {String? deviceListId}) async {
    final trimmed = token?.trim();
    final resolved = (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
    if (resolved != null) {
      _cloudClaimNeedsQrRefresh = false;
      if ((_cloudSetupTerminalError ?? '').trim() == 'claim_proof_mismatch') {
        _cloudSetupTerminalError = null;
      }
      final st = (_cloudSetupStatus ?? '').trim().toLowerCase();
      if (st.contains('claim') && st.contains('qr')) {
        _cloudSetupStatus = null;
      }
    }
    debugPrint(
      '[QR][PAIR] apply tokenLen=${resolved?.length ?? 0} target=${deviceListId ?? _activeDeviceId ?? _activeCanonicalDeviceId}',
    );
    api.setPairToken(resolved);
    await _persistLastPairToken(resolved);
    final targetId =
        deviceListId ?? _activeDeviceId ?? _activeCanonicalDeviceId;
    if (targetId != null && targetId.trim().isNotEmpty) {
      await _persistPairToken(resolved, deviceListId: targetId);
    }
    if (targetId != null && targetId.trim().isNotEmpty) {
      final canonical = canonicalizeDeviceId(targetId);
      if (canonical == null || canonical.isEmpty) return;
      final idx = _devices.indexWhere(
        (d) => canonicalizeDeviceId(d.id) == canonical,
      );
      if (idx != -1) {
        _devices[idx].pairToken = resolved;
        await _saveDevicesToPrefs();
      }
    }
  }

  Future<String?> _resolveActivePairToken() async {
    final dev = _activeDevice;
    final direct = dev?.pairToken?.trim() ?? '';
    if (direct.isNotEmpty) {
      api.setPairToken(direct);
      return direct;
    }

    final ids = <String>[];
    void add(String? s) {
      final v = s?.trim() ?? '';
      if (v.isEmpty) return;
      if (ids.contains(v)) return;
      ids.add(v);
    }

    add(dev?.id);
    add(_activeDeviceId);
    add(_activeCanonicalDeviceId);
    add(_deviceId6ForMqtt());
    add(_recentEndpointId6ForCurrentBase(maxAge: const Duration(minutes: 15)));
    final inferredId6 = _inferLikelyActiveId6FromInventory();
    add(inferredId6);
    add(thingNameFromAny(inferredId6 ?? ''));

    for (final id in ids) {
      final stored = await _loadPairToken(id);
      final v = stored?.trim() ?? '';
      if (v.isEmpty) continue;
      debugPrint(
        '[QR][RESOLVE] using stored pairToken for id=$id len=${v.length}',
      );
      api.setPairToken(v);

      bool devicesDirty = false;
      if (dev != null) {
        dev.pairToken = v;
        devicesDirty = true;
        unawaited(_persistPairToken(v, deviceListId: dev.id));
      }
      final canonicalId = canonicalizeDeviceId(id);
      if (canonicalId != null && canonicalId.isNotEmpty) {
        final idx = _devices.indexWhere(
          (d) => canonicalizeDeviceId(d.id) == canonicalId,
        );
        if (idx != -1) {
          _devices[idx].pairToken = v;
          devicesDirty = true;
        }
      }
      if (devicesDirty) {
        unawaited(_saveDevicesToPrefs());
      }
      return v;
    }

    // AP fallback: if we're on device SoftAP, ask /info for id6 and try storage again.
    final host = Uri.tryParse(api.baseUrl)?.host.trim() ?? '';
    if (host == '192.168.4.1') {
      try {
        final r = await http
            .get(Uri.parse('http://192.168.4.1/info'))
            .timeout(const Duration(seconds: 2));
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final obj = jsonDecode(r.body);
          if (obj is Map) {
            final id6 = _normalizeDeviceId6((obj['id6'] ?? '').toString());
            if (id6 != null && id6.isNotEmpty) {
              final apIds = <String>[
                id6,
                canonicalizeDeviceId(id6) ?? id6,
                thingNameFromAny(id6) ?? '',
              ];
              for (final id in apIds) {
                final stored = await _loadPairToken(id);
                final v = stored?.trim() ?? '';
                if (v.isEmpty) continue;
                debugPrint(
                  '[QR][RESOLVE] AP /info fallback recovered pairToken id=$id len=${v.length}',
                );
                api.setPairToken(v);
                if (dev != null) {
                  dev.pairToken = v;
                  unawaited(_persistPairToken(v, deviceListId: dev.id));
                  unawaited(_saveDevicesToPrefs());
                }
                return v;
              }
            }
          }
        }
      } catch (_) {}
    }

    final last = await _loadLastPairToken();
    if (last != null && last.isNotEmpty) {
      debugPrint(
        '[QR][RESOLVE] using last pairToken fallback len=${last.length}',
      );
      api.setPairToken(last);
      if (dev != null) {
        dev.pairToken = last;
        unawaited(_persistPairToken(last, deviceListId: dev.id));
        unawaited(_saveDevicesToPrefs());
      }
      return last;
    }

    debugPrint(
      '[QR][RESOLVE] pairToken not found ids=${ids.join(",")} '
      'active=${_activeDeviceId ?? "-"} id6=${_deviceId6ForMqtt() ?? "-"}',
    );
    return null;
  }

  Future<void> _handleInvalidQrToken({String source = 'BLE'}) async {
    final now = DateTime.now();
    final last = _lastInvalidQrTokenAt;
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _lastInvalidQrTokenAt = now;

    debugPrint('[AUTH] invalid_qr_token ($source)');
    _showSnack(
      'Cihaz doğrulama kodu geçersiz veya eski. Soft recovery açıp tekrar deneyin.',
    );
  }

  Future<void> _persistDoaWatering() async {
    if (_activeDeviceId == null) return;
    final idx = _devices.indexWhere((d) => d.id == _activeDeviceId);
    if (idx == -1) return;
    _devices[idx].doaWaterDurationMin = _doaWaterDurationMin;
    _devices[idx].doaWaterIntervalHr = _doaWaterIntervalHr;
    _devices[idx].doaWaterAutoEnabled = _doaWaterAutoEnabled;
    await _saveDevicesToPrefs();
  }

  Future<bool> _sendDoaWateringConfig({bool? enabled}) async {
    if (!_isDoaDevice) return false;
    if (!_canControlDevice) return false;
    final useEnabled = enabled ?? _doaWaterAutoEnabled;
    final duration = useEnabled ? _doaWaterDurationMin.round() : 0;
    final payload = {
      'waterAutoEnabled': useEnabled ? 1 : 0,
      'waterDurationMin': duration,
      'waterIntervalMin': (_doaWaterIntervalHr * 60).round(),
      'autoHumEnabled': 0,
    };
    return _send(payload);
  }

  Future<void> _sendDoaManualWater(bool on) async {
    if (!_isDoaDevice) return;
    if (!_canControlDevice) return;
    await _send({'waterManual': on ? 1 : 0, 'autoHumEnabled': 0});
  }

  Future<void> _sendDoaHumAutoConfig(bool on) async {
    if (!_isDoaDevice) return;
    if (!_canControlDevice) return;
    await _send({'waterHumAutoEnabled': on ? 1 : 0, 'autoHumEnabled': 0});
  }

  Future<bool> _sendArtAutoHumidityConfig({bool? enabled}) async {
    if (_isDoaDevice) return false;
    if (!_canControlDevice) return false;
    final useEnabled = enabled ?? _autoHumEnabled;
    return _send({
      'autoHumEnabled': useEnabled ? 1 : 0,
      'autoHumTarget': _autoHumTarget.round(),
    });
  }

  Future<String?> _pollApForStaIp({
    String apBase = 'http://192.168.4.1',
    Duration total = const Duration(seconds: 40),
    Duration step = const Duration(seconds: 2),
    ValueSetter<String>? onHost,
  }) async {
    final endpoints = <String>['/info', '/api/status', '/status', '/state'];
    final deadline = DateTime.now().add(total);
    var attempt = 0;
    var consecutiveAll404 = 0;

    String? extractIpFromObj(Map obj) {
      final net = obj['network'];
      if (net is Map) {
        final mdnsHost = (net['mdnsHost'] ?? net['host'])?.toString().trim();
        if (mdnsHost != null && mdnsHost.isNotEmpty) {
          debugPrint('[AP] network.mdnsHost=$mdnsHost');
          try {
            onHost?.call(mdnsHost);
          } catch (_) {}
        }
        final staIpRaw = net['staIp'];
        if (staIpRaw is String &&
            staIpRaw.isNotEmpty &&
            staIpRaw != '0.0.0.0') {
          return staIpRaw.trim();
        }
      }
      final directIp = obj['ip'];
      if (directIp is String && directIp.isNotEmpty && directIp != '0.0.0.0') {
        return directIp.trim();
      }
      final wifi = obj['wifi'];
      if (wifi is Map) {
        final host = (wifi['host'] is String)
            ? (wifi['host'] as String).trim()
            : '';
        if (host.isNotEmpty) {
          debugPrint('[AP] wifi.host=$host');
          try {
            onHost?.call(host);
          } catch (_) {}
        }
        final staOk = wifi['sta_ok'] == true || wifi['sta'] == 3;
        final ip1 = (wifi['ip'] is String) ? (wifi['ip'] as String).trim() : '';
        final ip2 = (wifi['sta_ip'] is String)
            ? (wifi['sta_ip'] as String).trim()
            : '';
        final chosen = ip1.isNotEmpty ? ip1 : ip2;
        debugPrint(
          '[AP] parsed sta_ok=$staOk ip=$chosen ap_ip=${wifi['ap_ip']}',
        );
        if (staOk && chosen.isNotEmpty && chosen != '0.0.0.0') {
          return chosen;
        }
      }
      final state = obj['state'];
      if (state is Map) {
        final ipS = state['ip'];
        if (ipS is String && ipS.isNotEmpty && ipS != '0.0.0.0') {
          return ipS.trim();
        }
        final wifi2 = state['wifi'];
        if (wifi2 is Map) {
          final staOk2 = wifi2['sta_ok'] == true || wifi2['sta'] == 3;
          final ipS1 = (wifi2['ip'] is String)
              ? (wifi2['ip'] as String).trim()
              : '';
          final ipS2 = (wifi2['sta_ip'] is String)
              ? (wifi2['sta_ip'] as String).trim()
              : '';
          final chosen2 = ipS1.isNotEmpty ? ipS1 : ipS2;
          if (staOk2 && chosen2.isNotEmpty && chosen2 != '0.0.0.0') {
            return chosen2;
          }
        }
      }
      return null;
    }

    while (DateTime.now().isBefore(deadline)) {
      attempt++;
      var all404ThisRound = true;
      for (final ep in endpoints) {
        final uri = Uri.parse('$apBase$ep');
        try {
          final r = await http
              .get(uri, headers: api.authHeaders())
              .timeout(kLocalHttpRequestTimeout);
          if (r.statusCode >= 200 && r.statusCode < 300 && r.body.isNotEmpty) {
            all404ThisRound = false;
            debugPrint('[AP] GET ${uri.toString()} -> ${r.body}');
            final obj = jsonDecode(r.body);
            if (obj is Map) {
              final ip = extractIpFromObj(obj);
              if (ip != null) return ip;
            }
          } else {
            if (r.statusCode != 404) {
              all404ThisRound = false;
            }
            debugPrint('[AP] GET ${uri.toString()} status=${r.statusCode}');
          }
        } catch (e) {
          all404ThisRound = false;
          debugPrint('[AP] poll error @${uri.toString()}: ${e.toString()}');
        }
      }
      if (all404ThisRound) {
        consecutiveAll404++;
        if (consecutiveAll404 >= 2) {
          debugPrint('[AP] all endpoints 404 repeatedly; early stop');
          return null;
        }
      } else {
        consecutiveAll404 = 0;
      }
      debugPrint('[AP] wait ${step.inSeconds}s (attempt $attempt)');
      await Future.delayed(step);
    }
    return null;
  }

  Future<bool> _probeApReachable() async {
    const apBase = 'http://192.168.4.1';
    try {
      final r = await http
          .get(Uri.parse('$apBase/info'), headers: api.authHeaders())
          .timeout(kLocalHttpProbeTimeout);
      final ok =
          (r.statusCode >= 200 && r.statusCode < 300) ||
          r.statusCode == 401 ||
          r.statusCode == 403 ||
          r.statusCode == 429;
      if (ok) {
        _markApSticky();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _probeApEndpointId6({
    Duration timeout = kLocalHttpProbeTimeout,
  }) async {
    const apBase = 'http://192.168.4.1';
    try {
      final r = await http
          .get(Uri.parse('$apBase/info'), headers: api.authHeaders())
          .timeout(timeout);
      if (r.statusCode < 200 || r.statusCode >= 300) return null;
      final obj = jsonDecode(r.body);
      if (obj is! Map<String, dynamic>) return null;
      final id6 = _extractEndpointId6FromInfoJson(obj);
      if (id6 != null && id6.isNotEmpty) {
        _rememberEndpointId6ForCurrentBase(id6);
      }
      return id6;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _probeInfoReachable(
    String base, {
    Duration timeout = kLocalHttpProbeTimeout,
  }) async {
    try {
      final isAp = base == 'http://192.168.4.1';
      final path = isAp ? '/info' : '/api/status';
      final r = await http
          .get(Uri.parse('$base$path'), headers: api.authHeaders())
          .timeout(timeout);
      final ok =
          (r.statusCode >= 200 && r.statusCode < 300) ||
          r.statusCode == 401 ||
          r.statusCode == 403 ||
          r.statusCode == 429;
      if (ok && !isAp) {
        _captureLastIpForBaseInBackground(base);
        final host = Uri.tryParse(base)?.host ?? '';
        if (_baseHostLooksLikeIpv4(host)) {
          unawaited(_updateActiveDeviceLastIp(host));
        }
        _localDnsFailUntil = null;
        _localUnreachableUntil = null;
        _lastLocalOkAt = DateTime.now();
      }
      return ok;
    } catch (e) {
      if (_looksLikeDnsLookupFailure(e) && !_baseHostLooksLikeIpv4(base)) {
        _markLocalDnsFailure();
      } else if (_looksLikeLocalUnreachable(e)) {
        _markLocalUnreachable();
      }
      return false;
    }
  }

  Future<bool> _probeLocalHealthWithRetry(String base) async {
    final ok1 = await _probeInfoReachable(
      base,
      timeout: const Duration(milliseconds: 1500),
    );
    if (ok1) return true;
    await Future.delayed(const Duration(milliseconds: 500));
    return _probeInfoReachable(
      base,
      timeout: const Duration(milliseconds: 2000),
    );
  }

  Future<void> _maybeFixLocalBaseViaMdns() async {
    if (_transportRecoveryBlocked(reason: 'mdns_fix')) return;
    if (_apStickyActive()) return;
    final now = DateTime.now();
    final last = _lastMdnsFixAt;
    if (last != null && now.difference(last) < const Duration(seconds: 60)) {
      return;
    }
    _lastMdnsFixAt = now;

    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return;

    final host = '${mdnsHostForId6(id6, rawIdHint: id6)}.local';
    final hostBase = 'http://$host';
    if (await _probeInfoReachable(hostBase)) {
      if (api.baseUrl != hostBase) {
        debugPrint('[NET] mDNS host reachable -> baseUrl=$hostBase');
        await _applyProvisionedBaseUrl(hostBase, showSnack: false);
      }
      _localDnsFailUntil = null;
      _localUnreachableUntil = null;
      _lastLocalOkAt = DateTime.now();
      return;
    }

    try {
      final ip = await _mdnsResolveHost(host);
      if (ip == null || ip.isEmpty) return;
      final ipBase = 'http://$ip';
      if (await _probeInfoReachable(ipBase)) {
        if (api.baseUrl != ipBase) {
          debugPrint('[NET] mDNS resolved $host -> $ipBase');
          await _applyProvisionedBaseUrl(ipBase, showSnack: false);
        }
        _localDnsFailUntil = null;
        _localUnreachableUntil = null;
        _lastLocalOkAt = DateTime.now();
      }
    } catch (_) {}
  }

  Future<void> _maybeSwitchToApBaseUrlIfReachable() async {
    if (_transportRecoveryBlocked(reason: 'ap_switch')) return;
    const apBase = 'http://192.168.4.1';
    final now = DateTime.now();
    final baseHost = Uri.tryParse(api.baseUrl)?.host ?? '';
    final onSoftAp = baseHost == '192.168.4.1';
    if (!onSoftAp &&
        _lastLocalOkAt != null &&
        now.difference(_lastLocalOkAt!) < const Duration(seconds: 60)) {
      return;
    }
    final selectedId6 = _selectedId6ForGuard();
    final apEndpointId6 = await _probeApEndpointId6();
    final ok = apEndpointId6 != null || await _probeApReachable();
    if (!ok) return;
    if (selectedId6 != null &&
        selectedId6.isNotEmpty &&
        apEndpointId6 != null &&
        apEndpointId6.isNotEmpty &&
        apEndpointId6 != selectedId6) {
      debugPrint(
        '[NET] AP reachable but mismatched endpoint=$apEndpointId6 selected=$selectedId6; skipping AP switch',
      );
      _preferApUntil = null;
      if (onSoftAp) {
        final preferred = _normalizeBaseUrl(_activeDevice?.baseUrl ?? '');
        if (preferred != null &&
            preferred.isNotEmpty &&
            preferred != apBase &&
            api.baseUrl != preferred) {
          await _applyProvisionedBaseUrl(preferred, showSnack: false);
        }
      }
      return;
    }
    if (selectedId6 != null &&
        selectedId6.isNotEmpty &&
        (apEndpointId6 == null || apEndpointId6.isEmpty)) {
      final cachedApId6 = _recentEndpointId6ForBase(apBase);
      if (cachedApId6 != null && cachedApId6 == selectedId6) {
        _lastLocalOkAt = DateTime.now();
        _markApSticky();
        if (api.baseUrl != apBase || baseUrl != apBase) {
          debugPrint(
            '[NET] AP endpoint id unavailable, using cached match=$cachedApId6',
          );
          await _applyProvisionedBaseUrl(apBase, showSnack: false);
        }
        return;
      }
      if (onSoftAp) {
        _lastLocalOkAt = DateTime.now();
        _markApSticky(const Duration(seconds: 20));
        return;
      }
      debugPrint(
        '[NET] AP reachable but endpoint id unknown for selected=$selectedId6; skipping AP switch',
      );
      _preferApUntil = null;
      return;
    }
    _lastLocalOkAt = DateTime.now();
    _markApSticky();
    if (api.baseUrl == apBase && baseUrl == apBase) return;
    debugPrint('[NET] AP portal reachable -> switching baseUrl to $apBase');
    await _applyProvisionedBaseUrl(apBase, showSnack: false);
    try {
      await _ensurePairTokenForAp(prompt: false);
    } catch (_) {}
  }

  Future<void> _ensureLocalBaseFromApPortal({
    Duration total = const Duration(seconds: 8),
    Duration step = const Duration(seconds: 1),
  }) async {
    if (_apDiscoveryRunning) return;
    _apDiscoveryRunning = true;
    try {
      final host0 = Uri.tryParse(api.baseUrl)?.host ?? '';
      if (host0.endsWith('.local')) {
        _useFallbackIpIfAny('local-probe');
      }
      final ok0 = await api.testConnection();
      if (!ok0) {
        debugPrint(
          '[INIT] baseUrl not reachable, trying AP portal for STA IP...',
        );
        const apBase = 'http://192.168.4.1';

        var apReachable = false;
        try {
          final r = await http
              .get(Uri.parse('$apBase/info'))
              .timeout(kLocalHttpProbeTimeout);
          apReachable = r.statusCode >= 200 && r.statusCode < 300;
        } catch (_) {
          apReachable = false;
        }
        if (apReachable && baseUrl != apBase) {
          baseUrl = apBase;
          api.baseUrl = apBase;
          _urlCtl.text = apBase;
          try {
            final p2 = await SharedPreferences.getInstance();
            await p2.setString('baseUrl', apBase);
          } catch (_) {}
          await _updateActiveDeviceBaseUrl(apBase);
          debugPrint('[INIT] baseUrl switched to AP -> $apBase');
        }
        if (apReachable) {
          final ip = await _pollApForStaIp(
            apBase: apBase,
            total: total,
            step: step,
            onHost: (_) {},
          );
          if (ip != null && ip.isNotEmpty) {
            final newBase = 'http://$ip';
            baseUrl = newBase;
            api.baseUrl = newBase;
            _urlCtl.text = newBase;
            try {
              final p2 = await SharedPreferences.getInstance();
              await p2.setString('baseUrl', newBase);
            } catch (_) {}
            debugPrint('[INIT] baseUrl updated from AP -> $newBase');
            await _updateActiveDeviceBaseUrl(newBase);
          } else {
            debugPrint('[INIT] AP portal did not return STA IP.');
          }
        } else {
          debugPrint(
            '[INIT] AP not reachable at /info; skipping AP STA-IP discovery.',
          );
        }
      }
    } catch (e) {
      debugPrint('[INIT] autodiscover error: ${e.toString()}');
    } finally {
      _apDiscoveryRunning = false;
    }
  }
}
