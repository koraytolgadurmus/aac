part of 'main.dart';

extension _HomeScreenCloudAuthTransportPart on _HomeScreenState {
  bool _cloudHealthy(DateTime now) {
    if (_lastCloudOkAt == null) return false;
    return now.difference(_lastCloudOkAt!) <= kCloudHealthWindow;
  }

  Future<int> _mergeCloudDevices(
    List<Map<String, dynamic>> devices, {
    bool autoSelectIfNeeded = false,
  }) async {
    var changed = false;
    final mergedIds = <String>{};

    for (final item in devices) {
      final rawId = (item['deviceId'] ?? item['id6'] ?? '').toString().trim();
      final canonicalId = canonicalizeDeviceId(rawId);
      if (canonicalId == null || canonicalId.isEmpty) continue;
      mergedIds.add(canonicalId);

      final role = (item['role'] ?? '').toString().trim().toUpperCase();
      final source = (item['source'] ?? '').toString().trim();
      final cloudThingName = (item['thingName'] ?? '').toString().trim();
      final cloudBrand = (item['brand'] ?? '').toString().trim();
      final cloudSuffix = (item['suffix'] ?? '').toString().trim();
      final cloudHasBrand = cloudBrand.isNotEmpty;
      final cloudHasSuffix = cloudSuffix.isNotEmpty;
      final existing = _findDeviceByCanonical(canonicalId);
      if (existing == null) {
        final thingName = cloudThingName.isNotEmpty
            ? cloudThingName
            : thingNameFromAny(canonicalId);
        final mdnsHost = mdnsHostFromAny(canonicalId);
        final storedPair =
            await _loadPairToken(canonicalId) ??
            (thingName != null ? await _loadPairToken(thingName) : null);
        _devices.add(
          _SavedDevice(
            id: canonicalId,
            brand: cloudBrand.isNotEmpty ? cloudBrand : kDefaultDeviceBrand,
            suffix: cloudSuffix,
            baseUrl: _preferredDisplayBaseUrlForDevice(
              _SavedDevice(
                id: canonicalId,
                brand: cloudBrand.isNotEmpty ? cloudBrand : kDefaultDeviceBrand,
                suffix: cloudSuffix,
                baseUrl: _defaultBaseUrlForCloudDevice(canonicalId),
                thingName: thingName,
                mdnsHost: mdnsHost,
              ),
            ),
            thingName: thingName,
            mdnsHost: mdnsHost,
            pairToken: storedPair,
            cloudLinked: true,
            cloudRole: role.isEmpty ? null : role,
            cloudSource: source.isEmpty ? null : source,
          ),
        );
        changed = true;
        continue;
      }

      final desiredBase = existing.baseUrl.trim().isEmpty
          ? _defaultBaseUrlForCloudDevice(canonicalId)
          : existing.baseUrl;
      final normalizedDesiredBase = _preferredDisplayBaseUrlForDevice(
        _SavedDevice(
          id: canonicalId,
          brand: cloudHasBrand ? cloudBrand : existing.brand,
          suffix: cloudHasSuffix ? cloudSuffix : existing.suffix,
          baseUrl: desiredBase,
          thingName:
              existing.thingName ??
              (cloudThingName.isNotEmpty
                  ? cloudThingName
                  : thingNameFromAny(canonicalId)),
          mdnsHost: existing.mdnsHost ?? mdnsHostFromAny(canonicalId),
        ),
      );
      if (existing.baseUrl != normalizedDesiredBase ||
          (cloudHasBrand && existing.brand != cloudBrand) ||
          (cloudHasSuffix && existing.suffix != cloudSuffix) ||
          !existing.cloudLinked ||
          existing.cloudRole != (role.isEmpty ? null : role) ||
          existing.cloudSource != (source.isEmpty ? null : source)) {
        existing.baseUrl = normalizedDesiredBase;
        if (cloudHasBrand) existing.brand = cloudBrand;
        if (cloudHasSuffix) existing.suffix = cloudSuffix;
        existing.cloudLinked = true;
        existing.cloudRole = role.isEmpty ? null : role;
        existing.cloudSource = source.isEmpty ? null : source;
        existing.thingName ??= cloudThingName.isNotEmpty
            ? cloudThingName
            : thingNameFromAny(canonicalId);
        existing.mdnsHost ??= mdnsHostFromAny(canonicalId);
        changed = true;
      }

      final localHasCustomPresentation =
          existing.brand.trim().isNotEmpty &&
          (!isDefaultDeviceBrand(existing.brand.trim()) ||
              existing.suffix.trim().isNotEmpty);
      final cloudMissingPresentation = !cloudHasBrand && !cloudHasSuffix;
      final cloudMissingSuffix =
          existing.suffix.trim().isNotEmpty && !cloudHasSuffix;
      if (role == 'OWNER' &&
          localHasCustomPresentation &&
          (cloudMissingPresentation || cloudMissingSuffix) &&
          _cloudLoggedIn()) {
        await cloudApi.updateDeviceName(
          canonicalId,
          brand: existing.brand,
          suffix: existing.suffix,
          timeout: const Duration(seconds: 6),
        );
      }
    }

    if (mergedIds.isNotEmpty) {
      for (final d in _devices) {
        final canonical = canonicalizeDeviceId(d.id);
        if (canonical == null || canonical.isEmpty) continue;
        if (!mergedIds.contains(canonical) && d.cloudLinked) {
          d.cloudLinked = false;
          d.cloudRole = null;
          d.cloudSource = null;
          changed = true;
        }
      }
    }

    _dedupeSavedDevicesByCanonical();

    if (_activeDeviceId != null) {
      final hasExact = _devices.any((d) => d.id == _activeDeviceId);
      final hasCanonical = _findDeviceByCanonical(_activeDeviceId!) != null;
      if (!hasExact && !hasCanonical) {
        final stale = _activeDeviceId!.trim();
        final staleCanonical = canonicalizeDeviceId(stale);
        if (staleCanonical != null && staleCanonical.isNotEmpty) {
          final rebuilt = _SavedDevice(
            id: staleCanonical,
            brand: _preferredBrandForDeviceHint(staleCanonical),
            baseUrl: api.baseUrl,
            thingName: thingNameFromAny(staleCanonical),
            mdnsHost: mdnsHostFromAny(staleCanonical),
          );
          _devices.add(rebuilt);
          _activeDeviceId = rebuilt.id;
          changed = true;
          debugPrint(
            '[DEVICES] active device missing after cloud sync; rebuilt local entry id=${rebuilt.id}',
          );
        } else {
          debugPrint(
            '[DEVICES] active device no longer exists -> clearing active id ($_activeDeviceId)',
          );
          _activeDeviceId = null;
          changed = true;
        }
      }
    }

    if (autoSelectIfNeeded && _activeDevice == null && _devices.isNotEmpty) {
      if (_devices.length == 1) {
        await _setActiveDevice(_devices.first);
        changed = false;
      } else {
        debugPrint(
          '[DEVICES] active device is null after cloud sync (count=${_devices.length}); waiting for explicit user selection',
        );
      }
    } else if (changed) {
      // ignore: invalid_use_of_protected_member
      if (mounted) setState(() {});
      await _saveDevicesToPrefs();
    }

    return mergedIds.length;
  }

  Future<int?> _syncCloudDevices({
    bool autoSelectIfNeeded = false,
    bool showSnack = false,
    bool force = false,
  }) async {
    if (!_cloudLoggedIn()) return null;
    final now = DateTime.now();
    final activeId6 = _deviceId6ForMqtt();
    final cachedListMissesActive =
        activeId6 != null &&
        activeId6.isNotEmpty &&
        !_cloudApiDeviceIds.contains(activeId6);
    final canUseRecentCache =
        !force &&
        !autoSelectIfNeeded &&
        !showSnack &&
        !cachedListMissesActive &&
        _cloudDevicesFetchedAt != null &&
        now.difference(_cloudDevicesFetchedAt!) < const Duration(seconds: 20);
    if (canUseRecentCache) return _cloudApiDeviceCount;
    final existing = _cloudDeviceSyncFuture;
    if (existing != null) return await existing;

    final future = () async {
      final refreshed = await _cloudRefreshIfNeeded();
      if (!_cloudAuthReady(DateTime.now()) && !refreshed) return null;

      final me = await cloudApi.fetchMe(const Duration(seconds: 8));
      if (me != null) {
        _applyCloudFeaturesFromMe(me);
        final email = (me['email'] ?? '').toString().trim();
        if (email.isNotEmpty && email != _cloudUserEmail) {
          _cloudUserEmail = email;
          await _saveCloudAuth();
        }
      }

      final devices = await cloudApi.listDevices(const Duration(seconds: 8));
      if (devices == null) return null;
      _cloudApiDeviceIds = devices
          .map(
            (d) => normalizeDeviceId6(
              (d['deviceId'] ?? d['id6'] ?? '').toString(),
            ),
          )
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false);
      final count = await _mergeCloudDevices(
        devices,
        autoSelectIfNeeded: autoSelectIfNeeded,
      );
      _cloudApiDeviceCount = devices.length;
      _cloudDevicesFetchedAt = DateTime.now();
      // ignore: invalid_use_of_protected_member
      if (mounted) setState(() {});
      if (showSnack) {
        _showSnack(
          devices.isEmpty
              ? 'Cloud hesabında kayıtlı cihaz bulunamadı'
              : '${devices.length} cihaz cloud hesabından yüklendi',
        );
      }
      return count;
    }();

