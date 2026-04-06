part of 'main.dart';

extension _HomeScreenOwnerFinalizePart on _HomeScreenState {
  // AP üstünden owner claim denemesi.
  Future<bool> _tryClaimOwnerOverApImpl({
    required String user,
    required String pass,
  }) async {
    final u = Uri.tryParse(api.baseUrl);
    final onDeviceAp = (u != null && u.host == '192.168.4.1');
    if (!onDeviceAp) return false;
    final st = state;
    if (st != null && st.ownerExists) return true;

    await _ensureOwnerKeypair(generateIfMissing: true);
    final ownerPub = _ownerPubQ65B64;
    if (ownerPub == null || ownerPub.isEmpty) return false;

    debugPrint('[OWNER][AP] CLAIM_REQUEST send');
    await api.sendCommand(<String, dynamic>{
      'type': 'CLAIM_REQUEST',
      'user': user,
      'pass': pass,
      'owner_pubkey': ownerPub,
    });

    final refreshed =
        await _fetchStateSmart(force: true) ?? await api.fetchState();
    final claimed = refreshed?.ownerExists == true;
    if (claimed && mounted) {
      _safeSetState(() {
        state = refreshed;
        connected = true;
        _lastUpdate = DateTime.now();
      });
      api.setSigningKey(_ownerPrivD32 ?? _clientPrivD32);
      api.setApSessionToken(null);
      api.setApSessionNonce(null);
      _showSnack('Owner atandı (AP).');
    }
    return claimed;
  }

  Future<bool> _refreshOwnerStateFromDeviceImpl() async {
    try {
      final refreshed =
          await _fetchStateSmart(force: true) ?? await api.fetchState();
      if (refreshed == null) return state?.ownerExists == true;
      final claimed = refreshed.ownerExists == true;
      if (mounted) {
        _safeSetState(() {
          state = refreshed;
          connected = true;
          _lastUpdate = DateTime.now();
          _syncAutoHumControlsFromState(refreshed);
        });
      } else {
        state = refreshed;
        connected = true;
        _lastUpdate = DateTime.now();
      }
      return claimed;
    } catch (_) {
      return state?.ownerExists == true;
    }
  }

  Future<bool> _isBluetoothReadyForAutoClaimImpl() async {
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (supported == false) return false;
      final st = await safeAdapterState(timeout: const Duration(seconds: 2));
      return st != BluetoothAdapterState.off;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _finalizeOwnerClaimAfterQrImpl({
    required String? id6,
    required String? setupUser,
    required String? setupPass,
  }) async {
    if (await _refreshOwnerStateFromDevice()) return true;

    final normalizedId6 = (id6 ?? '').trim();
    final user = (setupUser ?? '').trim();
    final pass = (setupPass ?? '').trim();
    if (normalizedId6.isEmpty || user.isEmpty || pass.isEmpty) {
      debugPrint(
        '[OWNER][FINALIZE] skipped (missing id/user/pass) '
        'id6=${normalizedId6.isNotEmpty} user=${user.isNotEmpty} pass=${pass.isNotEmpty}',
      );
      return false;
    }

    final claimedViaAp = await _tryClaimOwnerOverAp(user: user, pass: pass);
    if (claimedViaAp) return true;

    final bleReady = await _isBluetoothReadyForAutoClaim();
    if (!bleReady) {
      debugPrint('[OWNER][FINALIZE] BLE not ready for auto-claim');
      return await _refreshOwnerStateFromDevice();
    }

    final bleOk = await _attemptBleControlConnectWithRetries(
      id6: normalizedId6,
      attempts: 2,
    );
    if (bleOk) {
      await _refreshOwnerSigningKey();
    }

    return await _refreshOwnerStateFromDevice();
  }

  Future<bool> _ensureLocalOwnerClaimAfterProvisionImpl({
    String? idHint,
    String? setupUserHint,
    String? setupPassHint,
    String source = 'ble_provision',
  }) async {
    if (await _refreshOwnerStateFromDevice()) {
      return true;
    }

    String? resolvedId6 = _normalizeDeviceId6((idHint ?? '').trim());
    String setupUser = (setupUserHint ?? '').trim();
    String setupPass = (setupPassHint ?? '').trim();

    if (resolvedId6 == null || resolvedId6.isEmpty) {
      resolvedId6 = await _getBleTargetId6FromPrefs();
      resolvedId6 = _normalizeDeviceId6((resolvedId6 ?? '').trim());
    }
    if ((resolvedId6 == null || resolvedId6.isEmpty) &&
        (_deviceId6ForMqtt() ?? '').trim().isNotEmpty) {
      resolvedId6 = _normalizeDeviceId6((_deviceId6ForMqtt() ?? '').trim());
    }

    if ((setupUser.isEmpty || setupPass.isEmpty) &&
        resolvedId6 != null &&
        resolvedId6.isNotEmpty) {
      final cached = await _loadBleSetupCredsForId6(resolvedId6);
      setupUser = (cached?['user'] ?? '').trim();
      setupPass = (cached?['pass'] ?? '').trim();
    }
    if (resolvedId6 == null ||
        resolvedId6.isEmpty ||
        setupUser.isEmpty ||
        setupPass.isEmpty) {
      debugPrint(
        '[OWNER][FINALIZE] skip source=$source reason=missing_claim_inputs '
        'id6=${resolvedId6 != null && resolvedId6.isNotEmpty} '
        'user=${setupUser.isNotEmpty} pass=${setupPass.isNotEmpty}',
      );
      return false;
    }

    _setBlockingProgress(
      title: t.t('please_wait'),
      body: 'Owner doğrulaması tamamlanıyor...',
    );
    try {
      final ok = await _finalizeOwnerClaimAfterQr(
        id6: resolvedId6,
        setupUser: setupUser,
        setupPass: setupPass,
      );
      debugPrint('[OWNER][FINALIZE] source=$source enforced_ok=$ok');
      if (!ok && mounted) {
        _showSnack(
          'Owner ataması tamamlanamadı. Lütfen Bluetooth kurulumunu yeniden deneyin.',
        );
      }
      return ok;
    } finally {
      _clearBlockingProgress();
    }
  }
}
