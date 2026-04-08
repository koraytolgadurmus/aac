part of 'main.dart';

extension _HomeScreenTransportSendPart on _HomeScreenState {
  String _newCmdId() {
    final r = math.Random.secure();
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final bytes = List<int>.generate(6, (_) => r.nextInt(256));
    final rnd = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'c$ts$rnd';
  }

  Map<String, dynamic> _withCmdId(Map<String, dynamic> body) {
    final v = body['cmdId'];
    if (v is String && v.trim().isNotEmpty) return body;
    final out = Map<String, dynamic>.from(body);
    out['cmdId'] = _newCmdId();
    return out;
  }

  dynamic _normalizeCmdForKey(dynamic v) {
    if (v is Map) {
      final out = SplayTreeMap<String, dynamic>();
      v.forEach((k, val) {
        out[k.toString()] = _normalizeCmdForKey(val);
      });
      return out;
    }
    if (v is List) {
      return v.map(_normalizeCmdForKey).toList();
    }
    return v;
  }

  String _canonicalCmdKey(Map<String, dynamic> body) {
    return jsonEncode(_normalizeCmdForKey(body));
  }

  bool _isLocalOwnerClaimRequiredFailure() {
    final status = api.lastHttpStatus;
    final err = (api.lastErrCode ?? '').toLowerCase();
    final msg = (api.lastError ?? '').toLowerCase();
    final haystack = '$err $msg';
    if (haystack.contains('owner_required') ||
        haystack.contains('owner required') ||
        haystack.contains('not owner') ||
        haystack.contains('not_owner') ||
        haystack.contains('unclaimed')) {
      return true;
    }
    if (status == 401 || status == 403) {
      return haystack.contains('owner');
    }
    return false;
  }

  void _maybeHintOwnerClaimRequired({required String transport}) {
    final now = DateTime.now();
    if (_ownerClaimHintUntil != null && now.isBefore(_ownerClaimHintUntil!)) {
      return;
    }
    _ownerClaimHintUntil = now.add(const Duration(seconds: 20));
    debugPrint(
      '[OWNER] command rejected; owner claim required transport=$transport '
      'status=${api.lastHttpStatus ?? "-"} err=${api.lastErrCode ?? "-"}',
    );
    _showSnack(
      'Cihaz owner atanmamış. Bluetooth ile bağlanıp soft recovery açarak owner atayın.',
    );
  }

