part of 'main.dart';

extension _HomeScreenDeviceBootstrapPart on _HomeScreenState {
  Future<void> _setActiveDevice(_SavedDevice dev) async {
    final prevId = _activeDeviceId;
    _lastActiveDeviceSwitchAt = DateTime.now();
    _activeDeviceSwitchEpoch++;
    _activeSwitchRecoverySeq++;
    if (prevId != null && prevId != dev.id) {
      _captureRuntimeForDevice(prevId);
    }
    final existingIndex = _devices.indexWhere((d) => d.id == dev.id);
    if (existingIndex == -1) {
      _devices.add(dev);
    } else {
      _devices[existingIndex] = dev;
    }
    _activeDeviceId = dev.id;
    _localUnauthorizedHits = 0;
    _nextLocalUnauthorizedRecoveryAt = null;
    final nextId6 = _normalizeDeviceId6(dev.id);

    var normalized = dev.baseUrl;
    if (normalized.isNotEmpty &&
        !normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    normalized = _normalizedStoredBaseForDevice(dev, normalized);
    final autoBrand = resolveDeviceBrand(
      firmwareProduct: state?.deviceProduct ?? deviceProductSlugFromAny(dev.id),
      bleName: _bleCtrlDevice?.platformName ?? '',
      baseUrl: normalized,
      mdnsHost: dev.mdnsHost ?? '',
      apSsid: '',
      currentBrand: dev.brand,
    ).brand.trim();
    if (autoBrand.isNotEmpty && autoBrand != dev.brand) {
      debugPrint('[BRAND] setActive auto-correct ${dev.brand} -> $autoBrand');
      dev.brand = autoBrand;
      if (existingIndex != -1) {
        _devices[existingIndex].brand = autoBrand;
      }
    }
    if (nextId6 != null && nextId6.isNotEmpty) {
      final host = Uri.tryParse(normalized)?.host.trim().toLowerCase() ?? '';
      final isAp = host == '192.168.4.1';
      final isIpv4 = _baseHostLooksLikeIpv4(host);
      final isMdnsLike = RegExp(
        r'^[a-z0-9-]+-[0-9]{6}(\.local)?$',
      ).hasMatch(host);
      if (isMdnsLike && !isAp && !isIpv4) {
        final canonicalHost = mdnsHostForId6(nextId6, rawIdHint: dev.id);
        final canonicalMdns = '$canonicalHost.local';
        if (host != canonicalMdns && host != canonicalHost) {
          normalized = 'http://$canonicalMdns';
          debugPrint(
            '[DEVICES] switch normalized mismatched mDNS host -> $normalized',
          );
        }
      }
    }

    if (prevId != null && prevId != dev.id) {
      _cloudOwnerExistsOverride = null;
      _cloudOwnerSetupDoneOverride = null;
      _lastCloudOkAt = null;
      _cloudFailUntil = null;
      _cloudPreferUntil = null;
      _lastLocalOkAt = null;
      _localDnsFailUntil = null;
      _localUnreachableUntil = null;
      _preferApUntil = null;
      _lastApReachableAt = null;
      _transportSessionOwner = null;
      _transportRecoveryCooldownUntil = null;
      state = null;
      connected = false;
      _lastUpdate = null;
    }
    _allowNetworkAutoPolling();

    _cloudUserEnabledLocal = dev.cloudEnabledLocal;
    _apSessionToken = null;
    _apSessionNonce = null;
    api.clearLocalSession();
    api.resetAuthBackoff();
    _restoreRuntimeForDevice(dev.id);
    api.setApSessionToken(_apSessionToken);
    api.setApSessionNonce(_apSessionNonce);

    if (prevId != null && prevId != dev.id && _bleControlMode) {
      final bleNameId6 = _extractId6FromBleName(
        _bleCtrlDevice?.platformName ?? '',
      );
      final bleTargetId6 = await _getBleTargetId6FromPrefs();
      final currentBleId6 = bleNameId6 ?? bleTargetId6;
      if (nextId6 == null ||
          currentBleId6 == null ||
          currentBleId6 != nextId6) {
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
            reason: 'device_switch_ble_target_mismatch',
          );
        } catch (_) {}
        _bleCtrlDevice = null;
        _bleCtrlInfoChar = null;
        _bleCtrlCmdChar = null;
        _bleControlMode = false;
        _bleSessionAuthed = false;
        _bleSessionAuthCompleter = null;
      }
    }

