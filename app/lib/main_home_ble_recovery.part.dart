part of 'main.dart';

extension _HomeScreenBleRecoveryPart on _HomeScreenState {
  Future<bool> _tryRecoverPairTokenViaBleForAp({required String id6}) async {
    try {
      final hadBleSession = _bleControlMode;
      if (!hadBleSession) {
        await _toggleBleControl(
          interactive: false,
          // Recovery path should not block on setup creds; we only need
          // BLE channel to fetch nonce/pairToken or AP session bootstrap.
          allowUnownedWithoutSetupCreds: true,
        ).timeout(const Duration(seconds: 10));
      }
      if (!_bleControlMode) return false;

      // Prefer AP session bootstrap over BLE so AP HTTP can proceed even when
      // pairToken isn't currently available in app storage.
      await _requestApSessionViaBleBestEffort(ttlSec: 600);
      final hasSession = (_apSessionToken ?? '').trim().isNotEmpty;
      if (hasSession) {
        api.setApSessionToken(_apSessionToken);
        api.setApSessionNonce(_apSessionNonce);
        return true;
      }

      String token = (_bleControlPairToken ?? '').trim();
      if (token.isEmpty) {
        final nonceProbe = Completer<Map<String, dynamic>>();
        _bleNonceMapCompleter = nonceProbe;
        try {
          await _bleSendJson(const {'cmd': 'GET_NONCE'});
          final nonceObj = await nonceProbe.future.timeout(
            const Duration(seconds: 3),
            onTimeout: () => <String, dynamic>{},
          );
          token = (nonceObj['pairToken'] ?? nonceObj['qrToken'] ?? '')
              .toString()
              .trim();
          if (token.isNotEmpty) _bleControlPairToken = token;
        } finally {
          if (_bleNonceMapCompleter == nonceProbe) {
            _bleNonceMapCompleter = null;
          }
        }
      }
      if (token.isEmpty) return false;

      await _applyPairToken(token, deviceListId: id6);
      api.setPairToken(token);
      api.clearLocalSession();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureBluetoothOnWithUi() async {
    final supported = await FlutterBluePlus.isSupported;
    if (!mounted) return false;
    if (supported == false) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.t('ble_not_supported'))));
      return false;
    }
    var st = await safeAdapterState(timeout: const Duration(seconds: 5));
    if (st == BluetoothAdapterState.on ||
        FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
      return true;
    }

    try {
      if (FlutterBluePlus.connectedDevices.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    for (var i = 0; i < 3; i++) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 350));
      st = await safeAdapterState(timeout: const Duration(seconds: 1));
      if (st == BluetoothAdapterState.on ||
          FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
        return true;
      }
    }

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(milliseconds: 500),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await FlutterBluePlus.stopScan();
      return true;
    } catch (_) {}

    final definitelyOff =
        st == BluetoothAdapterState.off &&
        FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off;
    if (definitelyOff) return false;
    return true;
  }

  Future<void> _cleanupBleControlSession() async {
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
        reason: 'cleanup_ble_control_session',
      );
    } catch (_) {}
    _bleCtrlDevice = null;
    _bleCtrlInfoChar = null;
    _bleCtrlCmdChar = null;
    _bleControlMode = false;
    _bleSessionAuthed = false;
    _bleSessionAuthCompleter = null;
  }

  Future<bool> _attemptBleControlConnectOnce({
    required String id6,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_bleControlMode) return true;
    if (_bleCtrlConnecting) return false;
    if (_qrBleConnectInFlight) return false;
    _qrBleConnectInFlight = true;
    try {
      await _setBleTargetId6InPrefs(id6);
      await _ensureActiveDeviceForId6(id6);
      await _toggleBleControl(interactive: false).timeout(timeout);
      return _bleControlMode;
    } catch (_) {
      await _cleanupBleControlSession();
      return false;
    } finally {
      _qrBleConnectInFlight = false;
    }
  }

  Future<bool> _attemptBleControlConnectWithRetries({
    required String id6,
    required int attempts,
  }) async {
    for (var i = 1; i <= attempts; i++) {
      final ok = await _attemptBleControlConnectOnce(id6: id6);
      if (ok) return true;
      await Future.delayed(const Duration(milliseconds: 800));
    }
    return false;
  }

  bool get _localDnsFailActive =>
      _localDnsFailUntil != null &&
      DateTime.now().isBefore(_localDnsFailUntil!);

  bool get _localUnreachableActive =>
      _localUnreachableUntil != null &&
      DateTime.now().isBefore(_localUnreachableUntil!);

  bool _looksLikeDnsLookupFailure(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('failed host lookup') ||
        s.contains('nodename nor servname') ||
        s.contains('errno = 8') ||
        s.contains('no address associated with hostname') ||
        s.contains('name or service not known') ||
        s.contains('temporary failure in name resolution');
  }

  bool _baseHostLooksLikeIpv4(String base) {
    final host = Uri.tryParse(base)?.host ?? '';
    if (host.isEmpty) return false;
    return RegExp(r'^\d+(\.\d+){3}$').hasMatch(host);
  }

  bool _looksLikeLocalUnreachable(Object e) {
    final s = e.toString().toLowerCase();
    final isTimeout =
        s.contains('connection timed out') ||
        s.contains('operation timed out') ||
        s.contains('timeoutexception') ||
        s.contains('errno = 60');
    if (isTimeout &&
        _lastLocalOkAt != null &&
        DateTime.now().difference(_lastLocalOkAt!) <
            const Duration(seconds: 20)) {
      return false;
    }
    return s.contains('host is down') ||
        s.contains('errno = 64') ||
        s.contains('network is unreachable') ||
        s.contains('network is down') ||
        s.contains('connection failed') ||
        s.contains('connection refused') ||
        s.contains('connection timed out') ||
        s.contains('operation timed out') ||
        s.contains('software caused connection abort') ||
        s.contains('timeoutexception') ||
        s.contains('errno = 60') ||
        s.contains('errno = 61') ||
        s.contains('errno = 50') ||
        s.contains('errno = 51');
  }

  void _markLocalDnsFailure([Duration ttl = const Duration(minutes: 10)]) {
    _localDnsFailUntil = DateTime.now().add(ttl);
    _cacheActiveRuntimeHealth();
  }

  void _markLocalUnreachable([Duration ttl = const Duration(seconds: 30)]) {
    final now = DateTime.now();
    if (_lastLocalOkAt != null &&
        now.difference(_lastLocalOkAt!) < const Duration(seconds: 20)) {
      _localUnreachableUntil = now.add(const Duration(seconds: 5));
      _cacheActiveRuntimeHealth();
      return;
    }
    _localUnreachableUntil = now.add(ttl);
    _cacheActiveRuntimeHealth();
  }

  Future<void> _maybeAutoRecoverLocalUnauthorized({
    String trigger = 'unknown',
  }) async {
    final now = DateTime.now();
    if (_localUnauthorizedRecoveryInFlight) return;
    if (_nextLocalUnauthorizedRecoveryAt != null &&
        now.isBefore(_nextLocalUnauthorizedRecoveryAt!)) {
      return;
    }
    if (_transportSessionOwner != null) return;

    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return;
    final authRole = (state?.authRole ?? '').trim().toUpperCase();
    final cloudRole = (_activeDevice?.cloudRole ?? '').trim().toUpperCase();
    final nonOwnerKnown =
        authRole == 'USER' ||
        authRole == 'GUEST' ||
        cloudRole == 'USER' ||
        cloudRole == 'GUEST';
    if (nonOwnerKnown) {
      _nextLocalUnauthorizedRecoveryAt = DateTime.now().add(
        const Duration(seconds: 30),
      );
      debugPrint(
        '[AUTH][AUTO] unauthorized recovery skipped: non-owner role auth=$authRole cloud=$cloudRole',
      );
      return;
    }

    _localUnauthorizedRecoveryInFlight = true;
    try {
      debugPrint(
        '[AUTH][AUTO] unauthorized recovery start trigger=$trigger id6=$id6 hits=$_localUnauthorizedHits',
      );

      await _resolveActivePairToken();

      final opened = await api.ensureOwnerSession();
      if (opened) {
        _localUnauthorizedHits = 0;
        _nextLocalUnauthorizedRecoveryAt = null;
        debugPrint(
          '[AUTH][AUTO] unauthorized recovery fixed via session id6=$id6',
        );
        return;
      }

      final cached = await _loadBleSetupCredsForId6(id6);
      final setupUser = (cached?['user'] ?? '').trim();
      final setupPass = (cached?['pass'] ?? '').trim();
      final recovered = await _tryRecoverPairTokenViaBleForAp(id6: id6);
      if (recovered) {
        final reopened = await api.ensureOwnerSession();
        if (reopened) {
          _localUnauthorizedHits = 0;
          _nextLocalUnauthorizedRecoveryAt = null;
          debugPrint(
            '[AUTH][AUTO] unauthorized recovery fixed via BLE pairToken/session refresh id6=$id6',
          );
          return;
        }
      }

      // Do not auto-claim owner from periodic unauthorized recovery loop.
      // Owner claim should remain an explicit onboarding action.
      if (setupUser.isEmpty || setupPass.isEmpty) {
        _nextLocalUnauthorizedRecoveryAt = DateTime.now().add(
          const Duration(seconds: 20),
        );
        debugPrint(
          '[AUTH][AUTO] unauthorized recovery postponed: BLE refresh failed and setup creds missing id6=$id6',
        );
        return;
      }
      _nextLocalUnauthorizedRecoveryAt = DateTime.now().add(
        const Duration(seconds: 20),
      );
      debugPrint(
        '[AUTH][AUTO] unauthorized recovery postponed: BLE refresh failed id6=$id6',
      );
      return;
    } catch (e) {
      _nextLocalUnauthorizedRecoveryAt = DateTime.now().add(
        const Duration(seconds: 20),
      );
      debugPrint('[AUTH][AUTO] unauthorized recovery error: $e');
    } finally {
      _localUnauthorizedRecoveryInFlight = false;
    }
  }

  void _handleUnauthorizedHit({
    required String source,
    bool immediateRecovery = false,
  }) {
    _localUnauthorizedHits++;
    final apUnauthorizedSource =
        source.contains('ap_fetch_unauthorized') ||
        source.contains('try_connect_ap_unauthorized') ||
        source.contains('AP_HTTP_401');
    final threshold = (immediateRecovery || apUnauthorizedSource) ? 1 : 2;
    if (_localUnauthorizedHits >= threshold) {
      unawaited(_maybeAutoRecoverLocalUnauthorized(trigger: source));
    }
  }

  bool get _backgroundSuspended => _backgroundSuspendCount > 0;

  void _pauseBackground({String reason = ''}) {
    _backgroundSuspendCount++;
    if (_backgroundSuspendCount != 1) return;
    debugPrint('[BG] pause ${reason.isEmpty ? '' : '($reason)'}');
    try {
      _poller?.cancel();
      _poller = null;
    } catch (_) {}
    _pollTickInFlight = false;
  }

  void _resumeBackground({String reason = ''}) {
    if (_backgroundSuspendCount <= 0) return;
    _backgroundSuspendCount--;
    if (_backgroundSuspendCount != 0) return;
    debugPrint('[BG] resume ${reason.isEmpty ? '' : '($reason)'}');
    _startPolling();
  }

  void _dismissBlockingPopupsIfAny({int maxPops = 3}) {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    for (var i = 0; i < maxPops; i++) {
      if (!nav.canPop()) break;
      try {
        nav.pop();
      } catch (_) {
        break;
      }
    }
  }
}