    _cloudDeviceSyncFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_cloudDeviceSyncFuture, future)) {
        _cloudDeviceSyncFuture = null;
      }
    }
  }

  Future<void> _handleCloudLoginSuccess({
    required bool signup,
    bool promptPicker = true,
  }) async {
    final ok = await _cloudHostedUiLogin(signup: signup);
    if (!mounted) return;
    if (!ok) {
      _showSnack(signup ? 'Kayıt başarısız' : 'Cloud girişi başarısız');
      return;
    }
    final count = await _syncCloudDevices(
      autoSelectIfNeeded: true,
      showSnack: false,
    );
    if (!mounted) return;
    if ((count ?? 0) > 1 && promptPicker) {
      await _openDevicePicker();
    }
    await _consumePendingCloudInviteAfterAuth();
    await _refreshPendingCloudInvites(force: true);
    _showSnack(
      count == null
          ? (signup ? 'Kayıt başarılı' : 'Cloud girişi başarılı')
          : '$count cihaz cloud hesabından yüklendi',
    );
    // ignore: invalid_use_of_protected_member
    setState(() {});
  }

  Future<void> _tryConnect({bool showSnack = true}) async {
    _poller?.cancel();
    debugPrint(
      '[UI] _tryConnect invoked with baseUrlField="${_urlCtl.text.trim()}" (current api.baseUrl=${api.baseUrl})',
    );
    _allowNetworkAutoPolling();
    final authRoleNow = (state?.authRole ?? '').trim().toUpperCase();
    final cloudRoleNow = (_activeDevice?.cloudRole ?? '').trim().toUpperCase();
    final nonOwnerKnownNow =
        authRoleNow == 'USER' ||
        authRoleNow == 'GUEST' ||
        cloudRoleNow == 'USER' ||
        cloudRoleNow == 'GUEST';
    if (_urlCtl.text.trim().isNotEmpty) {
      var u = _urlCtl.text.trim();
      if (!u.startsWith('http://') && !u.startsWith('https://')) {
        u = 'http://$u';
      }
      final typedHost = Uri.tryParse(u)?.host.trim() ?? '';
      if (_baseHostLooksLikeIpv4(typedHost) && _activeDevice != null) {
        _activeDevice!.lastIp = typedHost;
        u = _normalizedStoredBaseForDevice(_activeDevice!, u);
      }
      if (u != baseUrl) {
        baseUrl = u;
        api.baseUrl = baseUrl;
        _localUnreachableUntil = null;
        _localDnsFailUntil = null;
        debugPrint(
          '[NET] Base URL değişti, unreachable/DNS flag\'leri temizlendi',
        );
        try {
          final p = await SharedPreferences.getInstance();
          await p.setString('baseUrl', baseUrl);
          await _updateActiveDeviceBaseUrl(baseUrl);
        } catch (_) {}
      }
    }
    try {
      final parsed = Uri.tryParse(baseUrl.trim());
      final host = parsed?.host ?? '';
      if (host.endsWith('.local')) {
        debugPrint(
          '[NET] baseUrl host looks like .local -> trying mDNS: $host',
        );
        final ip = await _mdnsResolveHost(host);
        if (ip != null && ip.isNotEmpty) {
          debugPrint('[NET] mDNS resolved $host -> $ip');
          await _updateActiveDeviceLastIp(ip);
          api.baseUrl = 'http://$ip';
        } else {
          debugPrint('[NET] mDNS could not resolve $host; trying lastIp');
          _useFallbackIpIfAny(host);
        }
      }
    } catch (e) {
      debugPrint('[NET] .local resolve/check error: $e');
    }

    HapticFeedback.lightImpact();
    _showSnack(t.t('connecting'));
    await _connectionTick(force: true);

    if (nonOwnerKnownNow && _cloudReady(DateTime.now()) && _cloudMqttReady()) {
      if (!mounted) return;
      // ignore: invalid_use_of_protected_member
      setState(() => connected = true);
      if (showSnack) _showSnack('Cloud bağlantısı aktif (davetli kullanıcı).');
      _startPolling();
      return;
    }

    var reachable = false;
    try {
      reachable = await api.testConnection();
    } catch (e) {
      if (_looksLikeDnsLookupFailure(e) &&
          !_baseHostLooksLikeIpv4(api.baseUrl)) {
        _markLocalDnsFailure();
      } else if (_looksLikeLocalUnreachable(e)) {
        _markLocalUnreachable();
      }
    }
    debugPrint('[NET] testConnection -> $reachable for baseUrl=${api.baseUrl}');
    if (!reachable) {
      final host = Uri.tryParse(api.baseUrl)?.host ?? '';
      final localTargeted = host.endsWith('.local');
      if (!localTargeted) {
        await _maybeSwitchToApBaseUrlIfReachable();
      } else {
        debugPrint(
          '[NET] local target unresolved; prefer cached IP before AP fast-path',
        );
        _useFallbackIpIfAny(host);
      }
      if (api.baseUrl == 'http://192.168.4.1') {
        reachable = await _probeInfoReachable(
          'http://192.168.4.1',
          timeout: const Duration(milliseconds: 1500),
        );
      } else {
        reachable = await api.testConnection();
      }
      debugPrint(
        '[NET] testConnection(after AP) -> $reachable for baseUrl=${api.baseUrl}',
      );
    }

    if (!reachable) {
      final keepViaCloud =
          _cloudReady(DateTime.now()) &&
          _cloudCommandEligibleForActive() &&
          _cloudMqttReady();
      if (!mounted) return;
      // ignore: invalid_use_of_protected_member
      setState(() => connected = keepViaCloud);
      if (showSnack) {
        _showSnack(
          keepViaCloud
              ? 'Local erişim yok, cloud bağlantısı kullanılacak.'
              : t.t('reachable_no'),
        );
      }
      return;
    }

    DeviceState? s = await api.fetchState();
    if (s == null) {
      await _ensurePairTokenForAp(prompt: false);
      s = await api.fetchState();
      final onDeviceApNow =
          (Uri.tryParse(api.baseUrl)?.host ?? '') == '192.168.4.1';
      if (s == null &&
          onDeviceApNow &&
          (api.lastErrCode ?? '').trim().toLowerCase() == 'unauthorized') {
        _handleUnauthorizedHit(
          source: 'try_connect_ap_unauthorized',
          immediateRecovery: true,
        );
        await Future.delayed(const Duration(milliseconds: 350));
        s = await api.fetchState();
      }
    }
    if (s == null) {
      final u = Uri.tryParse(api.baseUrl);
      final onDeviceAp = (u != null && u.host == '192.168.4.1');
      if (onDeviceAp) {
        final auth = api.authHeaders();
        final hasLocalAuth =
            auth.containsKey('Authorization') ||
            ((auth['X-Session-Token'] ?? '').isNotEmpty &&
                (auth['X-Session-Nonce'] ?? '').isNotEmpty);
        if (!hasLocalAuth) {
          _showSnack('Önce Bluetooth ile cihaza bağlanıp soft recovery açın.');
        } else {
          _showSnack(
            'AP yetkilendirme başarısız. BLE ile "Kurtarma AP" açıp tekrar deneyin.',
          );
        }
      } else {
        _showSnack(
          'Yerel erişim yetkisiz. Owner/Invite yetkisi verin veya BLE ile soft recovery açıp AP üzerinden tekrar deneyin.',
        );
      }
    }

    if (!mounted) return;
    if (s != null) {
      // ignore: invalid_use_of_protected_member
      setState(() {
        state = s;
        _syncAutoHumControlsFromState(s!);
        connected = true;
        _lastUpdate = DateTime.now();
      });
      if (showSnack) _showSnack(t.t('reachable_yes'));
      await _maybeShowOtaPrompt(s);
      _startPolling();
    } else {
      // ignore: invalid_use_of_protected_member
      setState(() => connected = false);
      if (showSnack) _showSnack(t.t('reachable_no'));
      _startPolling();
    }
  }

  Future<void> _bootstrapCloudSessionOnStartup() async {
    if (!_cloudLoggedIn()) return;
    try {
      await _refreshCloudFeatures();
      if (_cloudUserEnabledLocal) {
        _startCloudPreferWindow();
        await _syncCloudDevices(autoSelectIfNeeded: true);
      }
      await _maybeAutoResumeOwnerClaimOnStartup();
      await _refreshPendingCloudInvites(force: true);
      // ignore: invalid_use_of_protected_member
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('[CLOUD][BOOT] bootstrap error: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> _maybeAutoResumeOwnerClaimOnStartup() async {
    if (!_cloudLoggedIn()) return;
    if (_cloudStartupClaimInFlight) return;
    final retryAt = _cloudStartupClaimRetryAt;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) return;
    final id6 = (_deviceId6ForMqtt() ?? '').trim();
    if (id6.isEmpty) return;
    final st = state;
    if (st?.ownerExists == true || st?.cloudClaimed == true) return;
    final claimSecret = await _resolveActivePairToken();
    if (claimSecret == null || claimSecret.trim().isEmpty) return;
    final now = DateTime.now();
    if (!_cloudAuthReady(now)) {
      final refreshed = await _cloudRefreshIfNeeded();
      if (!refreshed && !_cloudAuthReady(DateTime.now())) return;
    }
    _cloudStartupClaimInFlight = true;
    try {
      debugPrint('[CLOUD][BOOT] attempting silent owner-claim id6=$id6');
      final ok = await _claimViaCloudWithSecret(
        id6: id6,
        claimSecret: claimSecret,
        allowRecoveryPrompt: false,
      );
      debugPrint('[CLOUD][BOOT] silent owner-claim ok=$ok');
      _cloudStartupClaimRetryAt = ok
          ? null
          : DateTime.now().add(const Duration(seconds: 20));
      if (ok && mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {});
      }
    } finally {
      _cloudStartupClaimInFlight = false;
    }
  }

  bool _transportRecoveryBlocked({
    String reason = '',
    bool includeCooldown = true,
  }) {
    if (_backgroundSuspended) return true;
    if (_transportSessionOwner != null) {
      if (reason.isNotEmpty) {
        debugPrint(
          '[PATH] transport recovery blocked ($reason) session=$_transportSessionOwner',
        );
      }
      return true;
    }
    if (includeCooldown &&
        _transportRecoveryCooldownUntil != null &&
        DateTime.now().isBefore(_transportRecoveryCooldownUntil!)) {
      if (reason.isNotEmpty) {
        final ms = _transportRecoveryCooldownUntil!
            .difference(DateTime.now())
            .inMilliseconds;
        debugPrint(
          '[PATH] transport recovery cooling down ($reason) remainingMs=$ms',
        );
      }
      return true;
    }
    return false;
  }

  bool _shouldKeepConnectedOnNullState() {
    if (_bleControlMode) return true;
    final now = DateTime.now();
    if (_transportSessionOwner != null) return true;
    if (_transportRecoveryCooldownUntil != null &&
        now.isBefore(_transportRecoveryCooldownUntil!)) {
      return true;
    }
    if (_lastUpdate != null &&
        now.difference(_lastUpdate!) < const Duration(seconds: 25)) {
      return true;
    }
    if (_lastLocalOkAt != null &&
        now.difference(_lastLocalOkAt!) < const Duration(seconds: 25)) {
      return true;
    }
    if (_lastApReachableAt != null &&
        now.difference(_lastApReachableAt!) < const Duration(seconds: 20)) {
      return true;
    }
    if (_lastCloudOkAt != null &&
        now.difference(_lastCloudOkAt!) < const Duration(seconds: 30) &&
        _cloudCommandEligibleForActive() &&
        _cloudMqttReady()) {
      return true;
    }
    return false;
  }

  bool _isDirectEspConnectedNow() {
    if (_bleControlMode) return true;
    if (_lastStateFetchSource == 'local' || _lastStateFetchSource == 'ap') {
      return true;
    }
    final now = DateTime.now();
    if (_lastLocalOkAt != null &&
        now.difference(_lastLocalOkAt!) < const Duration(seconds: 20)) {
      return true;
    }
    return false;
  }

  bool _isCloudPathConnectedNow() {
    final now = DateTime.now();
    final cloudRecentOk =
        _lastCloudOkAt != null &&
        now.difference(_lastCloudOkAt!) < const Duration(seconds: 30);
    if (!cloudRecentOk) return false;
    if (!_cloudCommandEligibleForActive()) return false;
    // Cloud can be used for control as long as MQTT path is up.
    return _cloudMqttReady();
  }

  bool _isControlPathConnectedNow() {
    return _isDirectEspConnectedNow() || _isCloudPathConnectedNow();
  }

  void _beginTransportSession(String owner) {
    if (_transportSessionOwner == owner) return;
    _transportSessionOwner = owner;
    _transportRecoveryCooldownUntil = null;
    debugPrint('[PATH] transport session begin owner=$owner');
  }

  void _endTransportSession(
    String owner, {
    Duration cooldown = const Duration(seconds: 15),
  }) {
    if (_transportSessionOwner != owner) return;
    _transportSessionOwner = null;
    _transportRecoveryCooldownUntil = DateTime.now().add(cooldown);
    debugPrint(
      '[PATH] transport session end owner=$owner cooldownMs=${cooldown.inMilliseconds}',
    );
  }

  bool _cloudMqttReady() {
    final s = state;
    if (s != null) {
      if (s.cloudMqttConnected) return true;
      final st = s.cloudMqttState.toUpperCase();
      if (st == 'CONNECTED' || st == 'READY') return true;
      final cloudState = s.cloudState.toUpperCase();
      if (cloudState == 'CONNECTED' && st.isNotEmpty) return true;
    }
    return false;
  }

  bool _cloudReady(DateTime now) {
    final reason = (state?.cloudStateReason ?? '').trim().toLowerCase();
    if (reason == 'no_endpoint') {
      debugPrint('[CLOUD] not ready: no_endpoint');
      return false;
    }
    if (!_cloudEnabledEffective()) {
      debugPrint('[CLOUD] not ready: disabled');
      return false;
    }
    if (!_cloudCommandEligibleForActive()) {
      debugPrint(
        '[CLOUD] not ready: selected device not linked to cloud account',
      );
      return false;
    }
    if (_cloudApiBase.trim().isEmpty) {
      debugPrint('[CLOUD] not ready: api base empty');
      return false;
    }
    if (_deviceId6ForMqtt() == null) {
      debugPrint('[CLOUD] not ready: deviceId6 missing');
      return false;
    }
    if (_cloudFailUntil != null && now.isBefore(_cloudFailUntil!)) {
      debugPrint('[CLOUD] not ready: cooldown active');
      return false;
    }
    if (!_cloudAuthReady(now) &&
        (_cloudRefreshToken == null || _cloudRefreshToken!.isEmpty)) {
      debugPrint('[CLOUD] not ready: auth missing/expired');
      return false;
    }
    return true;
  }

  Future<bool> _cloudCommandPathReadyNow({
    required String id6,
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!_cloudReady(now)) return false;
    if (!force &&
        _cloudCmdPathCheckedId6 == id6 &&
        _cloudCmdPathCheckedAt != null &&
        now.difference(_cloudCmdPathCheckedAt!) < const Duration(seconds: 5) &&
        _cloudCmdPathReadyCached != null) {
      return _cloudCmdPathReadyCached!;
    }

    final refreshed = await _cloudRefreshIfNeeded();
    if (!_cloudAuthReady(now) && !refreshed) {
      _cloudCmdPathCheckedAt = now;
      _cloudCmdPathCheckedId6 = id6;
      _cloudCmdPathReadyCached = false;
      return false;
    }

    DeviceState? cloudState;
    try {
      cloudState = await cloudApi.fetchState(id6, const Duration(seconds: 5));
    } catch (_) {
      cloudState = null;
    }
    final ready = _cloudStateLooksReady(cloudState);
    _cloudCmdPathCheckedAt = DateTime.now();
    _cloudCmdPathCheckedId6 = id6;
    _cloudCmdPathReadyCached = ready;
    if (ready) {
      _markCloudOk();
    } else {
      _markCloudFail();
    }
    debugPrint(
      '[CLOUD][GATE] id6=$id6 ready=$ready '
      'mqtt=${cloudState?.cloudMqttConnected ?? false} '
      'state=${cloudState?.cloudState ?? "-"} '
      'mqttState=${cloudState?.cloudMqttState ?? "-"}',
    );
    return ready;
  }

  bool _cloudReadyForInvite(DateTime now, {String? id6}) {
    if (_cloudApiBase.trim().isEmpty) {
      debugPrint('[CLOUD] not ready(invite): api base empty');
      return false;
    }
    final id6Resolved = id6 ?? _deviceId6ForMqtt();
    if (id6Resolved == null || id6Resolved.isEmpty) {
      debugPrint('[CLOUD] not ready(invite): deviceId6 missing');
      return false;
    }
    if (_cloudFailUntil != null && now.isBefore(_cloudFailUntil!)) {
      debugPrint('[CLOUD] not ready(invite): cooldown active');
      return false;
    }
    if (!_cloudAuthReady(now) &&
        (_cloudRefreshToken == null || _cloudRefreshToken!.isEmpty)) {
      debugPrint('[CLOUD] not ready(invite): auth missing/expired');
      return false;
    }
    return true;
  }

  bool _cloudAuthReady(DateTime now) {
    if (_cloudIdToken == null || _cloudIdToken!.isEmpty) return false;
    if (_cloudTokenExp == null) return true;
    return now.isBefore(_cloudTokenExp!.subtract(const Duration(seconds: 30)));
  }

  DateTime? _parseJwtExp(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    String payload = parts[1];
    payload = payload.replaceAll('-', '+').replaceAll('_', '/');
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    try {
      final bytes = base64.decode(payload);
      final obj = jsonDecode(utf8.decode(bytes));
      if (obj is Map && obj['exp'] is num) {
        final exp = (obj['exp'] as num).toInt();
        return DateTime.fromMillisecondsSinceEpoch(
          exp * 1000,
          isUtc: true,
        ).toLocal();
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _parseJwtPayload(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    String payload = parts[1];
    payload = payload.replaceAll('-', '+').replaceAll('_', '/');
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    try {
      final bytes = base64.decode(payload);
      final obj = jsonDecode(utf8.decode(bytes));
      if (obj is Map<String, dynamic>) return obj;
      if (obj is Map) return Map<String, dynamic>.from(obj);
    } catch (_) {}
    return null;
  }

  bool _cloudTokenMatchesConfig(String jwt) {
    final payload = _parseJwtPayload(jwt);
    if (payload == null) return false;
    final iss = (payload['iss'] ?? '').toString().trim();
    final aud = (payload['aud'] ?? payload['client_id'] ?? '')
        .toString()
        .trim();
    if (iss != kCognitoIssuer) return false;
    if (aud != kCognitoClientId) return false;
    return true;
  }

  String? _parseJwtEmail(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    String payload = parts[1];
    payload = payload.replaceAll('-', '+').replaceAll('_', '/');
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    try {
      final bytes = base64.decode(payload);
      final obj = jsonDecode(utf8.decode(bytes));
      if (obj is Map && obj['email'] is String) {
        return obj['email'] as String;
      }
    } catch (_) {}
    return null;
  }

  String _cloudRedirectUri() {
    if (Platform.isIOS) return kCognitoRedirectUriIos;
    return kCognitoRedirectUriAndroid;
  }

  List<String> _cloudRedirectCandidates() {
    final out = <String>[];
    void addIfValid(String raw) {
      final v = raw.trim();
      if (v.isEmpty) return;
      if (!out.contains(v)) out.add(v);
    }

    addIfValid(_cloudRedirectUri());
    if (Platform.isAndroid) {
      addIfValid(kCognitoRedirectUriAndroidLegacy);
    }
    return out;
  }

  String _cloudCognitoBaseUrl() {
    var s = kCognitoHostedDomain.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  void _logCloudIdToken(String source) {
    if (!kDebugMode || !kLogCloudTokens) return;
    final token = _cloudIdToken;
    if (token == null || token.isEmpty) {
      debugPrint('[CLOUD][AUTH] $source idToken=<empty>');
    } else {
      final tokenBytes = utf8.encode(token);
      final fp = sha256.convert(tokenBytes).toString().substring(0, 12);
      debugPrint(
        '[CLOUD][AUTH] $source idToken=<redacted> len=${token.length} sha256:$fp',
      );
    }
  }

  Future<void> _saveCloudAuth() async {
    if (_cloudIdToken != null) {
      await _secureStorage.write(key: 'cloud_id_token', value: _cloudIdToken);
    } else {
      await _secureStorage.delete(key: 'cloud_id_token');
    }
    if (_cloudRefreshToken != null) {
      await _secureStorage.write(
        key: 'cloud_refresh_token',
        value: _cloudRefreshToken,
      );
    } else {
      await _secureStorage.delete(key: 'cloud_refresh_token');
    }
    if (_cloudUserEmail != null) {
      await _secureStorage.write(
        key: 'cloud_user_email',
        value: _cloudUserEmail,
      );
    } else {
      await _secureStorage.delete(key: 'cloud_user_email');
    }
    if (_cloudTokenExp != null) {
      await _secureStorage.write(
        key: 'cloud_token_exp',
        value: _cloudTokenExp!.millisecondsSinceEpoch.toString(),
      );
    } else {
      await _secureStorage.delete(key: 'cloud_token_exp');
    }
    cloudApi.bearerToken = _cloudIdToken;
  }

  Future<void> _loadCloudAuth() async {
    _cloudIdToken = await _secureStorage.read(key: 'cloud_id_token');
    _cloudRefreshToken = await _secureStorage.read(key: 'cloud_refresh_token');
    _cloudUserEmail = await _secureStorage.read(key: 'cloud_user_email');
    final expStr = await _secureStorage.read(key: 'cloud_token_exp');
    if (expStr != null) {
      final ms = int.tryParse(expStr);
      if (ms != null) {
        _cloudTokenExp = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    if (_cloudIdToken != null &&
        _cloudIdToken!.isNotEmpty &&
        !_cloudTokenMatchesConfig(_cloudIdToken!)) {
      debugPrint(
        '[CLOUD][AUTH] stored token issuer/client mismatch -> clearing stale auth',
      );
      _cloudIdToken = null;
      _cloudRefreshToken = null;
      _cloudUserEmail = null;
      _cloudTokenExp = null;
      await _saveCloudAuth();
    }
    cloudApi.bearerToken = _cloudIdToken;
    _logCloudIdToken('load');
  }

  bool _isCloudInvitePayload(Map<String, dynamic> inviteObj) {
    final cloudPartRaw = inviteObj['cloudInvite'];
    final cloudPart = (cloudPartRaw is Map)
        ? Map<String, dynamic>.from(cloudPartRaw)
        : inviteObj;
    final src = cloudPart['source'] ?? cloudPart['cloud'];
    final inviteInner = cloudPart['invite'];
    final innerSrc = (inviteInner is Map)
        ? (inviteInner['source'] ?? inviteInner['cloud'])
        : null;
    return src == 'cloud' ||
        src == true ||
        (cloudPart['t'] ?? '').toString() == 'device_invite' ||
        innerSrc == 'cloud' ||
        innerSrc == true;
  }

  Future<void> _cachePendingCloudInvite(String inviteText) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPendingCloudInviteTextKey, inviteText);
  }

  Future<String?> _loadPendingCloudInvite() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kPendingCloudInviteTextKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  Future<void> _clearPendingCloudInvite() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPendingCloudInviteTextKey);
  }

  Future<void> _consumePendingCloudInviteAfterAuth() async {
    if (!_cloudLoggedIn()) return;
    final inviteText = await _loadPendingCloudInvite();
    if (inviteText == null || inviteText.isEmpty) return;
    await _clearPendingCloudInvite();
    final ok = await _submitInvitePayloadFromText(
      inviteText,
      allowLoginRedirect: false,
    );
    if (ok) {
      _showSnack('Paylaşılan cihaz hesabınıza eklendi.');
    }
  }

  Future<bool> _cloudHostedUiLoginCore({required bool signup}) async {
    final redirectCandidates = _cloudRedirectCandidates();
    final cognitoBase = _cloudCognitoBaseUrl();
    if (redirectCandidates.isEmpty || cognitoBase.isEmpty) return false;
    final serviceConfig = AuthorizationServiceConfiguration(
      authorizationEndpoint: '$cognitoBase/oauth2/authorize',
      tokenEndpoint: '$cognitoBase/oauth2/token',
    );
    for (final redirectUrl in redirectCandidates) {
      try {
        final result = await _appAuth.authorizeAndExchangeCode(
          AuthorizationTokenRequest(
            kCognitoClientId,
            redirectUrl,
            serviceConfiguration: serviceConfig,
            scopes: const ['openid', 'email', 'profile'],
            promptValues: signup ? null : const ['login'],
            additionalParameters: signup
                ? const {'screen_hint': 'signup'}
                : null,
          ),
        );
        final idToken = result.idToken;
        if (idToken == null || idToken.isEmpty) continue;
        _cloudIdToken = idToken;
        _cloudRefreshToken = result.refreshToken ?? _cloudRefreshToken;
        _cloudTokenExp = _parseJwtExp(idToken);
        _cloudUserEmail = _parseJwtEmail(idToken) ?? _cloudUserEmail;
        await _saveCloudAuth();
        final me = await cloudApi.fetchMe(const Duration(seconds: 8));
        if (me != null &&
            (me['email'] is String) &&
            (me['email'] as String).isNotEmpty) {
          _cloudUserEmail = (me['email'] as String).trim();
          await _saveCloudAuth();
        }
        _applyCloudFeaturesFromMe(me);
        _logCloudIdToken('hosted_ui');
        return _cloudLoggedIn();
      } catch (e, st) {
        debugPrint('[CLOUD][AUTH] hosted ui error (redirect=$redirectUrl): $e');
        debugPrint(st.toString());
      }
    }
    return false;
  }

  Future<bool> _cloudHostedUiLogin({required bool signup}) async {
    if (!mounted) return false;
    final title = signup
        ? 'Cloud kayıt ekranı açılıyor...'
        : 'Cloud giriş ekranı açılıyor...';
    final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AsyncLaunchPage(
          title: title,
          task: () => _cloudHostedUiLoginCore(signup: signup),
        ),
      ),
    );
    return ok ?? false;
  }

  Uri _cloudCognitoIdpUri() =>
      Uri.parse('https://cognito-idp.$kCognitoRegion.amazonaws.com/');

  Future<Map<String, dynamic>?> _cognitoIdpAction(
    String target,
    Map<String, dynamic> body,
  ) async {
    try {
      final r = await http
          .post(
            _cloudCognitoIdpUri(),
            headers: <String, String>{
              'Content-Type': 'application/x-amz-json-1.1',
              'X-Amz-Target': 'AWSCognitoIdentityProviderService.$target',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
      final text = r.body.trim();
      final decoded = text.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(text) as Map);
      decoded['_httpStatus'] = r.statusCode;
      return decoded;
    } catch (e) {
      debugPrint('[COGNITO][$target] $e');
      return null;
    }
  }

  String _cognitoErrorText(Map<String, dynamic>? out) {
    if (out == null) return 'network_error';
    return (out['__type'] ?? out['message'] ?? out['Message'] ?? '')
        .toString()
        .trim();
  }

  bool _cognitoErrorMatches(Map<String, dynamic>? out, List<String> needles) {
    final err = _cognitoErrorText(out).toLowerCase();
    for (final needle in needles) {
      if (err.contains(needle.toLowerCase())) return true;
    }
    return false;
  }

  Future<bool> _cognitoResendConfirmationCode(String email) async {
    final out = await _cognitoIdpAction('ResendConfirmationCode', {
      'ClientId': kCognitoClientId,
      'Username': email.trim(),
    });
    if (out == null) return false;
    final status = (out['_httpStatus'] as int?) ?? 0;
    if (_cognitoErrorMatches(out, ['already confirmed', 'not authorized'])) {
      return true;
    }
    return status >= 200 && status < 300;
  }

  Future<bool> _cognitoConfirmSignUp({
    required String email,
    required String code,
  }) async {
    final out = await _cognitoIdpAction('ConfirmSignUp', {
      'ClientId': kCognitoClientId,
      'Username': email.trim(),
      'ConfirmationCode': code.trim(),
      'ForceAliasCreation': true,
    });
    if (out == null) return false;
    final status = (out['_httpStatus'] as int?) ?? 0;
    if (_cognitoErrorMatches(out, ['already confirmed'])) {
      return true;
    }
    return status >= 200 && status < 300;
  }

  Future<bool> _cognitoForgotPassword(String email) async {
    final out = await _cognitoIdpAction('ForgotPassword', {
      'ClientId': kCognitoClientId,
      'Username': email.trim(),
    });
    if (out == null) return false;
    final status = (out['_httpStatus'] as int?) ?? 0;
    return status >= 200 && status < 300;
  }

  Future<void> _openCloudConfirmDialog() async {
    if (!mounted) return;
    await _settleRouteTransition();
    if (!mounted) return;
    final input = await Navigator.of(context, rootNavigator: true)
        .push<_CloudConfirmInput>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) =>
                _CloudConfirmPage(initialEmail: _cloudUserEmail ?? ''),
          ),
        );
    if (input == null) return;
    final action = input.action;
    final email = input.email;
    final code = input.code;
    if (!_looksLikeEmail(email)) {
      _showSnack('Geçerli bir e-posta girin');
      return;
    }
    if (action == 'resend') {
      final ok = await _cognitoResendConfirmationCode(email);
      _showSnack(
        ok
            ? 'Doğrulama kodu yeniden gönderildi.'
            : 'Kod yeniden gönderilemedi.',
      );
      return;
    }
    if (code.isEmpty) {
      _showSnack('Doğrulama kodunu girin');
      return;
    }
    final ok = await _cognitoConfirmSignUp(email: email, code: code);
    if (ok) {
      final loggedIn = await _cloudHostedUiLogin(signup: false);
      if (loggedIn) {
        await _syncCloudDevices(autoSelectIfNeeded: true, showSnack: false);
      }
    }
    _showSnack(ok ? 'Hesap doğrulandı.' : 'Doğrulama başarısız.');
  }

  Future<void> _startCloudForgotPasswordFlow() async {
    if (!mounted) return;
    await _settleRouteTransition();
    if (!mounted) return;
    final email = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CloudEmailPage(
          title: 'Şifre sıfırlama',
          initialEmail: _cloudUserEmail ?? '',
          submitLabel: 'Kod gönder',
        ),
      ),
    );
    if (email == null || email.trim().isEmpty) return;
    if (!_looksLikeEmail(email)) {
      _showSnack('Geçerli bir e-posta girin');
      return;
    }
    final ok = await _cognitoForgotPassword(email);
    _showSnack(
      ok
          ? 'Şifre sıfırlama kodu gönderildi.'
          : 'Şifre sıfırlama kodu gönderilemedi.',
    );
  }

  Future<void> _refreshPendingCloudInvites({bool force = false}) async {
    final now = DateTime.now();
    if (!_cloudLoggedIn()) return;
    if (_cloudPendingInvitesLoading) return;
    if (!force &&
        _cloudPendingInvitesFetchedAt != null &&
        now.difference(_cloudPendingInvitesFetchedAt!) <
            const Duration(seconds: 15)) {
      return;
    }

    if (mounted) {
      // ignore: invalid_use_of_protected_member
      setState(() {
        _cloudPendingInvitesLoading = true;
        _cloudPendingInvitesErr = null;
      });
    } else {
      _cloudPendingInvitesLoading = true;
      _cloudPendingInvitesErr = null;
    }

    try {
      final refreshed = await _cloudRefreshIfNeeded();
      if (!_cloudAuthReady(now) && !refreshed) {
        if (mounted) {
          // ignore: invalid_use_of_protected_member
          setState(() {
            _cloudPendingInvitesLoading = false;
            _cloudPendingInvitesErr = 'cloud_auth_required';
          });
        } else {
          _cloudPendingInvitesLoading = false;
          _cloudPendingInvitesErr = 'cloud_auth_required';
        }
        return;
      }

      final invites = await cloudApi.listMyInvites(const Duration(seconds: 8));
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _cloudPendingInvites = invites;
          _cloudPendingInvitesFetchedAt = DateTime.now();
          _cloudPendingInvitesLoading = false;
          _cloudPendingInvitesErr = invites == null
              ? 'cloud_pending_invites_failed'
              : null;
        });
      } else {
        _cloudPendingInvites = invites;
        _cloudPendingInvitesFetchedAt = DateTime.now();
        _cloudPendingInvitesLoading = false;
        _cloudPendingInvitesErr = invites == null
            ? 'cloud_pending_invites_failed'
            : null;
      }
    } catch (e) {
      debugPrint('[CLOUD][PENDING_INVITES] refresh error: $e');
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _cloudPendingInvitesLoading = false;
          _cloudPendingInvitesErr = 'cloud_pending_invites_failed';
        });
      } else {
        _cloudPendingInvitesLoading = false;
        _cloudPendingInvitesErr = 'cloud_pending_invites_failed';
      }
    }
  }

  Future<void> _acceptPendingCloudInvite(Map<String, dynamic> invite) async {
    final payload = Map<String, dynamic>.from(invite);
    final ok = await _joinInviteViaCloud(payload);
    if (!ok) return;
    await _refreshPendingCloudInvites(force: true);
    await _syncCloudDevices(autoSelectIfNeeded: true, showSnack: false);
    await _refreshCloudMembers(force: true);
    if (_cloudInvitesSupported()) {
      await _refreshCloudInvites(force: true);
    }
  }

  Future<void> _openPendingCloudInvitesFlow() async {
    if (!_cloudLoggedIn()) {
      final authChoice = await _showCloudAuthChoiceDialog();
      if (authChoice == 'login' || authChoice == 'signup') {
        await _handleCloudLoginSuccess(
          signup: authChoice == 'signup',
          promptPicker: false,
        );
      } else if (authChoice == 'confirm') {
        await _openCloudConfirmDialog();
      } else if (authChoice == 'forgot') {
        await _startCloudForgotPasswordFlow();
      }
      if (!_cloudLoggedIn()) return;
    }
    await _refreshPendingCloudInvites(force: true);
    if (!mounted) return;
    final invites = _cloudPendingInvites ?? const <Map<String, dynamic>>[];
    if (invites.isEmpty) {
      _showSnack('Bu hesap için bekleyen davet yok.');
      return;
    }
    await _settleRouteTransition();
    if (!mounted) return;
    final selectedInviteId = await Navigator.of(context, rootNavigator: true)
        .push<String>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _ChoicePage(
              title: 'Davet ile kullanım',
              description: 'Bu hesaba atanmış bekleyen paylaşımlar',
              options: [
                for (final item in invites)
                  _ChoiceOption(
                    value: (item['inviteId'] ?? '').toString(),
                    title:
                        'Cihaz ${(item['deviceId'] ?? item['id6'] ?? '').toString().trim()}',
                    subtitle:
                        'Rol: ${(item['role'] ?? 'USER').toString().trim().toUpperCase()}',
                    icon: Icons.devices_outlined,
                    emphasized: true,
                  ),
              ],
            ),
          ),
        );
    if (selectedInviteId == null || selectedInviteId.trim().isEmpty) return;
    final selected = invites.firstWhere(
      (item) => (item['inviteId'] ?? '').toString() == selectedInviteId,
      orElse: () => <String, dynamic>{},
    );
    if (selected.isEmpty) return;
    await _acceptPendingCloudInvite(selected);
  }

  Future<void> _refreshCloudIntegrations({bool force = false}) async {
    final now = DateTime.now();
    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return;
    if (!_cloudLoggedIn()) return;
    if (!_cloudReady(now)) return;
    if (_cloudIntegrationsLoading) return;
    if (!force &&
        _cloudIntegrationsFetchedAt != null &&
        now.difference(_cloudIntegrationsFetchedAt!) <
            const Duration(seconds: 15)) {
      return;
    }

    if (mounted) {
      // ignore: invalid_use_of_protected_member
      setState(() {
        _cloudIntegrationsLoading = true;
        _cloudIntegrationsErr = null;
      });
    } else {
      _cloudIntegrationsLoading = true;
      _cloudIntegrationsErr = null;
    }

    try {
      final refreshed = await _cloudRefreshIfNeeded();
      if (!_cloudAuthReady(now) && !refreshed) {
        if (mounted) {
          // ignore: invalid_use_of_protected_member
          setState(() {
            _cloudIntegrationsLoading = false;
            _cloudIntegrationsErr = 'cloud_auth_required';
          });
        } else {
          _cloudIntegrationsLoading = false;
          _cloudIntegrationsErr = 'cloud_auth_required';
        }
        return;
      }

      final integrations = await cloudApi.listIntegrations(
        id6,
        const Duration(seconds: 8),
      );
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _cloudIntegrations = integrations;
          _cloudIntegrationsFetchedAt = DateTime.now();
          _cloudIntegrationsLoading = false;
          _cloudIntegrationsErr = integrations == null
              ? 'cloud_integrations_failed'
              : null;
        });
      } else {
        _cloudIntegrations = integrations;
        _cloudIntegrationsFetchedAt = DateTime.now();
        _cloudIntegrationsLoading = false;
        _cloudIntegrationsErr = integrations == null
            ? 'cloud_integrations_failed'
            : null;
      }
    } catch (e) {
      debugPrint('[CLOUD][INTEGRATIONS] refresh error: $e');
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _cloudIntegrationsLoading = false;
          _cloudIntegrationsErr = 'cloud_integrations_failed';
        });
      } else {
        _cloudIntegrationsLoading = false;
        _cloudIntegrationsErr = 'cloud_integrations_failed';
      }
    }
  }

  Future<void> _cloudRevokeMember(String targetUserSub) async {
    final now = DateTime.now();
    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return;
    if (!_cloudLoggedIn()) return;
    if (!_cloudReady(now)) return;

    try {
      final refreshed = await _cloudRefreshIfNeeded();
      if (!_cloudAuthReady(now) && !refreshed) {
        if (!mounted) return;
        _showSnack('Cloud oturum gerekli');
        return;
      }
      final res = await cloudApi.revokeMember(id6, targetUserSub);
      if (!mounted) return;
      if (res == null) {
        _showSnack('Cloud revoke başarısız');
        return;
      }
      final propagated = (res['propagatedToDevice'] == true);
      _showSnack(
        propagated
            ? 'Yetki kaldırıldı (cihaza da iletildi)'
            : 'Yetki kaldırıldı (cihaza iletilemedi)',
      );
      await _refreshCloudMembers(force: true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Cloud revoke hata: $e');
    }
  }

  List<Map<String, dynamic>> _visibleCloudMembers() {
    final members = _cloudMembers ?? const <Map<String, dynamic>>[];
    return members
        .where((item) {
          final role = (item['role'] ?? '').toString().trim().toUpperCase();
          final status = (item['status'] ?? '').toString().trim().toLowerCase();
          final userSub = (item['userSub'] ?? item['userId'] ?? '')
              .toString()
              .trim();
          if (role == 'OWNER') return false;
          if (userSub.isEmpty) return false;
          if (status.isNotEmpty && status != 'active' && status != 'accepted') {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _visibleCloudInvites() {
    final invites = _cloudInvites ?? const <Map<String, dynamic>>[];
    final nowS = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return invites
        .where((item) {
          final status = (item['status'] ?? '').toString().trim().toLowerCase();
          final expiresAt =
              int.tryParse((item['expiresAt'] ?? '').toString()) ?? 0;
          if (status.isNotEmpty && status != 'pending' && status != 'active') {
            return false;
          }
          if (expiresAt > 0 && expiresAt <= nowS) return false;
          return true;
        })
        .toList(growable: false);
  }

  String _formatInviteRemaining(Object? rawExpiresAt) {
    final expiresAt = int.tryParse((rawExpiresAt ?? '').toString()) ?? 0;
    if (expiresAt <= 0) return 'Süre bilgisi yok';
    final nowS = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final remain = expiresAt - nowS;
    if (remain <= 0) return 'Süresi doldu';
    final min = remain ~/ 60;
    final sec = remain % 60;
    if (min <= 0) return '${sec}s kaldı';
    return '${min}dk ${sec}s kaldı';
  }

  Future<void> _cloudPushAcl() async {
    final now = DateTime.now();
    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return;
    if (!_cloudLoggedIn()) return;
    if (!_cloudReady(now)) return;
    if (!_cloudEnabledEffective()) return;
    if (!_isOwnerRole()) return;
    if (_cloudAclPushLoading) return;

    if (mounted) {
      // ignore: invalid_use_of_protected_member
      setState(() {
        _cloudAclPushLoading = true;
      });
    } else {
      _cloudAclPushLoading = true;
    }

    try {
      final refreshed = await _cloudRefreshIfNeeded();
      if (!_cloudAuthReady(now) && !refreshed) {
        if (!mounted) return;
        _showSnack('Cloud oturum gerekli');
        return;
      }
      final res = await cloudApi.pushAcl(
        id6,
        timeout: const Duration(seconds: 8),
      );
      if (!mounted) return;
      if (res == null) {
        _showSnack('ACL push başarısız');
        return;
      }
      final ok = res['ok'] == true || res['pushed'] == true;
      final version = (res['version'] ?? '').toString().trim();
      final userCount = res['userCount'] ?? res['user_count'] ?? 0;
      final reason = (res['reason'] ?? res['err'] ?? res['error'] ?? '')
          .toString()
          .trim();
      if (ok) {
        _showSnack(
          'ACL push ok'
          '${version.isNotEmpty ? ' · v=$version' : ''}'
          ' · users=$userCount',
        );
      } else {
        _showSnack(
          'ACL push başarısız${reason.isNotEmpty ? ' · $reason' : ''}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('ACL push hata: $e');
    } finally {
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _cloudAclPushLoading = false;
        });
      } else {
        _cloudAclPushLoading = false;
      }
    }
  }

  Future<void> _refreshCloudFeatures() async {
    if (!_cloudLoggedIn()) return;
    try {
      final me = await cloudApi.fetchMe(const Duration(seconds: 8));
      _applyCloudFeaturesFromMe(me);
      // ignore: invalid_use_of_protected_member
      if (mounted) setState(() {});
    } catch (_) {}
  }

  String _cloudRoleKey(String id6) => 'cloudRole_$id6';

  Future<void> _setCloudEnabledLocalForActiveDevice(
    bool enabled, {
    SharedPreferences? prefs,
  }) async {
    _cloudUserEnabledLocal = enabled;
    final active = _activeDevice;
    if (active != null) {
      active.cloudEnabledLocal = enabled;
    }
    await _saveDevicesToPrefs(prefs);
  }

  Future<void> _saveCloudRole(String id6, String role) async {
    final r = role.trim().toUpperCase();
    if (id6.isEmpty || r.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_cloudRoleKey(id6), r);
  }

  Future<String?> _loadCloudRole(String id6) async {
    if (id6.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    final r = p.getString(_cloudRoleKey(id6));
    if (r == null || r.trim().isEmpty) return null;
    return r.trim().toUpperCase();
  }

  Future<void> _cloudLogout() async {
    _cloudIdToken = null;
    _cloudRefreshToken = null;
    _cloudTokenExp = null;
    _cloudUserEmail = null;
    _cloudPreferUntil = null;
    _lastCloudOkAt = null;
    _cloudFailUntil = null;
    _cloudFeatureInvites = null;
    _cloudFeatureOtaJobs = null;
    _cloudFeatureShadowDesired = null;
    _cloudFeatureShadowState = null;
    _cloudFeatureShadowAclSync = null;
    _cloudApiState = null;
    _cloudApiStateReason = null;
    _cloudIotEndpoint = null;
    _cloudApiDeviceCount = null;
    _cloudApiDeviceIds = [];
    _cloudCapabilities = null;
    _cloudCapabilitiesSchema = null;
    _cloudCapabilitiesSource = null;
    _cloudCapabilitiesFetchedAt = null;
    _cloudFeaturesFetchedAt = null;
    _cloudPendingInvites = null;
    _cloudPendingInvitesFetchedAt = null;
    _cloudPendingInvitesLoading = false;
    _cloudPendingInvitesErr = null;
    await _saveCloudAuth();
    _logCloudIdToken('logout');
    // ignore: invalid_use_of_protected_member
    if (mounted) setState(() {});
  }

  bool _isLocalCloudNoEndpoint() {
    final reason = (state?.cloudStateReason ?? '').trim().toLowerCase();
    return reason == 'no_endpoint';
  }

  Future<bool> _cloudClaimAllowed({
    required String source,
    bool refreshLocalState = false,
  }) async {
    if (refreshLocalState) {
      final refreshed =
          await _fetchStateSmart(force: true) ?? await api.fetchState();
      if (refreshed != null) {
        state = refreshed;
        // ignore: invalid_use_of_protected_member
        if (mounted) setState(() {});
      }
    }
    if (_isLocalCloudNoEndpoint()) {
      _cloudSetupTerminalError = 'no_endpoint';
      _cloudSetupStatus =
          'Cloud endpoint ayarlı değil (firmware cloud secret eksik).';
      debugPrint('[CLOUD][CLAIM] skip source=$source reason=no_endpoint');
      // ignore: invalid_use_of_protected_member
      if (mounted) setState(() {});
      return false;
    }
    return true;
  }

  Future<void> _maybeAutoClaimCloud(String id6, DeviceState cloudState) async {
    final now = DateTime.now();
    if (!_cloudEnabledEffective()) return;
    final localReason = (state?.cloudStateReason ?? '').trim().toLowerCase();
    if (localReason == 'no_endpoint') {
      debugPrint('[CLOUD][AUTO] skip claim id6=$id6 localReason=no_endpoint');
      return;
    }
    final reason = cloudState.cloudStateReason.trim().toLowerCase();
    if (reason == 'no_endpoint') {
      debugPrint('[CLOUD][AUTO] skip claim id6=$id6 reason=no_endpoint');
      return;
    }
    final refreshed = await _cloudRefreshIfNeeded();
    if (!_cloudAuthReady(now) && !refreshed) return;
    if (cloudState.ownerExists || cloudState.cloudClaimed) return;
    final localState = await api.fetchState();
    if (localState == null) {
      debugPrint('[CLOUD][AUTO] skip claim id6=$id6 local_state_unavailable');
      return;
    }
    if (localState.ownerExists) return;
    final setupCreds = await _loadBleSetupCredsForId6(id6);
    final setupUser = (setupCreds?['user'] ?? '').trim();
    final setupPass = (setupCreds?['pass'] ?? '').trim();
    if (setupUser.isEmpty || setupPass.isEmpty) {
      debugPrint(
        '[CLOUD][AUTO] skip claim id6=$id6 reason=missing_setup_creds',
      );
      return;
    }
    final prev = state;
    final isOwner =
        (prev != null &&
            _authRoleKnown(prev.authRole) &&
            prev.authRole == 'OWNER') ||
        _ownerPrivD32 != null;
    if (!isOwner) return;
    if (_lastCloudAutoClaimAt != null &&
        now.difference(_lastCloudAutoClaimAt!) < const Duration(seconds: 60)) {
      return;
    }
    _lastCloudAutoClaimAt = now;
    final claimSecret = await _resolveActivePairToken();
    if (claimSecret == null || claimSecret.isEmpty) {
      debugPrint('[CLOUD][AUTO] skip claim id6=$id6 reason=missing_pair_token');
      _cloudSetupTerminalError = 'claim_proof_required';
      _cloudSetupStatus = 'Cloud claim için cihaz doğrulama kodu gerekli.';
      // ignore: invalid_use_of_protected_member
      if (mounted) setState(() {});
      return;
    }
    debugPrint('[CLOUD][AUTO] claim start id6=$id6');
    final ok = await cloudApi.claimDeviceWithAutoSync(
      id6,
      kCloudConnectTimeout,
      claimSecret: claimSecret,
      userIdHash: _cloudUserIdHash(),
      ownerPubKeyB64: _cloudOwnerPubKeyB64(),
      deviceBrand: _activeDevice?.brand,
      deviceSuffix: _activeDevice?.suffix,
    );
    debugPrint('[CLOUD][AUTO] claim result ok=$ok');
    if (ok) {
      cloudState.cloudClaimed = true;
      await _syncCloudDevices(
        autoSelectIfNeeded: false,
        showSnack: false,
        force: true,
      );
      await _refreshOwnerFromCloud();
      await _refreshCloudMembers(force: true);
      if (_cloudInvitesSupported()) {
        await _refreshCloudInvites(force: true);
      }
      _markCloudOk();
      _startCloudPreferWindow();
      await _maybeFinalizeLocalOwnerAfterCloudClaim(
        id6: id6,
        setupUser: setupUser,
        setupPass: setupPass,
        source: 'auto_claim',
      );
    }
  }

  Future<void> _maybeFinalizeLocalOwnerAfterCloudClaim({
    required String id6,
    required String setupUser,
    required String setupPass,
    required String source,
  }) async {
    if (_localOwnerFinalizeInFlight) return;
    final now = DateTime.now();
    if (_lastLocalOwnerFinalizeAt != null &&
        now.difference(_lastLocalOwnerFinalizeAt!) <
            const Duration(seconds: 30)) {
      return;
    }
    final localState = await api.fetchState();
    if (localState == null || localState.ownerExists) return;
    _localOwnerFinalizeInFlight = true;
    _lastLocalOwnerFinalizeAt = now;
    try {
      final ok = await _finalizeOwnerClaimAfterQr(
        id6: id6,
        setupUser: setupUser,
        setupPass: setupPass,
      );
      debugPrint('[OWNER][FINALIZE] source=$source ok=$ok');
      if (ok) {
        _cloudOwnerExistsOverride = true;
        if (state != null) {
          state!.ownerExists = true;
          state!.ownerSetupDone = true;
        }
        // ignore: invalid_use_of_protected_member
        if (mounted) setState(() {});
      }
    } finally {
      _localOwnerFinalizeInFlight = false;
    }
  }

  void _markCloudOk() {
    _lastCloudOkAt = DateTime.now();
    _cloudFailUntil = null;
    _cacheActiveRuntimeHealth(cloudOk: true);
  }

  void _markCloudFail() {
    _cloudFailUntil = DateTime.now().add(kCloudCooldown);
    _cacheActiveRuntimeHealth();
  }

  void _startCloudPreferWindow() {
    _cloudPreferUntil = DateTime.now().add(kCloudPreferWindow);
  }

  _SavedDevice? _findDeviceByCanonical(String rawId) {
    final canonical = canonicalizeDeviceId(rawId);
    if (canonical == null || canonical.isEmpty) return null;
    for (final d in _devices) {
      if (canonicalizeDeviceId(d.id) == canonical) return d;
    }
    return null;
  }

  String _preferredDisplayBaseUrlForDevice(_SavedDevice dev) {
    final canonical = canonicalizeDeviceId(dev.id);
    final rawBase = dev.baseUrl.trim();
    final normalized = rawBase.isEmpty
        ? (canonical != null ? _defaultBaseUrlForCloudDevice(canonical) : '')
        : rawBase;
    if (canonical != null && canonical.isNotEmpty) {
      String? mdnsHost = dev.mdnsHost?.trim();
      final storedThing = dev.thingName?.trim() ?? '';
      if ((mdnsHost == null || mdnsHost.isEmpty) && storedThing.isNotEmpty) {
        final lowered = storedThing.toLowerCase();
        if (lowered.endsWith('.local')) {
          mdnsHost = storedThing.substring(0, storedThing.length - 6);
        } else if (RegExp(r'^[a-z0-9-]+-[0-9]{6}$').hasMatch(lowered)) {
          mdnsHost = storedThing;
        }
      }
      mdnsHost ??= mdnsHostFromAny(canonical);
      if (mdnsHost != null && mdnsHost.isNotEmpty) {
        final uri = Uri.tryParse(_normalizeBaseUrl(normalized) ?? normalized);
        final scheme = ((uri?.scheme ?? 'http').isEmpty)
            ? 'http'
            : (uri?.scheme ?? 'http');
        final portNum = uri?.port;
        final hasCustomPort =
            portNum != null && portNum != 0 && portNum != 80 && portNum != 443;
        final port = hasCustomPort ? ':$portNum' : '';
        return '$scheme://$mdnsHost.local$port';
      }
    }
    return _preferredStableLocalBaseUrl(normalized);
  }

  String _normalizedStoredBaseForDevice(_SavedDevice dev, [String? rawBase]) {
    final candidateRaw = (rawBase ?? dev.baseUrl).trim();
    final normalizedRaw =
        _normalizeBaseUrl(candidateRaw) ??
        (candidateRaw.isEmpty ? 'http://192.168.4.1' : candidateRaw);
    if (normalizedRaw == 'http://192.168.4.1') return normalizedRaw;
    final canonical = canonicalizeDeviceId(dev.id);
    if (canonical == null ||
        canonical.isEmpty ||
        _isPlaceholderDeviceId(dev.id)) {
      return _preferredStableLocalBaseUrl(normalizedRaw);
    }
    final temp = _SavedDevice(
      id: canonical,
      brand: dev.brand.trim().isNotEmpty ? dev.brand : kDefaultDeviceBrand,
      suffix: dev.suffix,
      baseUrl: normalizedRaw,
      lastIp: dev.lastIp,
      thingName: dev.thingName ?? thingNameFromAny(canonical),
      mdnsHost: dev.mdnsHost ?? mdnsHostFromAny(canonical),
      pairToken: dev.pairToken,
      cloudLinked: dev.cloudLinked,
      cloudEnabledLocal: dev.cloudEnabledLocal,
      cloudRole: dev.cloudRole,
      cloudSource: dev.cloudSource,
      doaWaterDurationMin: dev.doaWaterDurationMin,
      doaWaterIntervalHr: dev.doaWaterIntervalHr,
      doaWaterAutoEnabled: dev.doaWaterAutoEnabled,
    );
    return _preferredDisplayBaseUrlForDevice(temp);
  }

  void _normalizeSavedDeviceInventory() {
    for (final dev in _devices) {
      if (dev.brand.trim().isEmpty) {
        dev.brand = kDefaultDeviceBrand;
      }
      final resolvedBrand = resolveDeviceBrand(
        firmwareProduct: deviceProductSlugFromAny(dev.id),
        bleName: '',
        baseUrl: dev.baseUrl,
        mdnsHost: dev.mdnsHost ?? '',
        apSsid: '',
        currentBrand: dev.brand,
      ).brand.trim();
      if (resolvedBrand.isNotEmpty && resolvedBrand != dev.brand) {
        debugPrint(
          '[BRAND] inventory auto-correct ${dev.id}: ${dev.brand} -> $resolvedBrand',
        );
        dev.brand = resolvedBrand;
      }
      final canonical = canonicalizeDeviceId(dev.id);
      if (canonical != null && canonical.isNotEmpty) {
        dev.thingName ??= thingNameFromAny(canonical);
        dev.mdnsHost ??= mdnsHostFromAny(canonical);
      }
      dev.baseUrl = _normalizedStoredBaseForDevice(dev);
    }
    _dedupeSavedDevicesByCanonical();
  }

  void _dedupeSavedDevicesByCanonical() {
    if (_devices.length < 2) return;
    final seen = <String, _SavedDevice>{};
    final deduped = <_SavedDevice>[];
    var activeChanged = false;
    for (final dev in _devices) {
      final canonical = canonicalizeDeviceId(dev.id);
      if (canonical == null || canonical.isEmpty) {
        deduped.add(dev);
        continue;
      }
      final existing = seen[canonical];
      if (existing == null) {
        dev.baseUrl = _preferredDisplayBaseUrlForDevice(dev);
        seen[canonical] = dev;
        deduped.add(dev);
        continue;
      }
      _mergeSavedDeviceInto(
        target: existing,
        source: dev,
        canonicalId: canonical,
      );
      _moveRuntimeContext(dev.id, existing.id);
      existing.baseUrl = _preferredDisplayBaseUrlForDevice(existing);
      if (_activeDeviceId == dev.id && _activeDeviceId != existing.id) {
        _activeDeviceId = existing.id;
        activeChanged = true;
      }
    }
    if (activeChanged || deduped.length != _devices.length) {
      _devices = deduped;
    }
  }

  String? _runtimeKeyForDeviceId(String? rawId) {
    final canonical = canonicalizeDeviceId(rawId ?? '');
    if (canonical == null || canonical.isEmpty) return null;
    return canonical;
  }

  void _captureRuntimeForDevice(String? rawId) {
    final key = _runtimeKeyForDeviceId(rawId);
    if (key == null) return;
    final ctx = _deviceRuntime.putIfAbsent(key, () => _DeviceRuntimeContext());
    ctx.apSessionToken = _apSessionToken;
    ctx.apSessionNonce = _apSessionNonce;
    ctx.lastLocalOkAt = _lastLocalOkAt;
    ctx.localDnsFailUntil = _localDnsFailUntil;
    ctx.localUnreachableUntil = _localUnreachableUntil;
    ctx.lastCloudOkAt = _lastCloudOkAt;
    ctx.cloudFailUntil = _cloudFailUntil;
    ctx.cloudPreferUntil = _cloudPreferUntil;
    ctx.cloudOwnerExistsOverride = _cloudOwnerExistsOverride;
    ctx.cloudOwnerSetupDoneOverride = _cloudOwnerSetupDoneOverride;
  }

  void _restoreRuntimeForDevice(String? rawId) {
    final key = _runtimeKeyForDeviceId(rawId);
    final ctx = key != null ? _deviceRuntime[key] : null;
    _apSessionToken = ctx?.apSessionToken;
    _apSessionNonce = ctx?.apSessionNonce;
    _lastLocalOkAt = ctx?.lastLocalOkAt;
    _localDnsFailUntil = ctx?.localDnsFailUntil;
    _localUnreachableUntil = ctx?.localUnreachableUntil;
    _lastCloudOkAt = ctx?.lastCloudOkAt;
    _cloudFailUntil = ctx?.cloudFailUntil;
    _cloudPreferUntil = ctx?.cloudPreferUntil;
    _cloudOwnerExistsOverride = ctx?.cloudOwnerExistsOverride;
    _cloudOwnerSetupDoneOverride = ctx?.cloudOwnerSetupDoneOverride;
    connected = ctx?.lastConnected ?? false;
  }

  void _cacheActiveRuntimeHealth({bool localOk = false, bool cloudOk = false}) {
    final key = _runtimeKeyForDeviceId(_activeDeviceId);
    if (key == null) return;
    final ctx = _deviceRuntime.putIfAbsent(key, () => _DeviceRuntimeContext());
    ctx.apSessionToken = _apSessionToken;
    ctx.apSessionNonce = _apSessionNonce;
    ctx.lastLocalOkAt = _lastLocalOkAt;
    ctx.localDnsFailUntil = _localDnsFailUntil;
    ctx.localUnreachableUntil = _localUnreachableUntil;
    ctx.lastCloudOkAt = _lastCloudOkAt;
    ctx.cloudFailUntil = _cloudFailUntil;
    ctx.cloudPreferUntil = _cloudPreferUntil;
    ctx.cloudOwnerExistsOverride = _cloudOwnerExistsOverride;
    ctx.cloudOwnerSetupDoneOverride = _cloudOwnerSetupDoneOverride;
    ctx.lastConnected = connected;
    if (localOk || cloudOk) {
      ctx.lastSeenAt = DateTime.now();
    }
  }

  void _moveRuntimeContext(String? fromRawId, String? toRawId) {
    final fromKey = _runtimeKeyForDeviceId(fromRawId);
    final toKey = _runtimeKeyForDeviceId(toRawId);
    if (fromKey == null || toKey == null || fromKey == toKey) return;
    final existing = _deviceRuntime.remove(fromKey);
    if (existing == null) return;
    final target = _deviceRuntime[toKey];
    if (target == null) {
      _deviceRuntime[toKey] = existing;
      return;
    }
    target.apSessionToken ??= existing.apSessionToken;
    target.apSessionNonce ??= existing.apSessionNonce;
    target.lastLocalOkAt ??= existing.lastLocalOkAt;
    target.localDnsFailUntil ??= existing.localDnsFailUntil;
    target.localUnreachableUntil ??= existing.localUnreachableUntil;
    target.lastCloudOkAt ??= existing.lastCloudOkAt;
    target.cloudFailUntil ??= existing.cloudFailUntil;
    target.cloudPreferUntil ??= existing.cloudPreferUntil;
    target.cloudOwnerExistsOverride ??= existing.cloudOwnerExistsOverride;
    target.cloudOwnerSetupDoneOverride ??= existing.cloudOwnerSetupDoneOverride;
  }

  bool _isPlaceholderDeviceId(String? rawId) {
    final trimmed = rawId?.trim() ?? '';
    return trimmed.startsWith('dev_');
  }

  _SavedDevice? _findPlaceholderDeviceForCanonical({
    required String canonicalId,
    String? preferredId,
    String? brandHint,
    String? suffixHint,
  }) {
    if (_isPlaceholderDeviceId(preferredId)) {
      final exact = _firstWhereOrNull<_SavedDevice>(
        _devices,
        (d) => d.id == preferredId,
      );
      if (exact != null) return exact;
    }

    final normalizedBrand = (brandHint ?? '').trim().toLowerCase();
    final normalizedSuffix = (suffixHint ?? '').trim().toLowerCase();
    if (normalizedBrand.isNotEmpty) {
      final matchedPresentation = _firstWhereOrNull<_SavedDevice>(
        _devices,
        (d) =>
            _isPlaceholderDeviceId(d.id) &&
            d.brand.trim().toLowerCase() == normalizedBrand &&
            d.suffix.trim().toLowerCase() == normalizedSuffix,
      );
      if (matchedPresentation != null) return matchedPresentation;
    }

    return null;
  }

  void _mergeSavedDeviceInto({
    required _SavedDevice target,
    required _SavedDevice source,
    String? canonicalId,
  }) {
    final targetCanonical = canonicalizeDeviceId(target.id);
    final sourceCanonical = canonicalizeDeviceId(source.id);
    final sameCanonicalDevice =
        targetCanonical != null &&
        sourceCanonical != null &&
        targetCanonical == sourceCanonical;
    if ((target.brand.trim().isEmpty || isDefaultDeviceBrand(target.brand)) &&
        source.brand.trim().isNotEmpty) {
      target.brand = source.brand;
    }
    if (target.suffix.trim().isEmpty && source.suffix.trim().isNotEmpty) {
      target.suffix = source.suffix;
    }
    if ((target.baseUrl.trim().isEmpty ||
            target.baseUrl.trim() == 'http://192.168.4.1') &&
        source.baseUrl.trim().isNotEmpty) {
      target.baseUrl = source.baseUrl;
    }
    target.lastIp ??= source.lastIp;
    target.thingName ??= source.thingName;
    target.mdnsHost ??= source.mdnsHost;
    target.thingName ??= canonicalId != null
        ? thingNameFromAny(canonicalId)
        : null;
    target.mdnsHost ??= canonicalId != null
        ? mdnsHostFromAny(canonicalId)
        : null;
    if (sameCanonicalDevice &&
        (target.pairToken == null || target.pairToken!.isEmpty) &&
        source.pairToken != null &&
        source.pairToken!.isNotEmpty) {
      target.pairToken = source.pairToken;
    }
    target.cloudEnabledLocal =
        target.cloudEnabledLocal || source.cloudEnabledLocal;
    target.cloudLinked = target.cloudLinked || source.cloudLinked;
    target.cloudRole ??= source.cloudRole;
    target.cloudSource ??= source.cloudSource;
    target.waqiName ??= source.waqiName;
    target.waqiLat ??= source.waqiLat;
    target.waqiLon ??= source.waqiLon;
    target.waqiCityName ??= source.waqiCityName;
    target.waqiAqi ??= source.waqiAqi;
    target.waqiPm25 ??= source.waqiPm25;
    target.waqiTempC ??= source.waqiTempC;
    target.waqiHumPct ??= source.waqiHumPct;
    target.waqiWindKph ??= source.waqiWindKph;
    target.waqiUpdatedAtMs ??= source.waqiUpdatedAtMs;
    target.doaWaterDurationMin ??= source.doaWaterDurationMin;
    target.doaWaterIntervalHr ??= source.doaWaterIntervalHr;
    target.doaWaterAutoEnabled ??= source.doaWaterAutoEnabled;
  }

  _SavedDevice? _promotePlaceholderDeviceToCanonical({
    required String canonicalId,
    String? preferredPlaceholderId,
    String? brandHint,
    String? suffixHint,
    String? baseUrlHint,
  }) {
    final existingCanonical = _findDeviceByCanonical(canonicalId);
    final placeholder = _findPlaceholderDeviceForCanonical(
      canonicalId: canonicalId,
      preferredId: preferredPlaceholderId,
      brandHint: brandHint,
      suffixHint: suffixHint,
    );
    if (placeholder == null) return existingCanonical;

    if (existingCanonical != null &&
        !identical(existingCanonical, placeholder)) {
      _mergeSavedDeviceInto(
        target: existingCanonical,
        source: placeholder,
        canonicalId: canonicalId,
      );
      _devices.removeWhere((d) => identical(d, placeholder));
      if (_activeDeviceId == placeholder.id) {
        _activeDeviceId = existingCanonical.id;
      }
      return existingCanonical;
    }

    placeholder.id = canonicalId;
    if ((placeholder.brand.trim().isEmpty ||
            isDefaultDeviceBrand(placeholder.brand)) &&
        (brandHint?.trim().isNotEmpty ?? false)) {
      placeholder.brand = brandHint!.trim();
    }
    if (placeholder.suffix.trim().isEmpty &&
        (suffixHint?.trim().isNotEmpty ?? false)) {
      placeholder.suffix = suffixHint!.trim();
    }
    if ((placeholder.baseUrl.trim().isEmpty ||
            placeholder.baseUrl.trim() == 'http://192.168.4.1') &&
        (baseUrlHint?.trim().isNotEmpty ?? false)) {
      placeholder.baseUrl = _normalizedStoredBaseForDevice(
        placeholder,
        baseUrlHint!.trim(),
      );
    }
    placeholder.thingName ??= thingNameFromAny(canonicalId);
    placeholder.mdnsHost ??= mdnsHostFromAny(canonicalId);
    return placeholder;
  }

  String _defaultBaseUrlForCloudDevice(String canonicalId) {
    final mdnsHost = mdnsHostFromAny(canonicalId);
    if (mdnsHost != null && mdnsHost.isNotEmpty) {
      return 'http://$mdnsHost.local';
    }
    return 'http://192.168.4.1';
  }
}