    if ((dev.pairToken ?? '').trim().isEmpty) {
      final storedPair = await _loadPairToken(dev.id);
      if (storedPair != null && storedPair.trim().isNotEmpty) {
        dev.pairToken = storedPair.trim();
      }
    }

    // ignore: invalid_use_of_protected_member
    setState(() {
      baseUrl = normalized;
      api.baseUrl = normalized;
      _urlCtl.text = normalized;
      api.setPairToken(dev.pairToken);
      final hasWaqi =
          dev.waqiLat != null &&
          dev.waqiLon != null &&
          (dev.waqiName ?? '').trim().isNotEmpty;
      _waqiLocation = hasWaqi
          ? WaqiLocation(
              name: dev.waqiName!.trim(),
              lat: dev.waqiLat!,
              lon: dev.waqiLon!,
            )
          : null;
      _waqiInstantInfo = _waqiInfoFromDeviceCache(dev);
      _waqiInstantDeviceId = dev.id;
      _doaWaterDurationMin = dev.doaWaterDurationMin ?? 2;
      _doaWaterIntervalHr = dev.doaWaterIntervalHr ?? 8;
      _doaWaterAutoEnabled = dev.doaWaterAutoEnabled ?? false;
    });

    await _saveDevicesToPrefs();
    if (nextId6 != null && nextId6.isNotEmpty) {
      await _setBleTargetId6InPrefs(nextId6);
    }

    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('baseUrl', baseUrl);
      await _persistPairToken(dev.pairToken, deviceListId: dev.id);
      final brand = dev.brand;
      final themeKey = _themeModeKeyForBrand(brand);
      final themeUserKey = _themeUserSetKeyForBrand(brand);
      final themeStr = p.getString(themeKey);
      _themeUserSet = p.getBool(themeUserKey) ?? false;
      if (!_themeUserSet) {
        final ThemeMode mode = brand == kDoaDeviceBrand
            ? ThemeMode.light
            : ThemeMode.dark;
        widget.onThemeChanged(mode);
      } else if (themeStr != null) {
        final ThemeMode mode = themeStr == 'light'
            ? ThemeMode.light
            : ThemeMode.dark;
        widget.onThemeChanged(mode);
      }
    } catch (_) {}

    _poller?.cancel();
    _startPolling();
    unawaited(
      _kickActiveDeviceRecovery(
        expectedDeviceId: dev.id,
        recoverySeq: _activeSwitchRecoverySeq,
      ),
    );
  }

  Future<void> _kickActiveDeviceRecovery({
    required String expectedDeviceId,
    required int recoverySeq,
  }) async {
    bool stillValid() =>
        mounted &&
        _activeDeviceId == expectedDeviceId &&
        _activeSwitchRecoverySeq == recoverySeq;
    if (!stillValid()) return;

    final delays = <Duration>[
      Duration.zero,
      const Duration(milliseconds: 900),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
      const Duration(seconds: 7),
    ];
    for (final d in delays) {
      if (!stillValid()) return;
      if (d > Duration.zero) {
        await Future.delayed(d);
        if (!stillValid()) return;
      }
      await _connectionTick(force: true);
      final canForceBle =
          state?.pairingWindowActive == true ||
          state?.softRecoveryActive == true ||
          state?.apSessionActive == true;
      await _autoConnectBleIfNeeded(force: canForceBle);
      try {
        final s = await _fetchStateSmart(force: true);
        if (!stillValid()) return;
        if (s != null) {
          final endpointOk = await _endpointMatchesSelectedForState(
            transport: 'switch',
            warnOnMismatch: false,
          );
          if (!endpointOk) {
            // ignore: invalid_use_of_protected_member
            setState(() {
              connected = false;
            });
            continue;
          }
          final pathConnected = _isControlPathConnectedNow();
          // ignore: invalid_use_of_protected_member
          setState(() {
            state = s;
            connected = pathConnected;
            _lastUpdate = DateTime.now();
            _syncAutoHumControlsFromState(s);
            _pushHistorySample(s);
          });
          _cacheActiveRuntimeHealth(
            localOk: !_cloudReady(DateTime.now()),
            cloudOk: _cloudReady(DateTime.now()),
          );
          debugPrint(
            '[DEVICES] switch recovery success device=$expectedDeviceId',
          );
          return;
        }
      } catch (_) {}
    }
    debugPrint('[DEVICES] switch recovery pending device=$expectedDeviceId');
  }

  Future<void> _ensureOwnerKeypair({required bool generateIfMissing}) async {
    try {
      final privB64 = await _secureStorage.read(
        key: _HomeScreenState._ownerPrivD32Key,
      );
      final pubB64 = await _secureStorage.read(
        key: _HomeScreenState._ownerPubQ65Key,
      );
      if (privB64 != null &&
          privB64.isNotEmpty &&
          pubB64 != null &&
          pubB64.isNotEmpty) {
        _ownerPrivD32 = base64Decode(privB64);
        _ownerPubQ65B64 = pubB64;
        return;
      }
    } catch (_) {}

    if (!generateIfMissing) return;

    final kp = _generateOwnerKeypairP256();
    _ownerPrivD32 = kp.privateD32;
    _ownerPubQ65B64 = kp.publicB64;
    try {
      await _secureStorage.write(
        key: _HomeScreenState._ownerPrivD32Key,
        value: kp.privateB64,
      );
      await _secureStorage.write(
        key: _HomeScreenState._ownerPubQ65Key,
        value: kp.publicB64,
      );
    } catch (_) {}
  }

  Future<void> _ensureClientKeypair({required bool generateIfMissing}) async {
    try {
      final privB64 = await _secureStorage.read(
        key: _HomeScreenState._clientPrivD32Key,
      );
      final pubB64 = await _secureStorage.read(
        key: _HomeScreenState._clientPubQ65Key,
      );
      if (privB64 != null &&
          privB64.isNotEmpty &&
          pubB64 != null &&
          pubB64.isNotEmpty) {
        _clientPrivD32 = base64Decode(privB64);
        _clientPubQ65B64 = pubB64;
        return;
      }
    } catch (_) {}

    if (!generateIfMissing) return;

    final kp = _generateOwnerKeypairP256(); // same curve/format
    _clientPrivD32 = kp.privateD32;
    _clientPubQ65B64 = kp.publicB64;
    try {
      await _secureStorage.write(
        key: _HomeScreenState._clientPrivD32Key,
        value: kp.privateB64,
      );
      await _secureStorage.write(
        key: _HomeScreenState._clientPubQ65Key,
        value: kp.publicB64,
      );
    } catch (_) {}
  }

  Future<void> _refreshOwnerSigningKey() async {
    await _ensureOwnerKeypair(generateIfMissing: false);
    if (_ownerPrivD32 == null || _ownerPrivD32!.isEmpty) {
      debugPrint(
        '[AUTH] owner key missing after claim; cannot refresh signing key',
      );
      return;
    }
    api.setSigningKey(_ownerPrivD32 ?? _clientPrivD32);
    // Clear any stale AP session so signed auth is used.
    api.setApSessionToken(null);
    api.setApSessionNonce(null);
  }

  String? _cloudUserIdHash() {
    final pubB64 = _ownerPubQ65B64 ?? _clientPubQ65B64;
    if (pubB64 == null || pubB64.isEmpty) return null;
    try {
      final pubBytes = base64Decode(pubB64);
      return _sha256Hex(pubBytes);
    } catch (_) {
      return null;
    }
  }

  String? _cloudOwnerPubKeyB64() {
    final pubB64 = _ownerPubQ65B64 ?? _clientPubQ65B64;
    if (pubB64 == null || pubB64.isEmpty) return null;
    return pubB64;
  }

  Future<void> _initDevices(SharedPreferences p) async {
    // Cihaz listesi ve aktif cihazı prefs'ten yükle.
    final legacyPair = p.getString('pair_token');
    try {
      final raw = p.getString('devices');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final loaded = <_SavedDevice>[];
          for (var i = 0; i < decoded.length; i++) {
            final item = decoded[i];
            if (item is! Map) continue;
            try {
              final dev = _SavedDevice.fromJson(
                Map<String, dynamic>.from(item),
              );
              if (dev.id.trim().isEmpty) continue;
              loaded.add(dev);
            } catch (e) {
              debugPrint('[DEVICES] skip invalid item[$i]: $e');
            }
          }
          _devices = loaded;
        }
      }
    } catch (e) {
      debugPrint('[DEVICES] parse error: $e');
      _devices = [];
    }
    _normalizeSavedDeviceInventory();

    _activeDeviceId = p.getString('active_device_id')?.trim();

    if (_devices.isEmpty) {
      // Eski tek cihazlı prefs'ten migrate et.
      final legacyBaseRaw = p.getString('baseUrl');
      var legacyBase = legacyBaseRaw ?? baseUrl;
      if (!legacyBase.startsWith('http://') &&
          !legacyBase.startsWith('https://')) {
        legacyBase = 'http://$legacyBase';
      }
      final recoveredId = _activeDeviceId;
      final normalizedLegacyBase = _normalizeBaseUrl(legacyBase) ?? legacyBase;
      final hasMeaningfulLegacyBase =
          legacyBaseRaw != null &&
          normalizedLegacyBase.trim().isNotEmpty &&
          normalizedLegacyBase.trim() != 'http://192.168.4.1';
      final hasLegacyDeviceSeed =
          hasMeaningfulLegacyBase ||
          (legacyPair?.trim().isNotEmpty ?? false) ||
          (recoveredId?.isNotEmpty ?? false);
      if (hasLegacyDeviceSeed) {
        final idHint = recoveredId?.trim() ?? '';
        final brandFromId = idHint.isNotEmpty
            ? brandFromDeviceProduct(deviceProductSlugFromAny(idHint)).trim()
            : '';
        final brandFromBase = brandFromHostHint(normalizedLegacyBase).trim();
        final inferredBrand = brandFromId.isNotEmpty
            ? brandFromId
            : (brandFromBase.isNotEmpty ? brandFromBase : kDefaultDeviceBrand);
        final dev = _SavedDevice(
          id: (recoveredId != null && recoveredId.isNotEmpty)
              ? recoveredId
              : 'dev_${DateTime.now().millisecondsSinceEpoch}',
          brand: inferredBrand,
          suffix: '',
          baseUrl: legacyBase,
          pairToken: p.getString('pair_token'),
          doaWaterDurationMin: null,
          doaWaterIntervalHr: null,
          doaWaterAutoEnabled: null,
        );
        _devices = [dev];
        _activeDeviceId = dev.id;
        debugPrint(
          '[DEVICES] list was empty -> created fallback device id=${dev.id} base=${dev.baseUrl}',
        );
        await _saveDevicesToPrefs(p);
      } else {
        _activeDeviceId = null;
      }
    }

    // Legacy cleanup: local HTTP user/pass are no longer used.
    try {
      await p.remove('auth_user');
      await p.remove('auth_pass');
      await p.remove('admin_user');
      await p.remove('admin_pass');
      await p.remove('pair_token');
    } catch (_) {}

    final active = _devices.isEmpty
        ? null
        : _devices.firstWhere(
            (d) => d.id == _activeDeviceId,
            orElse: () => _devices.first,
          );
    _activeDeviceId = active?.id;
    _cloudUserEnabledLocal = active?.cloudEnabledLocal ?? false;

    // Migrate any persisted pair tokens into secure storage (per-device).
    for (final d in _devices) {
      final rawPair = d.pairToken?.trim() ?? '';
      if (rawPair.isNotEmpty) {
        await _persistPairToken(rawPair, deviceListId: d.id);
      }
      final stored = await _loadPairToken(d.id);
      if (stored != null && stored.isNotEmpty) {
        d.pairToken = stored;
      } else if (rawPair.isNotEmpty) {
        d.pairToken = rawPair;
      } else {
        d.pairToken = null;
      }
    }

    if (legacyPair != null) {
      final trimmedLegacyPair = legacyPair.trim();
      if (trimmedLegacyPair.isNotEmpty && _activeDeviceId != null) {
        await _persistPairToken(
          trimmedLegacyPair,
          deviceListId: _activeDeviceId!,
        );
        final idx = _devices.indexWhere((d) => d.id == _activeDeviceId);
        if (idx != -1) _devices[idx].pairToken = trimmedLegacyPair;
      }
    }

    if (active != null) {
      baseUrl = _normalizedStoredBaseForDevice(active, active.baseUrl);
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'http://$baseUrl';
      }
      api = ApiService(baseUrl);
      _urlCtl.text = baseUrl;
      final storedPair = active.pairToken;
      if (storedPair != null && storedPair.isNotEmpty) {
        api.setPairToken(storedPair);
      } else {
        await _persistPairToken(null, deviceListId: active.id);
      }

      // Doa otomatik sulama varsayılanları
      _doaWaterDurationMin = active.doaWaterDurationMin ?? 2;
      _doaWaterIntervalHr = active.doaWaterIntervalHr ?? 8;
      _doaWaterAutoEnabled = active.doaWaterAutoEnabled ?? false;
      _waqiInstantInfo = _waqiInfoFromDeviceCache(active);
      _waqiInstantDeviceId = active.id;
    } else {
      baseUrl = 'http://192.168.4.1';
      api = ApiService(baseUrl);
      _urlCtl.text = baseUrl;
      _doaWaterDurationMin = 2;
      _doaWaterIntervalHr = 8;
      _doaWaterAutoEnabled = false;
      _waqiInstantInfo = null;
      _waqiInstantDeviceId = null;
    }

    // Eski tek cihazlı auth_user/auth_pass anahtarları artık kullanılmıyor (pairToken + session).
    try {
      await p.setString('baseUrl', baseUrl);
      await p.remove('auth_user');
      await p.remove('auth_pass');
      await p.remove('admin_user');
      await p.remove('admin_pass');
    } catch (_) {}
  }

  Future<void> _saveDevicesToPrefs([SharedPreferences? prefs]) async {
    prefs ??= await SharedPreferences.getInstance();
    try {
      _normalizeSavedDeviceInventory();
      final encoded = jsonEncode(_devices.map((e) => e.toJson()).toList());
      await prefs.setString('devices', encoded);
      if (_activeDeviceId != null) {
        await prefs.setString('active_device_id', _activeDeviceId!);
      } else {
        await prefs.remove('active_device_id');
      }
    } catch (e) {
      debugPrint('[DEVICES] save error: $e');
    }
  }

  Future<void> _updateActiveDeviceBaseUrl(String newBase) async {
    if (_devices.isEmpty || _activeDeviceId == null) return;
    final idx = _devices.indexWhere((d) => d.id == _activeDeviceId);
    if (idx == -1) return;
    final normalized = _normalizeBaseUrl(newBase) ?? newBase.trim();
    final host = Uri.tryParse(normalized)?.host.trim() ?? '';
    if (_baseHostLooksLikeIpv4(host)) {
      _devices[idx].lastIp = host;
    }
    _devices[idx].baseUrl = _normalizedStoredBaseForDevice(
      _devices[idx],
      normalized,
    );
    await _saveDevicesToPrefs();
  }

  String _preferredStableLocalBaseUrl(String rawBase) {
    final normalized = _normalizeBaseUrl(rawBase) ?? rawBase.trim();
    final uri = Uri.tryParse(normalized);
    final host = uri?.host.trim() ?? '';
    if (host.isEmpty || host == '192.168.4.1') return normalized;
    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return normalized;
    final isIpv4 = _baseHostLooksLikeIpv4(host);
    final canonicalHost = mdnsHostForId6(
      id6,
      rawIdHint: _activeDeviceId ?? id6,
    ).toLowerCase();
    final isCanonicalMdns =
        host == '$canonicalHost.local' || host == canonicalHost;
    if (!isIpv4 && !isCanonicalMdns) return normalized;
    final scheme = ((uri?.scheme ?? 'http').isEmpty)
        ? 'http'
        : (uri?.scheme ?? 'http');
    final portNum = uri?.port;
    final hasCustomPort =
        portNum != null && portNum != 0 && portNum != 80 && portNum != 443;
    final port = hasCustomPort ? ':$portNum' : '';
    return '$scheme://$canonicalHost.local$port';
  }

  bool _localFallbackAvailableForUi() {
    if (_bleControlMode) return true;
    if (state?.apSessionActive == true || state?.softRecoveryActive == true) {
      return true;
    }
    if (_deviceId6ForMqtt() != null) return true;
    final active = _activeDevice;
    if ((active?.lastIp ?? '').trim().isNotEmpty) return true;
    final currentHost = Uri.tryParse(api.baseUrl)?.host.trim() ?? '';
    if (currentHost.isNotEmpty) return true;
    return false;
  }
}