  Future<bool> _sendToDevice(
    Map<String, dynamic> body, {
    bool forceLocalOnly = false,
  }) {
    // Prevent request storms (multiple UI actions + planner ticks) from
    // overwhelming the device/local network stack. Serialize sends.
    final completer = Completer<bool>();
    _cmdSendQueue = _cmdSendQueue.then((_) async {
      try {
        final ok = await _sendToDeviceInner(
          body,
          forceLocalOnly: forceLocalOnly,
        );
        completer.complete(ok);
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    });
    return completer.future;
  }

  Future<bool> _sendToDeviceInner(
    Map<String, dynamic> body, {
    bool forceLocalOnly = false,
  }) async {
    cloudApi.clearLastCmdDiag();
    body = _withCmdId(body);
    bool okLocal = false;
    final now = DateTime.now();
    final baseHost = Uri.tryParse(api.baseUrl)?.host ?? '';
    final onSoftAp = baseHost == '192.168.4.1';
    final lastLocalOkAt = _lastLocalOkAt;
    final localOkAgeMs = lastLocalOkAt != null
        ? now.difference(lastLocalOkAt).inMilliseconds
        : -1;
    final localRecentOk =
        !onSoftAp &&
        lastLocalOkAt != null &&
        localOkAgeMs >= 0 &&
        localOkAgeMs <= 60000;
    final recentStateUpdate =
        !onSoftAp &&
        _lastUpdate != null &&
        now.difference(_lastUpdate!) <= const Duration(seconds: 8);
    final localHasCachedIp = _getActiveDeviceLastIp()?.isNotEmpty == true;
    final localIp = (!onSoftAp && baseHost.isNotEmpty) ? baseHost : '-';

    final bleReady = _bleControlMode && _bleCtrlCmdChar != null;
    final apReady = onSoftAp;
    final cloudId6 = _deviceId6ForMqtt();
    final cloudReady = _cloudReady(now);
    final cloudHealthy = _cloudHealthy(now);
    final cloudPrefer = _cloudPreferActive(now);
    final authRole = (state?.authRole ?? '').trim().toUpperCase();
    final cloudRole = (_activeDevice?.cloudRole ?? '').trim().toUpperCase();
    final nonOwnerKnown =
        authRole == 'USER' ||
        authRole == 'GUEST' ||
        cloudRole == 'USER' ||
        cloudRole == 'GUEST';
    var localHealthOk = false;
    var localHealth = 'n/a';
    var cloudTried = false;

    void logPath({required String chosen}) {
      _lastCmdTransport = chosen;
      debugPrint(
        '[PATH] localIp=$localIp localHealth=$localHealth '
        'ble=${bleReady ? 'ready' : 'no'} ap=${apReady ? 'ready' : 'no'} '
        'cloud=${cloudReady ? (cloudHealthy ? 'ok' : 'try') : 'no'} '
        'chosen=$chosen',
      );
    }

    Future<bool> sendViaBle() async {
      logPath(chosen: 'ble');
      try {
        final s = state;
        final type = body['type']?.toString();
        final cmd = body['cmd']?.toString();
        final isAuthFlow =
            type == 'CLAIM_REQUEST' ||
            type == 'GET_NONCE' ||
            type == 'AUTH' ||
            cmd == 'GET_NONCE' ||
            cmd == 'AUTH';
        if (s != null && s.ownerExists && !isAuthFlow) {
          final force =
              _bleLastAuthErr == 'not_authenticated' ||
              _bleLastAuthErr == 'auth_timeout';
          if (!_bleSessionAuthed || force) {
            _bleLastAuthErr = null;
            await _bleEnsureOwnerAuthed();
            if (!_bleSessionAuthed) {
              debugPrint('[CMD][BLE] blocked: not authenticated');
              _bleLastAuthErr ??= 'not_authenticated';
              return false;
            }
          }
        }

        if (!isAuthFlow && !_bleSessionAuthed) {
          final pairToken = await _resolveActivePairToken();
          debugPrint(
            '[CMD][BLE] resolved pairToken len=${pairToken?.length ?? 0}',
          );
          if (pairToken == null || pairToken.isEmpty) {
            debugPrint('[CMD][BLE] missing pairToken, aborting');
            return false;
          }
        }

        final ok = await _bleSendJson(body);
        if (!ok) {
          debugPrint('[CMD][BLE] send failed');
        }
        return ok;
      } catch (e) {
        debugPrint('[CMD][BLE] error: $e');
        return false;
      }
    }

    // BLE control mode'da komutları doğrudan BLE'ye gönder.
    // Local/AP probing gecikmesini ve timeout zincirini önler.
    if (_bleControlMode && bleReady) {
      localHealth = 'skip_ble_mode';
      return sendViaBle();
    }

    // 0) Cloud-first only when there is no local target at all.
    // If local target exists, always try local first for deterministic actuation
    // and keep cloud as fallback.
    if (!forceLocalOnly &&
        localIp == '-' &&
        !localRecentOk &&
        cloudReady &&
        cloudId6 != null &&
        cloudId6.isNotEmpty &&
        (cloudHealthy || cloudPrefer)) {
      final refreshed = await _cloudRefreshIfNeeded();
      if (!_cloudAuthReady(now) && !refreshed) {
        _markCloudFail();
      } else {
        final gateOk = await _cloudCommandPathReadyNow(id6: cloudId6);
        if (gateOk) {
          cloudTried = true;
          logPath(chosen: 'cloud');
          final cloudBody = Map<String, dynamic>.from(body);
          final ok = await _sendCloudCommandWithRecovery(
            id6: cloudId6,
            body: cloudBody,
            reason: 'cloud_first',
          );
          if (ok) return true;
        } else {
          debugPrint('[CMD] cloud_first skipped: path not ready');
        }
      }
    }

    // 1) Local health check (prefer local only if fresh/reachable)
    final skipLocalForCloudPrefer =
        !forceLocalOnly &&
        !onSoftAp &&
        cloudReady &&
        cloudId6 != null &&
        cloudId6.isNotEmpty &&
        baseHost.endsWith('.local') &&
        (!_localDnsFailActive || !localHasCachedIp
            ? true
            : _localUnreachableActive);
    if (skipLocalForCloudPrefer) {
      localHealth = 'skip_cloud_prefer';
    } else if (!forceLocalOnly && nonOwnerKnown) {
      localHealth = 'skip_non_owner';
    } else if (localIp != '-') {
      if (localRecentOk || recentStateUpdate) {
        localHealthOk = true;
        localHealth = 'cached_ok';
      } else {
        localHealthOk = await _probeLocalHealthWithRetry(api.baseUrl);
      }
    }
    localHealth = localHealthOk ? 'ok' : 'fail';
    final lastLocalOkStillWarm =
        _lastLocalOkAt != null &&
        now.difference(_lastLocalOkAt!) < const Duration(minutes: 5);
    final allowLocalSoftRetry =
        !localHealthOk && localIp != '-' && lastLocalOkStillWarm;
    if (!localHealthOk && localIp != '-') {
      if (allowLocalSoftRetry) {
        localHealth = 'soft_retry';
        debugPrint('[CMD] local health failed; soft-retry enabled');
      } else {
        debugPrint('[CMD] local health failed, skipping local');
      }
    }

    if (localHealthOk || allowLocalSoftRetry) {
      logPath(chosen: 'local');
      try {
        final identityOk = await _ensureEndpointMatchesSelectedDevice(
          transport: 'local',
        );
        if (!identityOk) {
          localHealth = 'mismatch';
          localHealthOk = false;
        } else {
          final selectedId6 = _selectedId6ForGuard();
          final localBody = selectedId6 != null && selectedId6.isNotEmpty
              ? <String, dynamic>{
                  ...body,
                  'deviceId': selectedId6,
                  'id6': selectedId6,
                }
              : Map<String, dynamic>.from(body);
          final safeBody = ApiService._sanitizeForLog(localBody);
          debugPrint(
            '[CMD] local send -> ${api.baseUrl} body=${jsonEncode(safeBody)}',
          );
          okLocal = await api.sendCommand(localBody);
          if (kDebugMode) {
            debugPrint('[CMD] local result ok=$okLocal');
          }
          if (okLocal) {
            _captureLastIpForBaseInBackground(api.baseUrl);
            _localDnsFailUntil = null;
            _localUnreachableUntil = null;
            _lastLocalOkAt = DateTime.now();
            _markConnected();
          } else {
            if (_isLocalOwnerClaimRequiredFailure()) {
              _maybeHintOwnerClaimRequired(transport: 'local');
            }
            final lastErr = api.lastError;
            if (lastErr != null && lastErr.trim().isNotEmpty) {
              debugPrint('[CMD] local failed: $lastErr');
              if (_looksLikeDnsLookupFailure(lastErr) &&
                  !_baseHostLooksLikeIpv4(api.baseUrl)) {
                _markLocalDnsFailure();
              } else if (_looksLikeLocalUnreachable(lastErr)) {
                _markLocalUnreachable();
              }
            }
            // If firmware rejects local control because cloud mode is enabled,
            // auto-switch app to cloud and retry the command once via cloud.
            if (api.lastHttpStatus == 403 &&
                api.lastErrCode == 'local_disabled_cloud') {
              await _autoEnableCloudLocalFlag(reason: 'local_disabled_cloud');
              final id6 = _deviceId6ForMqtt();
              if (id6 != null && id6.isNotEmpty && _cloudReady(now)) {
                final refreshed = await _cloudRefreshIfNeeded();
                if (_cloudAuthReady(now) || refreshed) {
                  debugPrint(
                    '[CMD] retry via cloud after local_disabled_cloud',
                  );
                  final cloudBody = Map<String, dynamic>.from(localBody);
                  final ok = await _sendCloudCommandWithRecovery(
                    id6: id6,
                    body: cloudBody,
                    reason: 'local_disabled_cloud',
                  );
                  if (ok) return true;
                }
              }
            }
            if (api.lastDnsFailure && !_baseHostLooksLikeIpv4(api.baseUrl)) {
              _markLocalDnsFailure();
            }
          }
          if (!okLocal &&
              !forceLocalOnly &&
              !cloudTried &&
              cloudReady &&
              cloudId6 != null &&
              cloudId6.isNotEmpty) {
            final refreshed = await _cloudRefreshIfNeeded();
            if (_cloudAuthReady(now) || refreshed) {
              final gateOk = await _cloudCommandPathReadyNow(id6: cloudId6);
              if (gateOk) {
                debugPrint('[CMD] local failed -> trying cloud fallback');
                final cloudBody = Map<String, dynamic>.from(localBody);
                final ok = await _sendCloudCommandWithRecovery(
                  id6: cloudId6,
                  body: cloudBody,
                  reason: 'local_failed_fallback',
                );
                if (ok) return true;
              } else {
                debugPrint(
                  '[CMD] local failed but cloud fallback skipped: path not ready',
                );
              }
            } else {
              _markCloudFail();
            }
          }
          return okLocal;
        }
      } catch (e) {
        debugPrint('[CMD] local send error: $e');
        if (_looksLikeDnsLookupFailure(e) &&
            !_baseHostLooksLikeIpv4(api.baseUrl)) {
          _markLocalDnsFailure();
        } else if (_looksLikeLocalUnreachable(e)) {
          _markLocalUnreachable();
        }
        if (!forceLocalOnly &&
            !cloudTried &&
            cloudReady &&
            cloudId6 != null &&
            cloudId6.isNotEmpty) {
          final refreshed = await _cloudRefreshIfNeeded();
          if (_cloudAuthReady(now) || refreshed) {
            final gateOk = await _cloudCommandPathReadyNow(id6: cloudId6);
            if (gateOk) {
              debugPrint('[CMD] local error -> trying cloud fallback');
              final cloudBody = Map<String, dynamic>.from(body);
              final ok = await _sendCloudCommandWithRecovery(
                id6: cloudId6,
                body: cloudBody,
                reason: 'local_error_fallback',
              );
              if (ok) return true;
            } else {
              debugPrint(
                '[CMD] local error but cloud fallback skipped: path not ready',
              );
            }
          } else {
            _markCloudFail();
          }
        }
        return false;
      }
    }

    // 1b) Cloud fallback when local is not reachable (MQTT must be connected)
    if (!forceLocalOnly &&
        !cloudTried &&
        cloudReady &&
        cloudId6 != null &&
        cloudId6.isNotEmpty) {
      final refreshed = await _cloudRefreshIfNeeded();
      if (!_cloudAuthReady(now) && !refreshed) {
        _markCloudFail();
      } else {
        final gateOk = await _cloudCommandPathReadyNow(id6: cloudId6);
        if (gateOk) {
          logPath(chosen: 'cloud');
          final cloudBody = Map<String, dynamic>.from(body);
          final ok = await _sendCloudCommandWithRecovery(
            id6: cloudId6,
            body: cloudBody,
            reason: 'cloud_fallback',
          );
          if (ok) return true;
        } else {
          debugPrint('[CMD] cloud_fallback skipped: path not ready');
        }
      }
    }

    // 2) SoftAP fallback (prefer AP over BLE when AP is reachable)
    if (apReady) {
      logPath(chosen: 'ap');
      try {
        final identityOk = await _ensureEndpointMatchesSelectedDevice(
          transport: 'ap',
        );
        if (!identityOk) {
          _lastCmdTransport = 'none';
          return false;
        }
        final selectedId6 = _selectedId6ForGuard();
        final apBody = selectedId6 != null && selectedId6.isNotEmpty
            ? <String, dynamic>{
                ...body,
                'deviceId': selectedId6,
                'id6': selectedId6,
              }
            : Map<String, dynamic>.from(body);
        await _maybeSwitchToApBaseUrlIfReachable();
        final safeBody = ApiService._sanitizeForLog(apBody);
        debugPrint(
          '[CMD] ap send -> ${api.baseUrl} body=${jsonEncode(safeBody)}',
        );
        okLocal = await api.sendCommand(apBody);
        if (kDebugMode) {
          debugPrint('[CMD] ap result ok=$okLocal');
        }
        if (okLocal) {
          _lastLocalOkAt = DateTime.now();
          _markConnected();
        } else if (_isLocalOwnerClaimRequiredFailure()) {
          _maybeHintOwnerClaimRequired(transport: 'ap');
        }
        if (okLocal) return true;
      } catch (e) {
        debugPrint('[CMD] ap send error: $e');
      }
    }

    // 3) BLE fallback
    if (bleReady) {
      return sendViaBle();
    }

    logPath(chosen: 'none');
    _showSnack('Cihaza bağlantı yok (Local/BLE/AP kapalı).');
    return false;
  }

  Future<bool> _send(
    Map<String, dynamic> body, {
    bool promptForQr = true,
    bool forceLocalOnly = false,
  }) async {
    final cloudRaw = body['cloud'];
    final isCloudDisableCmd =
        cloudRaw is Map &&
        (cloudRaw['enabled'] == false || cloudRaw['enabled'] == 0);
    if (isCloudDisableCmd && !_consumeCloudDisableIntent()) {
      debugPrint('[CLOUD] blocked cloud disable command: missing user intent');
      return false;
    }
    if (_isNoopCommandAgainstState(body, state)) {
      debugPrint('[CMD] skip noop key=${_canonicalCmdKey(body)}');
      return false;
    }
    debugPrint('[API SEND] -> ${jsonEncode(body)}');
    if (!_canControlDevice) {
      _showSnack(t.t('device_not'));
    }
    final now = DateTime.now();
    final key = _canonicalCmdKey(body);
    final isControlPayload =
        body.keys.every(
          (k) => const {
            'masterOn',
            'lightOn',
            'cleanOn',
            'ionOn',
            'mode',
            'fanPercent',
            'autoHumEnabled',
            'autoHumTarget',
            'rgb',
            'cmdId',
            'userIdHash',
          }.contains(k),
        ) &&
        body.keys.any(
          (k) => const {
            'masterOn',
            'lightOn',
            'cleanOn',
            'ionOn',
            'mode',
            'fanPercent',
            'autoHumEnabled',
            'autoHumTarget',
            'rgb',
          }.contains(k),
        );
    final dedupWindow = isControlPayload
        ? const Duration(seconds: 4)
        : const Duration(milliseconds: 800);
    if (_lastCmdKey == key &&
        _lastCmdSendAt != null &&
        now.difference(_lastCmdSendAt!) < dedupWindow) {
      debugPrint('[CMD] dedup skip key=$key');
      return false;
    }
    final lastAt = _lastCmdSendAt;
    if (lastAt != null) {
      final delta = now.difference(lastAt);
      const minGap = Duration(milliseconds: 250);
      if (delta < minGap) {
        await Future.delayed(minGap - delta);
      }
    }
    _lastCmdSendAt = DateTime.now();
    _lastCmdKey = key;
    _markPollFast();
    final ok = await _sendToDevice(body, forceLocalOnly: forceLocalOnly);
    if (!ok) {
      if (_bleControlMode && _bleCtrlCmdChar != null) {
        final err = _bleLastAuthErr;
        if (err == 'missing_owner_key') {
          _showSnack(
            'BLE kontrol için bu telefonda owner anahtarı yok. '
            'Cihazı factory resetleyip bu telefondan owner yapın veya owner yapılan telefondan bağlanın.',
          );
        } else if (err != null && err.isNotEmpty) {
          _showSnack('BLE yetki hatası: $err');
        } else {
          _showSnack(t.t('command_failed'));
        }
      } else {
        final cloudMsg = _cloudCmdFailureMessage();
        if (cloudMsg != null) {
          _showSnack('${t.t('command_failed')} ($cloudMsg)');
        } else {
          _showSnack(t.t('command_failed'));
        }
      }
      return false;
    }
    _markPollFast();
    _applyOptimisticControlState(body);
    if (_lastCmdTransport == 'ble' &&
        _bleControlMode &&
        _bleCtrlCmdChar != null) {
      return true;
    }
    unawaited(
      _fetchStateSmart().then((s) async {
        if (s != null && mounted) {
          // ignore: invalid_use_of_protected_member
          setState(() {
            state = s;
            _syncAutoHumControlsFromState(s);
          });
          await _maybeShowOtaPrompt(s);
        }
      }),
    );
    return true;
  }

  void _applyOptimisticControlState(Map<String, dynamic> body) {
    final st = state;
    if (st == null) return;
    bool readBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase();
        return s == 'true' || s == '1' || s == 'yes';
      }
      return false;
    }

