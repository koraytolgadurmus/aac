part of 'main.dart';

extension _HomeScreenBleControlPart on _HomeScreenState {
  // BLE yönetim oturumunu aç/kapat; mevcut davranışı koruyan taşınmış implementasyon.
  Future<void> _toggleBleControlImpl({
    bool interactive = true,
    bool preserveActiveDevice = false,
    bool allowUnownedWithoutSetupCreds = false,
  }) async {
    if (_bleBusy) {
      if (interactive) {
        _showSnack('BLE provisioning çalışırken yönetim açılamaz.');
      }
      return;
    }
    if (_bleCtrlConnecting) {
      if (interactive) _showSnack('BLE yönetim bağlantısı kuruluyor...');
      return;
    }
    Future<void> openBleSetupFallback() async {
      if (!interactive || !mounted) return;
      try {
        await _openBleManageAndProvision();
      } catch (e) {
        debugPrint('[BLE][CTRL] open setup fallback error: $e');
      }
    }

    if (_bleControlMode) {
      try {
        await _bleCtrlNotifySub?.cancel();
      } catch (_) {}
      _bleCtrlNotifySub = null;
      try {
        await _bleCtrlConnSub?.cancel();
      } catch (_) {}
      _bleCtrlConnSub = null;
      try {
        _bleCtrlStatusTimer?.cancel();
      } catch (_) {}
      _bleCtrlStatusTimer = null;
      try {
        await safeBleDisconnect(
          _bleCtrlDevice,
          reason: 'ble_control_toggle_off',
        );
      } catch (_) {}
      _bleCtrlDevice = null;
      _bleCtrlInfoChar = null;
      _bleCtrlCmdChar = null;
      _bleControlPairToken = null;
      _bleControlMode = false;
      if (interactive) _showSnack('BLE yönetim bağlantısı kapatıldı.');
      return;
    }

    String? targetId6;
    String? setupUser;
    String? setupPass;
    bool usedCachedCreds = false;
    if (interactive) {
      _dismissBlockingPopupsIfAny();

      final lastId6 = await _getBleTargetId6FromPrefs();
      if (lastId6 != null) {
        final cached = await _loadBleSetupCredsForId6(lastId6);
        if (cached != null) {
          targetId6 = lastId6;
          setupUser = cached['user'];
          setupPass = cached['pass'];
          usedCachedCreds = true;
        }
      }

      if (targetId6 == null || setupUser == null || setupPass == null) {
        targetId6 = targetId6 ?? _deviceId6ForMqtt();
      }
      if (targetId6 == null || targetId6.trim().isEmpty) {
        if (interactive) {
          _showSnack(
            'Önce kurulum sihirbazı ile Bluetooth eşleşmesini tamamlayın.',
          );
        }
        await openBleSetupFallback();
        return;
      }
    } else {
      targetId6 = await _getBleTargetId6FromPrefs();
      targetId6 = targetId6 ?? _deviceId6ForMqtt();
      if (targetId6 == null) return;
      if (preserveActiveDevice) {
        final activeId6 = _deviceId6ForMqtt();
        if (activeId6 == null || activeId6.isEmpty || activeId6 != targetId6) {
          debugPrint(
            '[BLE][AUTO] abort toggle: target id6=$targetId6 active id6=${activeId6 ?? "-"}',
          );
          return;
        }
      }
      final cached = await _loadBleSetupCredsForId6(targetId6);
      if (cached != null) {
        setupUser = cached['user'];
        setupPass = cached['pass'];
        usedCachedCreds = true;
      }
    }

    if (!preserveActiveDevice) {
      await _ensureActiveDeviceForId6(targetId6);
    }
    _bleCtrlConnecting = true;
    final bleReady = await _ensureBluetoothOnWithUi();
    if (!bleReady) {
      _bleCtrlConnecting = false;
      return;
    }

    if (interactive) _showSnack('BLE cihaz aranıyor...');
    BluetoothDevice? target;
    final targetId6Lc = targetId6.toLowerCase();
    final expectedSuffix = '_$targetId6Lc';

    try {
      final connected = FlutterBluePlus.connectedDevices;
      for (final d in connected) {
        final name = d.platformName;
        final lower = name.toLowerCase();
        if ((isKnownBleName(lower) && lower.endsWith(expectedSuffix)) ||
            lower.contains(targetId6Lc)) {
          target = d;
          break;
        }
      }
    } catch (_) {
      target = null;
    }

    StreamSubscription<List<ScanResult>>? sub;
    if (target == null) {
      final collected = <ScanResult>[];
      sub = FlutterBluePlus.onScanResults.listen((batch) {
        for (final r in batch) {
          if (collected.any(
            (e) => e.device.remoteId.str == r.device.remoteId.str,
          )) {
            continue;
          }
          final name = r.device.platformName;
          final adv = r.advertisementData.advName;
          final lowerName = name.toLowerCase();
          final lowerAdv = adv.toLowerCase();
          final matchName =
              (isKnownBleName(lowerName) && lowerName.endsWith(expectedSuffix)) ||
              lowerName.contains(targetId6Lc);
          final matchAdv =
              (isKnownBleName(lowerAdv) && lowerAdv.endsWith(expectedSuffix)) ||
              lowerAdv.contains(targetId6Lc);
          if (matchName || matchAdv) {
            collected.add(r);
          }
        }
      });
      try {
        final scanDuration = interactive
            ? const Duration(seconds: 5)
            : const Duration(seconds: 3);
        await FlutterBluePlus.startScan(timeout: scanDuration);
        await Future.delayed(scanDuration);
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      try {
        await sub.cancel();
      } catch (_) {}
      sub = null;
      if (collected.isEmpty) {
        _showSnack('Yakında bu cihaza ait BLE bulunamadı: *$targetId6');
        if (interactive && usedCachedCreds) {
          await _clearBleTargetId6InPrefs();
          await _clearBleSetupCredsForId6(targetId6);
        }
        _bleCtrlConnecting = false;
        await openBleSetupFallback();
        return;
      }
      target = collected.first.device;
    }

    final targetDevice = target;

    Future<bool> ensureConnected() async {
      try {
        final cur = await targetDevice.connectionState.first.timeout(
          const Duration(milliseconds: 800),
        );
        if (cur == BluetoothConnectionState.connected) return true;
      } catch (_) {}
      try {
        await targetDevice.connect(timeout: const Duration(seconds: 10));
      } catch (e) {
        debugPrint('[BLE][CTRL] connect error: $e');
        final es = e.toString().toLowerCase();
        if (es.contains('apple-code: 14') ||
            es.contains('peer removed pairing information')) {
          _showSnack(
            'iOS eşleşme kaydı uyuşmuyor. Ayarlar > Bluetooth > cihazı "Bu Aygıtı Unut" yapıp tekrar deneyin.',
          );
        }
        return false;
      }
      final deadline = DateTime.now().add(const Duration(seconds: 6));
      while (DateTime.now().isBefore(deadline)) {
        try {
          final st = await targetDevice.connectionState.first.timeout(
            const Duration(milliseconds: 400),
            onTimeout: () => BluetoothConnectionState.disconnected,
          );
          if (st == BluetoothConnectionState.connected) {
            await Future.delayed(const Duration(milliseconds: 300));
            return true;
          }
        } catch (e) {
          debugPrint('[BLE][CTRL] connect state poll error: $e');
        }
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
      debugPrint('[BLE][CTRL] connect state wait timed out');
      return false;
    }

    bool connectedOk = await ensureConnected();
    if (!connectedOk) {
      _showSnack('BLE bağlantısı kurulamadı.');
      _bleCtrlConnecting = false;
      await openBleSetupFallback();
      return;
    }

    List<BluetoothService> services;
    try {
      services = await targetDevice.discoverServices();
    } catch (e) {
      debugPrint('[BLE][CTRL] discoverServices error (will retry): $e');
      try {
        connectedOk = await ensureConnected();
      } catch (_) {
        connectedOk = false;
      }
      if (connectedOk) {
        try {
          services = await targetDevice.discoverServices();
        } catch (e2) {
          _showSnack('BLE servis keşfi hatası: $e2');
          try {
            await safeBleDisconnect(
              targetDevice,
              reason: 'ble_ctrl_discover_retry_fail',
            );
          } catch (_) {}
          _bleCtrlConnecting = false;
          await openBleSetupFallback();
          return;
        }
      } else {
        _showSnack('BLE servis keşfi hatası: $e');
        try {
          await safeBleDisconnect(
            target,
            reason: 'ble_ctrl_discover_connect_fail',
          );
        } catch (_) {}
        _bleCtrlConnecting = false;
        await openBleSetupFallback();
        return;
      }
    }
    if (services.isEmpty) {
      _showSnack('BLE servis keşfi boş döndü.');
      try {
        await safeBleDisconnect(
          targetDevice,
          reason: 'ble_ctrl_services_empty',
        );
      } catch (_) {}
      _bleCtrlConnecting = false;
      await openBleSetupFallback();
      return;
    }

    BluetoothService? prefSvc;
    try {
      prefSvc = services.firstWhere((s) => _guidEq(s.uuid, kSvcUuidHint));
    } catch (_) {
      prefSvc = null;
    }
    if (prefSvc == null && services.isEmpty) {
      _showSnack('BLE servisi bulunamadı.');
      try {
        await safeBleDisconnect(
          targetDevice,
          reason: 'ble_ctrl_service_missing',
        );
      } catch (_) {}
      _bleCtrlConnecting = false;
      return;
    }

    BluetoothCharacteristic? provChar;
    BluetoothCharacteristic? infoChar;
    BluetoothCharacteristic? cmdChar;

    Iterable<BluetoothCharacteristic> scanChars(
      Iterable<BluetoothService> ss,
    ) sync* {
      for (final s in ss) {
        debugPrint('[BLE][CTRL] service: ${s.uuid.str}');
        for (final c in s.characteristics) {
          final canWrite =
              c.properties.write || c.properties.writeWithoutResponse;
          final canNotify = c.properties.notify;
          debugPrint(
            '[BLE][CTRL]  char ${c.uuid.str} write=$canWrite notify=$canNotify',
          );
          yield c;
        }
      }
    }

    final scope = prefSvc != null ? [prefSvc] : services;
    for (final c in scanChars(scope)) {
      final id = c.uuid.str.toLowerCase();
      final canWrite = c.properties.write || c.properties.writeWithoutResponse;
      final canNotify = c.properties.notify;
      if (id.contains('12345678-1234-1234-1234-1234567890a1') && canWrite) {
        provChar = c;
      }
      if (id.contains('12345678-1234-1234-1234-1234567890a2') && canNotify) {
        infoChar = c;
      }
      if (id.contains('12345678-1234-1234-1234-1234567890a3') && canWrite) {
        cmdChar = c;
      }
    }

    infoChar ??= _firstWhereOrNull<BluetoothCharacteristic>(
      scanChars(scope),
      (c) => c.properties.notify,
    );

    cmdChar ??= _firstWhereOrNull<BluetoothCharacteristic>(scanChars(scope), (
      c,
    ) {
      final canWrite = c.properties.write || c.properties.writeWithoutResponse;
      if (!canWrite) return false;
      final prov = provChar;
      if (prov != null && _guidEq(c.uuid, prov.uuid)) {
        return false;
      }
      return true;
    });

    if (infoChar == null || cmdChar == null) {
      _showSnack('BLE kontrol karakteristikleri bulunamadı.');
      try {
        await safeBleDisconnect(targetDevice, reason: 'ble_ctrl_chars_missing');
      } catch (_) {}
      _bleCtrlConnecting = false;
      await openBleSetupFallback();
      return;
    }

    try {
      await _bleCtrlNotifySub?.cancel();
    } catch (_) {}
    _bleCtrlNotifySub = null;
    try {
      await _bleCtrlConnSub?.cancel();
    } catch (_) {}
    _bleCtrlConnSub = null;
    try {
      _bleCtrlStatusTimer?.cancel();
    } catch (_) {}
    _bleCtrlStatusTimer = null;
    try {
      await notifySub?.cancel();
    } catch (_) {}
    notifySub = null;

    final framer = _BleJsonFramer();
    try {
      await infoChar.setNotifyValue(true);
    } catch (_) {}

    debugPrint(
      '[BLE][CTRL] using svc=${prefSvc?.uuid.str ?? 'n/a'} '
      'info=${infoChar.uuid.str} cmd=${cmdChar.uuid.str}',
    );

    _bleCtrlDevice = targetDevice;
    _syncBrandFromBleRuntimeHint(targetDevice.platformName);
    _bleCtrlInfoChar = infoChar;
    _bleCtrlCmdChar = cmdChar;

    _bleCtrlConnSub = targetDevice.connectionState.listen((st) async {
      if (st == BluetoothConnectionState.disconnected) {
        debugPrint('[BLE][CTRL] disconnected');
        try {
          await _bleCtrlNotifySub?.cancel();
        } catch (_) {}
        _bleCtrlNotifySub = null;
        try {
          _bleCtrlStatusTimer?.cancel();
        } catch (_) {}
        _bleCtrlStatusTimer = null;
        if (mounted) {
          _safeSetState(() {
            _bleControlMode = false;
            _bleSessionAuthed = false;
            _bleSessionAuthCompleter = null;
            _bleCtrlDevice = null;
            _bleCtrlInfoChar = null;
            _bleCtrlCmdChar = null;
          });
        } else {
          _bleControlMode = false;
          _bleSessionAuthed = false;
          _bleSessionAuthCompleter = null;
          _bleCtrlDevice = null;
          _bleCtrlInfoChar = null;
          _bleCtrlCmdChar = null;
          _bleLastTsMs = null;
        }
        _showSnack('BLE bağlantısı koptu.');
        final targetId6 = await _getBleTargetId6FromPrefs();
        final activeId6 = _deviceId6ForMqtt();
        if (targetId6 != null && activeId6 != null && targetId6 == activeId6) {
          unawaited(
            Future<void>.delayed(const Duration(seconds: 3), () async {
              await _autoConnectBleIfNeeded().timeout(
                const Duration(seconds: 15),
                onTimeout: () {
                  debugPrint('[BLE][AUTO] Retry auto connect timeout');
                },
              );
            }),
          );
        } else {
          debugPrint(
            '[BLE][AUTO] skip retry after disconnect target=${targetId6 ?? "-"} active=${activeId6 ?? "-"}',
          );
        }
      }
    });

    final initialStateCompleter = Completer<DeviceState>();
    _bleCtrlNotifySub = infoChar.lastValueStream.listen((data) {
      try {
        final chunk = utf8.decode(data, allowMalformed: true);
        debugPrint('[BLE][CTRL] raw notify chunk: $chunk');

        void applyObject(Map<String, dynamic> obj) {
          if (obj['claim'] is Map<String, dynamic>) {
            final c = (obj['claim'] as Map).cast<String, dynamic>();
            final ok = c['ok'];
            if (ok is bool && ok) {
              final st = state;
              if (mounted && st != null) {
                _safeSetState(() {
                  st.ownerExists = true;
                  st.ownerSetupDone = true;
                  connected = true;
                  _lastUpdate = DateTime.now();
                });
              }
            }
            return;
          }

          if (obj['unown'] is Map<String, dynamic>) {
            final u = (obj['unown'] as Map).cast<String, dynamic>();
            final ok = u['ok'];
            if (ok is bool && ok) {
              final st = state;
              if (mounted && st != null) {
                _safeSetState(() {
                  st.ownerExists = false;
                  st.ownerSetupDone = false;
                  connected = true;
                  _lastUpdate = DateTime.now();
                });
              }
              _bleSessionAuthed = false;
              _showSnack('Owner kaldırıldı.');
            } else {
              final err = u['err']?.toString() ?? 'unknown';
              _showSnack('Owner kaldırılamadı: $err');
            }
            return;
          }

          if (obj['invite'] is Map<String, dynamic>) {
            final inv = (obj['invite'] as Map).cast<String, dynamic>();
            if (_bleInviteCompleter != null &&
                !_bleInviteCompleter!.isCompleted) {
              _bleInviteCompleter!.complete(inv);
              _bleInviteCompleter = null;
            }
            return;
          }

          if (obj['apSession'] is Map<String, dynamic>) {
            final a = (obj['apSession'] as Map).cast<String, dynamic>();
            final tok = (a['token'] ?? '').toString();
            final non = (a['nonce'] ?? '').toString();
            if (tok.isNotEmpty) {
              _apSessionToken = tok;
              _apSessionNonce = non.isNotEmpty ? non : null;
              api.setApSessionToken(_apSessionToken);
              api.setApSessionNonce(_apSessionNonce);
              _bleApSessionCompleter?.complete(<String, String>{
                'token': tok,
                if (non.isNotEmpty) 'nonce': non,
              });
              _bleApSessionCompleter = null;
            }
            return;
          }

          if (obj['apCredentials'] is Map<String, dynamic>) {
            final a = (obj['apCredentials'] as Map).cast<String, dynamic>();
            final ssid = (a['ssid'] ?? '').toString().trim();
            final pass = (a['pass'] ?? '').toString().trim();
            if (ssid.isNotEmpty) {
              _bleApCredsCompleter?.complete(<String, String>{
                'ssid': ssid,
                'pass': pass,
              });
              _bleApCredsCompleter = null;
            }
            return;
          }

          if (obj['auth'] is Map<String, dynamic>) {
            final a = (obj['auth'] as Map).cast<String, dynamic>();
            final pairToken = (a['pairToken'] ?? a['qrToken'] ?? '')
                .toString()
                .trim();
            if (pairToken.isNotEmpty) {
              _bleControlPairToken = pairToken;
              final idFromAuth = _normalizeDeviceId6(
                (a['id6'] ?? a['deviceId'] ?? '').toString(),
              );
              final idHint =
                  idFromAuth ??
                  _normalizeDeviceId6(_deviceId6ForMqtt() ?? '');
              if (idHint != null && idHint.isNotEmpty) {
                unawaited(_applyPairToken(pairToken, deviceListId: idHint));
              } else {
                api.setPairToken(pairToken);
              }
            }
            final err = a['err']?.toString();
            if (err != null && err.isNotEmpty) {
              _bleLastAuthErr = err;
              if (err == 'invalid_qr_token') {
                unawaited(_handleInvalidQrToken());
              } else {
                _bleSessionAuthed = false;
              }
            }
            final nonce = a['nonce']?.toString();
            if (nonce != null && nonce.isNotEmpty) {
              _bleSessionAuthed = false;
              if (_bleNonceMapCompleter != null &&
                  !_bleNonceMapCompleter!.isCompleted) {
                _bleNonceMapCompleter!.complete(a);
                _bleNonceMapCompleter = null;
              }
              _bleNonceCompleter?.complete(nonce);
              _bleNonceCompleter = null;
            }
            final ok = a['ok'];
            if (ok is bool) {
              if (ok) {
                _bleSessionAuthed = true;
                _bleLastAuthErr = null;
                _bleAuthCompleter?.complete(true);
              } else {
                _bleSessionAuthed = false;
                _bleAuthCompleter?.complete(false);
              }
              _bleAuthCompleter = null;
            }

            if (err == 'not_authenticated') {
              final st = state;
              if (st != null && st.ownerExists) {
                unawaited(_bleEnsureOwnerAuthed());
              }
            }
            return;
          }

          final hasStatusOrEnv =
              obj.containsKey('status') ||
              obj.containsKey('env') ||
              obj.containsKey('s') ||
              obj.containsKey('e');
          if (!hasStatusOrEnv && obj.containsKey('wifi')) {
            debugPrint('[BLE][CTRL] wifi-only notify ignored for DeviceState');
            return;
          }
          if (!hasStatusOrEnv) return;

          int? ts;
          final meta = obj['meta'];
          if (meta is Map) {
            final v = meta['ts_ms'] ?? meta['tsMs'] ?? meta['ts'];
            if (v is int) ts = v;
            if (v is num) ts = v.toInt();
            if (v is String) ts = int.tryParse(v);
          }
          ts ??= (obj['ts_ms'] is int)
              ? (obj['ts_ms'] as int)
              : (obj['ts_ms'] is num ? (obj['ts_ms'] as num).toInt() : null);
          if (ts != null) {
            final last = _bleLastTsMs;
            if (last != null && ts <= last) return;
            _bleLastTsMs = ts;
          }

          final core = _extractStateCore(obj);
          final st = DeviceState.fromJson(core);
          if (mounted) {
            _safeSetState(() {
              state = st;
              _syncAutoHumControlsFromState(st);
              connected = true;
              _lastUpdate = DateTime.now();
            });
            _pushHistorySample(st);
            if (st.ownerExists && !_bleSessionAuthed) {
              unawaited(_bleEnsureOwnerAuthed());
            }
          }
          if (!initialStateCompleter.isCompleted) {
            initialStateCompleter.complete(st);
          }
        }

        try {
          final obj = jsonDecode(chunk);
          if (obj is Map<String, dynamic>) {
            debugPrint('[BLE][CTRL] notify (direct JSON)');
            applyObject(obj);
            return;
          }
        } catch (_) {}

        final completed = framer.feed(chunk);
        for (final jsonStr in completed) {
          final text = jsonStr.trim();
          debugPrint('[BLE][CTRL] notify (framed): $text');
          try {
            final obj = jsonDecode(text);
            if (obj is Map<String, dynamic>) {
              applyObject(obj);
            }
          } catch (e) {
            debugPrint('[BLE][CTRL] framed JSON decode error: $e');
            framer.reset();
          }
        }
      } catch (e, st) {
        debugPrint('[BLE][CTRL] notify parse error: $e');
        debugPrint(st.toString());
      }
    });

    DeviceState? initialState;
    try {
      initialState = await initialStateCompleter.future.timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      initialState = null;
    }
    final stNow = initialState ?? state;
    bool deviceOwned = stNow?.ownerExists == true;
    {
      final ch = _bleCtrlCmdChar;
      if (ch != null) {
        final supportsWithResp = ch.properties.write;
        final useWithoutResp = !supportsWithResp;
        final probe = Completer<Map<String, dynamic>>();
        _bleNonceMapCompleter = probe;
        try {
          debugPrint('[BLE][AUTH] probe -> GET_NONCE');
          await ch.write(
            utf8.encode(jsonEncode({'cmd': 'GET_NONCE'})),
            withoutResponse: useWithoutResp,
          );
        } catch (_) {}
        try {
          final a = await probe.future.timeout(const Duration(seconds: 3));
          final owned = a['owned'];
          if (owned is bool) {
            deviceOwned = owned;
            debugPrint('[BLE][AUTH] probe <- owned=$deviceOwned');
          }
        } catch (_) {
        } finally {
          _bleNonceMapCompleter = null;
        }
      }
    }

    Future<void> failAndDisconnect(
      String msg, {
      bool clearSetupCache = false,
    }) async {
      if (clearSetupCache) {
        await _clearBleTargetId6InPrefs();
        if (targetId6 != null) await _clearBleSetupCredsForId6(targetId6);
      }
      _showSnack(msg);
      try {
        await safeBleDisconnect(target, reason: 'ble_ctrl_auth_fail');
      } catch (_) {}
      _bleCtrlConnecting = false;
      _bleCtrlDevice = null;
      _bleCtrlInfoChar = null;
      _bleCtrlCmdChar = null;
      _bleControlPairToken = null;
      await openBleSetupFallback();
    }

    bool authedOk = false;
    if (deviceOwned) {
      await _bleEnsureOwnerAuthed(targetId6: targetId6);
      authedOk = _bleSessionAuthed;
      if (!authedOk) {
        await failAndDisconnect(
          'Owner doğrulaması başarısız: ${_bleLastAuthErr ?? 'auth_failed'}',
        );
        return;
      }
    } else {
      final u = (setupUser ?? '').trim();
      final p = (setupPass ?? '').trim();
      final hasSetupCreds = u.isNotEmpty && p.isNotEmpty;

      if (!hasSetupCreds) {
        if (allowUnownedWithoutSetupCreds) {
          debugPrint(
            '[BLE][AUTH] unowned flow allowed without setup creds (ap-guided)',
          );
          authedOk = true;
        } else {
          if (!interactive) {
            await failAndDisconnect(
              'Cihaz doğrulaması gerekli (kurulum user/pass yok).',
            );
            return;
          }
          await failAndDisconnect(
            'Cihaz doğrulama bilgisi eksik (user/pass).',
            clearSetupCache: interactive,
          );
          return;
        }
      } else {
        _bleLastAuthErr = null;
        _bleSessionAuthed = false;
        _bleAuthCompleter = Completer<bool>();
        try {
          final payload = jsonEncode(<String, dynamic>{
            'type': 'AUTH_SETUP',
            'user': u,
            'pass': p,
          });
          final supportsWithResp = cmdChar.properties.write;
          await cmdChar.write(
            utf8.encode(payload),
            withoutResponse: !supportsWithResp,
          );
        } catch (_) {}

        bool ok = false;
        try {
          ok = await _bleAuthCompleter!.future.timeout(
            const Duration(seconds: 4),
            onTimeout: () => false,
          );
        } catch (_) {
          ok = false;
        } finally {
          _bleAuthCompleter = null;
        }

        if (!ok) {
          final err = _bleLastAuthErr ?? 'auth_failed';
          if (err == 'not_authenticated') {
            await _bleEnsureOwnerAuthed();
            ok = _bleSessionAuthed;
          }
        }

        authedOk = ok;
        if (!authedOk) {
          final err = _bleLastAuthErr ?? 'auth_failed';
          await failAndDisconnect(
            err == 'invalid_user_or_pass'
                ? 'Kurulum user/pass hatalı; BLE bağlantısı engellendi.'
                : 'BLE doğrulama başarısız: $err',
            clearSetupCache: err == 'invalid_user_or_pass',
          );
          return;
        }

        if (!deviceOwned && kBleClaimOwnerOnQr) {
          await _ensureOwnerKeypair(generateIfMissing: true);
          final ownerPub = _ownerPubQ65B64;
          if (ownerPub == null || ownerPub.isEmpty) {
            await failAndDisconnect('Owner anahtarı üretilemedi.');
            return;
          }
          final claimCompleter = Completer<Map<String, dynamic>>();
          StreamSubscription<List<int>>? sub;
          try {
            final framer2 = _BleJsonFramer();
            sub = _bleCtrlInfoChar?.lastValueStream.listen((data) {
              try {
                final chunk = utf8.decode(data, allowMalformed: true);
                for (final js in framer2.feed(chunk)) {
                  final obj = jsonDecode(js);
                  if (obj is Map<String, dynamic> && obj['claim'] is Map) {
                    if (!claimCompleter.isCompleted) {
                      claimCompleter.complete(
                        (obj['claim'] as Map).cast<String, dynamic>(),
                      );
                    }
                    break;
                  }
                }
              } catch (_) {}
            });
            final payload = jsonEncode(<String, dynamic>{
              'type': 'CLAIM_REQUEST',
              'user': u,
              'pass': p,
              'owner_pubkey': _ownerPubQ65B64,
            });
            debugPrint('[BLE][AUTH] CLAIM_REQUEST send (ctrl)');
            final supportsWithResp2 = cmdChar.properties.write;
            await cmdChar.write(
              utf8.encode(payload),
              withoutResponse: !supportsWithResp2,
            );
            final claim = await claimCompleter.future.timeout(
              const Duration(seconds: 4),
            );
            final okClaim = claim['ok'] == true;
            if (!okClaim) {
              debugPrint(
                '[BLE][AUTH] CLAIM_REQUEST failed: ${claim['err'] ?? 'unknown'}',
              );
              await failAndDisconnect(
                'Owner atanamadı: ${claim['err'] ?? 'unknown'}',
              );
              return;
            }
            final claimToken = (claim['pairToken'] ?? claim['qrToken'] ?? '')
                .toString()
                .trim();
            if (claimToken.isNotEmpty) {
              final claimIdRaw =
                  (claim['id6'] ?? claim['deviceId'] ?? targetId6)
                      .toString()
                      .trim();
              final claimId = normalizeDeviceId6(claimIdRaw) ?? claimIdRaw;
              await _applyPairToken(
                claimToken,
                deviceListId: claimId.isNotEmpty ? claimId : targetId6,
              );
              debugPrint(
                '[BLE][AUTH] CLAIM_REQUEST persisted pairToken len=${claimToken.length} id=$claimId',
              );
            }
            debugPrint('[BLE][AUTH] CLAIM_REQUEST ok');
            _bleSessionAuthed = true;
            _bleLastAuthErr = null;
            _setClaimFlowStage(
              _ClaimFlowStage.claimed,
              detail: 'BLE üzerinden owner claim tamamlandı.',
            );
            final st = state;
            if (st != null) {
              st.ownerExists = true;
              st.ownerSetupDone = true;
            }
            api.setSigningKey(_ownerPrivD32 ?? _clientPrivD32);
            api.setApSessionToken(null);
            api.setApSessionNonce(null);
          } catch (_) {
            await failAndDisconnect('Owner atama zaman aşımı.');
            return;
          } finally {
            await sub?.cancel();
          }
        }

        await _setBleTargetId6InPrefs(targetId6);
        await _storeBleSetupCredsForId6(id6: targetId6, user: u, pass: p);
      }
    }

    _bleControlMode = true;
    _bleCtrlConnecting = false;
    _bleCtrlStatusTimer?.cancel();
    _bleCtrlStatusTimer = null;

    if (infoChar.properties.read && !allowUnownedWithoutSetupCreds) {
      try {
        final data = await infoChar.read();
        if (data.isNotEmpty) {
          final chunk = utf8.decode(data, allowMalformed: true);
          final completed = framer.feed(chunk);
          for (final jsonStr in completed) {
            final text = jsonStr.trim();
            debugPrint('[BLE][CTRL] initial read: $text');
            final obj = jsonDecode(text);
            if (obj is Map<String, dynamic>) {
              final core = _extractStateCore(obj);
              final st = DeviceState.fromJson(core);
              if (mounted) {
                _safeSetState(() {
                  state = st;
                  _syncAutoHumControlsFromState(st);
                  connected = true;
                  _lastUpdate = DateTime.now();
                });
                _pushHistorySample(st);
              }
            }
          }
        }
      } catch (e, st) {
        debugPrint('[BLE][CTRL] initial read error: $e');
        debugPrint(st.toString());
      }
    }

    if (interactive) {
      _showSnack(
        'BLE ile yönetim bağlantısı kuruldu (${targetDevice.platformName}).',
      );
    }
  }

  Future<void> _bleEnsureOwnerAuthedImpl({String? targetId6}) async {
    if (_bleCtrlCmdChar == null) return;
    if (_bleSessionAuthed) return;
    final inflight = _bleSessionAuthCompleter;
    if (inflight != null) {
      try {
        await inflight.future.timeout(const Duration(seconds: 6));
      } catch (_) {}
      return;
    }
    _bleSessionAuthCompleter = Completer<bool>();
    final ch = _bleCtrlCmdChar!;
    final supportsWithResp = ch.properties.write;
    final useWithoutResp = !supportsWithResp;
    final prevTimer = _bleCtrlStatusTimer;
    if (prevTimer != null) {
      try {
        prevTimer.cancel();
      } catch (_) {}
      _bleCtrlStatusTimer = null;
    }
    try {
      _bleLastAuthErr = null;
      final fromBleName = _extractId6FromBleName(
        _bleCtrlDevice?.platformName ?? '',
      );
      final id6 = (targetId6?.trim().isNotEmpty == true)
          ? targetId6!.trim()
          : (fromBleName ?? normalizeDeviceId6(_activeDeviceId ?? '') ?? '');
      final canonicalKey = canonicalizeDeviceId(id6) ?? id6;
      if (id6.isEmpty || canonicalKey.isEmpty) {
        _bleLastAuthErr = 'missing_device_id';
        debugPrint('[BLE][AUTH] missing canonical device id for auth');
        return;
      }
      final nonceMap = Completer<Map<String, dynamic>>();
      _bleNonceMapCompleter = nonceMap;
      try {
        debugPrint('[BLE][AUTH] probe -> GET_NONCE');
        await ch.write(
          utf8.encode(jsonEncode({'cmd': 'GET_NONCE'})),
          withoutResponse: useWithoutResp,
        );
      } catch (_) {}
      Map<String, dynamic>? authMap;
      try {
        authMap = await nonceMap.future.timeout(const Duration(seconds: 3));
      } catch (_) {
        authMap = null;
      } finally {
        if (_bleNonceMapCompleter == nonceMap) _bleNonceMapCompleter = null;
      }
      final nonce = authMap?['nonce']?.toString() ?? '';
      final owned = authMap?['owned'] == true;
      if (nonce.isEmpty) {
        _bleLastAuthErr = 'nonce_missing';
        debugPrint('[BLE][AUTH] nonce missing');
        return;
      }

      String? sigB64;
      if (owned) {
        await _ensureOwnerKeypair(generateIfMissing: false);
        final ownerPriv = _ownerPrivD32;
        if (ownerPriv == null || ownerPriv.isEmpty) {
          _bleLastAuthErr = 'missing_owner_key';
          _showSnack(
            'Owner anahtarı yok. Bluetooth ile doğrulama yapıp tekrar eşleştirin.',
          );
          return;
        }
        sigB64 = _bleSignNonceWithPrivKey(
          privD32: ownerPriv,
          deviceId6: id6,
          nonceB64: nonce,
        );
      } else {
        final storedPair = await _loadPairToken(canonicalKey);
        if (storedPair == null || storedPair.trim().isEmpty) {
          _bleLastAuthErr = 'missing_pair_token';
          _showSnack(
            'Bu cihaz için doğrulama kodu yok. Soft recovery açıp tekrar deneyin.',
          );
          return;
        }
        sigB64 = _bleSignNonceWithPairToken(
          pairTokenHex: storedPair.trim(),
          deviceId6: id6,
          nonceB64: nonce,
        );
      }
      if (sigB64 == null || sigB64.isEmpty) {
        _bleLastAuthErr = 'signature_failed';
        debugPrint('[BLE][AUTH] signature generation failed');
        return;
      }
      final authCompleter = Completer<bool>();
      _bleAuthCompleter = authCompleter;
      final auth = jsonEncode({'cmd': 'AUTH', 'nonce': nonce, 'sig': sigB64});
      debugPrint('[BLE][AUTH] -> AUTH (sig)');
      try {
        await ch.write(utf8.encode(auth), withoutResponse: useWithoutResp);
      } catch (e, st) {
        debugPrint('[BLE][AUTH] AUTH write error: $e');
        debugPrint(st.toString());
      }

      final ok = await authCompleter.future.timeout(const Duration(seconds: 5));
      _bleSessionAuthed = ok;
      debugPrint(
        '[BLE][AUTH] <- ok=$_bleSessionAuthed err=${_bleLastAuthErr ?? '-'}',
      );
    } on TimeoutException {
      _bleSessionAuthed = false;
      _bleLastAuthErr ??= 'auth_timeout';
      debugPrint('[BLE][AUTH] timeout err=${_bleLastAuthErr ?? '-'}');
    } catch (e, st) {
      _bleSessionAuthed = false;
      debugPrint('[BLE][AUTH] error: $e');
      debugPrint(st.toString());
    } finally {
      _bleNonceCompleter = null;
      _bleAuthCompleter = null;
      _bleSessionAuthCompleter?.complete(_bleSessionAuthed);
      _bleSessionAuthCompleter = null;
    }
  }

  String? _extractId6FromBleNameImpl(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return null;
    final m = RegExp(r'([0-9A-Fa-f]{6})\\s*$').firstMatch(n);
    return m?.group(1)?.toUpperCase();
  }

  Future<bool> _bleSendJsonImpl(Map<String, dynamic> body) async {
    final ch = _bleCtrlCmdChar;
    if (ch == null) return false;
    final payload = jsonEncode(body);
    final supportsWithResp = ch.properties.write;
    final useWithoutResp = !supportsWithResp;
    try {
      await ch.write(utf8.encode(payload), withoutResponse: useWithoutResp);
      return true;
    } catch (e, st) {
      debugPrint('[BLE] write error: $e');
      debugPrint(st.toString());
      return false;
    }
  }
}