    int readInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    bool changed = false;

    if (body.containsKey('masterOn')) {
      st.masterOn = readBool(body['masterOn']);
      changed = true;
    }
    if (body.containsKey('lightOn')) {
      st.lightOn = readBool(body['lightOn']);
      changed = true;
    }
    if (body.containsKey('cleanOn')) {
      st.cleanOn = readBool(body['cleanOn']);
      changed = true;
    }
    if (body.containsKey('ionOn')) {
      st.ionOn = readBool(body['ionOn']);
      changed = true;
    }
    if (body.containsKey('mode')) {
      st.mode = readInt(body['mode']);
      changed = true;
    }
    if (body.containsKey('fanPercent')) {
      st.fanPercent = readInt(body['fanPercent']).clamp(0, 100);
      changed = true;
    }
    if (body.containsKey('autoHumEnabled')) {
      st.autoHumEnabled = readBool(body['autoHumEnabled']);
      changed = true;
    }
    if (body.containsKey('autoHumTarget')) {
      st.autoHumTarget = readInt(body['autoHumTarget']).clamp(30, 70);
      changed = true;
    }

    final rgbRaw = body['rgb'];
    if (rgbRaw is Map) {
      if (rgbRaw.containsKey('on')) st.rgbOn = readBool(rgbRaw['on']);
      if (rgbRaw.containsKey('r')) st.r = readInt(rgbRaw['r']).clamp(0, 255);
      if (rgbRaw.containsKey('g')) st.g = readInt(rgbRaw['g']).clamp(0, 255);
      if (rgbRaw.containsKey('b')) st.b = readInt(rgbRaw['b']).clamp(0, 255);
      if (rgbRaw.containsKey('brightness')) {
        st.rgbBrightness = readInt(rgbRaw['brightness']).clamp(1, 100);
      }
      changed = true;
    }

    if (!changed || !mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      state = st;
      _syncAutoHumControlsFromState(st);
    });
  }

  bool get _canControlDevice => connected || _bleControlMode;

  String? get _activeCanonicalDeviceId {
    final id = (_activeDevice?.id ?? _activeDeviceId ?? '').trim();
    if (id.isEmpty) return null;
    return canonicalizeDeviceId(id);
  }

  String? _selectedId6ForGuard() {
    final raw = _activeCanonicalDeviceId ?? _activeDeviceId ?? '';
    return _normalizeDeviceId6(raw);
  }

  String? _extractEndpointId6FromStatusJson(Map<String, dynamic> root) {
    String? pick(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isEmpty) return null;
      return _normalizeDeviceId6(s);
    }

    final core = _extractStateCore(root);
    final meta = (core['meta'] is Map<String, dynamic>)
        ? core['meta'] as Map<String, dynamic>
        : (root['meta'] is Map<String, dynamic>)
        ? root['meta'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final network = (core['network'] is Map<String, dynamic>)
        ? core['network'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final fromMeta = pick(meta['id6']) ?? pick(meta['deviceId']);
    if (fromMeta != null) return fromMeta;
    final fromCore = pick(core['id6']) ?? pick(core['deviceId']);
    if (fromCore != null) return fromCore;

    final apSsid = (network['apSsid'] ?? '').toString().trim();
    final fromAp = extractId6FromKnownApSsid(apSsid);
    if (fromAp != null) return _normalizeDeviceId6(fromAp);
    return null;
  }

  String? _extractEndpointId6FromInfoJson(Map<String, dynamic> root) {
    String? pick(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isEmpty) return null;
      return _normalizeDeviceId6(s);
    }

    final fromRoot = pick(root['id6']) ?? pick(root['deviceId']);
    if (fromRoot != null) return fromRoot;
    final apSsid = (root['apSsid'] ?? root['ssid'] ?? '').toString().trim();
    final fromAp = extractId6FromKnownApSsid(apSsid);
    if (fromAp != null) return _normalizeDeviceId6(fromAp);
    return null;
  }

  String _endpointBaseKey(String rawBase) {
    final u = Uri.tryParse(rawBase.trim());
    final host = (u?.host ?? '').trim().toLowerCase();
    final port = u?.hasPort == true ? ':${u!.port}' : '';
    return host.isNotEmpty ? '$host$port' : rawBase.trim().toLowerCase();
  }

  void _rememberEndpointId6ForCurrentBase(String id6) {
    final normalized = _normalizeDeviceId6(id6);
    if (normalized == null || normalized.isEmpty) return;
    final key = _endpointBaseKey(api.baseUrl);
    _endpointId6ByBase[key] = normalized;
    _endpointId6SeenAtByBase[key] = DateTime.now();
  }

  bool _apStickyActive() =>
      _preferApUntil != null && DateTime.now().isBefore(_preferApUntil!);

  void _markApSticky([Duration ttl = const Duration(seconds: 75)]) {
    _lastApReachableAt = DateTime.now();
    _preferApUntil = DateTime.now().add(ttl);
  }

  String? _recentEndpointId6ForCurrentBase({
    Duration maxAge = const Duration(seconds: 90),
  }) {
    final key = _endpointBaseKey(api.baseUrl);
    final seenAt = _endpointId6SeenAtByBase[key];
    final id6 = _endpointId6ByBase[key];
    if (seenAt == null || id6 == null || id6.isEmpty) return null;
    if (DateTime.now().difference(seenAt) > maxAge) return null;
    return id6;
  }

  String? _recentEndpointId6ForBase(
    String rawBase, {
    Duration maxAge = const Duration(seconds: 90),
  }) {
    final key = _endpointBaseKey(rawBase);
    final seenAt = _endpointId6SeenAtByBase[key];
    final id6 = _endpointId6ByBase[key];
    if (seenAt == null || id6 == null || id6.isEmpty) return null;
    if (DateTime.now().difference(seenAt) > maxAge) return null;
    return id6;
  }

  Future<String?> _readEndpointId6({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    Future<String?> quickRead(String path) async {
      try {
        final uri = Uri.parse('${api.baseUrl}$path');
        final r = await http
            .get(uri, headers: api.authHeaders())
            .timeout(timeout);
        if (r.statusCode < 200 || r.statusCode >= 300) return null;
        final obj = jsonDecode(r.body);
        if (obj is! Map<String, dynamic>) return null;
        if (path == '/info') {
          return _extractEndpointId6FromInfoJson(obj);
        }
        return _extractEndpointId6FromStatusJson(obj);
      } catch (_) {
        return null;
      }
    }

    final quickStatus = await quickRead('/api/status');
    if (quickStatus != null && quickStatus.isNotEmpty) {
      _rememberEndpointId6ForCurrentBase(quickStatus);
      return quickStatus;
    }
    final quickInfo = await quickRead('/info');
    if (quickInfo != null && quickInfo.isNotEmpty) {
      _rememberEndpointId6ForCurrentBase(quickInfo);
      return quickInfo;
    }

    try {
      final status = await api.fetchStatusRaw(timeout: timeout);
      final fromStatus = status == null
          ? null
          : _extractEndpointId6FromStatusJson(status);
      if (fromStatus != null && fromStatus.isNotEmpty) {
        _rememberEndpointId6ForCurrentBase(fromStatus);
        return fromStatus;
      }
    } catch (e) {
      debugPrint('[GUARD] read endpoint id from status failed: $e');
    }
    try {
      final info = await api.fetchInfoRaw(timeout: timeout);
      final fromInfo = info == null
          ? null
          : _extractEndpointId6FromInfoJson(info);
      if (fromInfo != null && fromInfo.isNotEmpty) {
        _rememberEndpointId6ForCurrentBase(fromInfo);
        return fromInfo;
      }
    } catch (e) {
      debugPrint('[GUARD] read endpoint id from info failed: $e');
    }
    return _recentEndpointId6ForCurrentBase();
  }

  void _showDeviceMismatchWarning({
    required String selectedId6,
    required String connectedId6,
    required String transport,
  }) {
    final now = DateTime.now();
    if (_deviceMismatchWarnUntil != null &&
        now.isBefore(_deviceMismatchWarnUntil!)) {
      return;
    }
    _deviceMismatchWarnUntil = now.add(const Duration(seconds: 4));
    _showSnack(
      'Seçili cihaz ($selectedId6) ile bağlı cihaz ($connectedId6) farklı. '
      '${transport.toUpperCase()} üzerinden komut engellendi. Lütfen doğru cihaza bağlanın.',
    );
  }

  bool _hostHintsSelectedId6(String selectedId6) {
    final host = (Uri.tryParse(api.baseUrl)?.host ?? '').trim().toLowerCase();
    if (host.isEmpty) return false;
    if (_baseHostLooksLikeIpv4(host)) {
      final lastIp = (_getActiveDeviceLastIp() ?? '').trim();
      return lastIp.isNotEmpty && host == lastIp;
    }
    final mdnsHost = (mdnsHostForId6(
      selectedId6,
      rawIdHint: selectedId6,
    )).trim().toLowerCase();
    if (mdnsHost.isNotEmpty && host == '$mdnsHost.local') return true;
    return host.contains(selectedId6);
  }

  Future<bool> _ensureEndpointMatchesSelectedDevice({
    required String transport,
  }) async {
    final selectedId6 = _selectedId6ForGuard();
    if (selectedId6 == null || selectedId6.isEmpty) return true;
    final endpointId6 = await _readEndpointId6();
    if (endpointId6 == null || endpointId6.isEmpty) {
      final cached = _recentEndpointId6ForCurrentBase(
        maxAge: const Duration(minutes: 20),
      );
      if (cached == selectedId6) {
        debugPrint(
          '[GUARD] endpoint id unavailable; allowing via cached match selected=$selectedId6',
        );
        return true;
      }
      if (_hostHintsSelectedId6(selectedId6)) {
        debugPrint(
          '[GUARD] endpoint id unavailable; allowing via host hint selected=$selectedId6 host=${Uri.tryParse(api.baseUrl)?.host ?? ''}',
        );
        return true;
      }
      _showSnack(
        'Bağlı cihaz kimliği doğrulanamadı. ${transport.toUpperCase()} komutu güvenlik nedeniyle engellendi.',
      );
      return false;
    }
    if (endpointId6 == selectedId6) return true;
    _lastEndpointMismatchAt = DateTime.now();
    debugPrint(
      '[GUARD] device mismatch transport=$transport selected=$selectedId6 endpoint=$endpointId6',
    );
    _showDeviceMismatchWarning(
      selectedId6: selectedId6,
      connectedId6: endpointId6,
      transport: transport,
    );
    return false;
  }

  Future<bool> _endpointMatchesSelectedForState({
    required String transport,
    bool warnOnMismatch = true,
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    final selectedId6 = _selectedId6ForGuard();
    if (selectedId6 == null || selectedId6.isEmpty) return true;
    final endpointId6 = await _readEndpointId6(timeout: timeout);
    if (endpointId6 == null || endpointId6.isEmpty) {
      // State poll sırasında geçici auth/dns dalgalanması olabilir; burada bloklamıyoruz.
      return true;
    }
    if (endpointId6 == selectedId6) return true;
    _lastEndpointMismatchAt = DateTime.now();
    debugPrint(
      '[GUARD] state mismatch transport=$transport selected=$selectedId6 endpoint=$endpointId6',
    );
    if (warnOnMismatch) {
      _showDeviceMismatchWarning(
        selectedId6: selectedId6,
        connectedId6: endpointId6,
        transport: transport,
      );
    }
    return false;
  }

  bool get _canClaimOwner {
    final s = state;
    if (s == null) return false;
    if (s.ownerSetupDone || s.ownerExists) return false;
    // Owner only via BLE in secure mode
    return !_bleBusy;
  }

  /// Resolve a .local hostname via mDNS and return an IPv4 string if found, else null.
  Future<String?> _mdnsResolveHost(
    String host, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final fqdn = host.endsWith('.local') ? host : '$host.local';
    debugPrint('[mDNS] resolving $fqdn ...');
    final ip = await mdns.mdnsResolveHost(fqdn, timeout: timeout);
    if (ip != null) {
      debugPrint('[mDNS] A $fqdn -> $ip');
      unawaited(_updateActiveDeviceLastIp(ip));
      unawaited(_updateActiveDeviceMdnsHost(host.replaceAll('.local', '')));
    } else {
      debugPrint('[mDNS] no IPv4 A record for $fqdn');
    }
    return ip;
  }

  void _captureLastIpForBaseInBackground(String rawBase) {
    final host = Uri.tryParse(rawBase)?.host.trim() ?? '';
    if (host.isEmpty) return;
    if (_baseHostLooksLikeIpv4(host)) {
      unawaited(_updateActiveDeviceLastIp(host));
      return;
    }
    if (!host.endsWith('.local')) return;
    final now = DateTime.now();
    final last = _mdnsBgResolveAtByHost[host];
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _mdnsBgResolveAtByHost[host] = now;
    unawaited(() async {
      try {
        await _mdnsResolveHost(
          host,
          timeout: const Duration(milliseconds: 1200),
        );
      } catch (_) {}
    }());
  }
}
