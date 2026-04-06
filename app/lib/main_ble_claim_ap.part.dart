part of 'main.dart';

extension _HomeScreenBleClaimApPart on _HomeScreenState {
  // Cloud claim akışını tek yerde tutar; wrapper method main.dart içinde kalır.
  Future<bool> _claimViaCloudWithSecretImpl({
    required String id6,
    required String claimSecret,
    bool allowRecoveryPrompt = true,
  }) async {
    if (!_cloudLoggedIn()) return false;
    if (!(await _cloudClaimAllowed(
      source: 'claim_via_cloud_with_secret',
      refreshLocalState: true,
    ))) {
      return false;
    }
    final normalizedId6 = _normalizeDeviceId6(id6.trim());
    final secret = claimSecret.trim();
    if (normalizedId6 == null || normalizedId6.isEmpty || secret.isEmpty) {
      return false;
    }

    await _cloudRefreshIfNeeded();
    final ok = await cloudApi.claimDeviceWithAutoSync(
      normalizedId6,
      const Duration(seconds: 20),
      claimSecret: secret,
      userIdHash: _cloudUserIdHash(),
      deviceBrand: _activeDevice?.brand,
      deviceSuffix: _activeDevice?.suffix,
    );
    if (!ok) {
      final err = (cloudApi.lastClaimError ?? '').trim();
      if (allowRecoveryPrompt &&
          (err == 'already_claimed' || err == 'claim_proof_mismatch')) {
        return _promptCloudOwnershipRecovery(
          id6: normalizedId6,
          claimSecret: secret,
          userIdHash: _cloudUserIdHash(),
        );
      }
      if (err == 'claim_proof_mismatch') {
        await _invalidateActiveClaimToken(reason: err);
      }
      return false;
    }

    await _syncCloudDevices(autoSelectIfNeeded: false, showSnack: false);
    await _refreshOwnerFromCloud();
    await _refreshCloudMembers(force: true);
    if (_cloudInvitesSupported()) {
      await _refreshCloudInvites(force: true);
    }
    _cloudSetupTerminalError = null;
    _cloudSetupStatus = 'Bulut hazir';
    _startCloudPreferWindow();
    if (state != null) {
      state!.cloudClaimed = true;
    }
    final setupCreds = await _loadBleSetupCredsForId6(normalizedId6);
    final setupUser = (setupCreds?['user'] ?? '').trim();
    final setupPass = (setupCreds?['pass'] ?? '').trim();
    if (setupUser.isNotEmpty && setupPass.isNotEmpty) {
      await _maybeFinalizeLocalOwnerAfterCloudClaim(
        id6: normalizedId6,
        setupUser: setupUser,
        setupPass: setupPass,
        source: 'manual_cloud_claim',
      );
    }
    _safeSetState(() {});
    return true;
  }

  Future<void> _openManualClaimSecretRecoveryImpl() async {
    final idCtl = TextEditingController(text: _deviceId6ForMqtt() ?? '');
    final secretCtl = TextEditingController();
    try {
      final raw =
          await showDialog<Map<String, String>>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Recovery kodu gir'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'QR yoksa cihaz ID (6 hex) ve recovery/pair token girerek claim akışını yeniden başlatabilirsiniz.',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: idCtl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Cihaz ID (id6)',
                      hintText: 'A1B2C3',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: secretCtl,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Recovery kodu / pair token',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Iptal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(<String, String>{
                    'id6': idCtl.text.trim(),
                    'secret': secretCtl.text.trim(),
                  }),
                  child: const Text('Kaydet'),
                ),
              ],
            ),
          ) ??
          const <String, String>{};

      final id6 = _normalizeDeviceId6((raw['id6'] ?? '').trim());
      final secret = (raw['secret'] ?? '').trim();
      if (id6 == null || id6.isEmpty) {
        _showSnack('Gecerli cihaz ID girin (6 hex).');
        return;
      }
      if (secret.length < 12) {
        _showSnack('Recovery kodu/pair token gecersiz gorunuyor.');
        return;
      }

      await _ensureActiveDeviceForId6(id6);
      await _setBleTargetId6InPrefs(id6);
      await _applyPairToken(secret, deviceListId: id6);
      _setClaimFlowStage(
        _ClaimFlowStage.qrStored,
        detail: 'Recovery kodu kaydedildi, claim dogrulamasi baslatiliyor...',
      );
      await _retryOwnerClaimFlow();
    } finally {
      idCtl.dispose();
      secretCtl.dispose();
    }
  }

  Future<void> _retryOwnerClaimFlowImpl() async {
    if (_claimFlowBusy) return;
    _claimFlowBusy = true;
    bool openWizardAfter = false;
    try {
      final st = state;
      if (st != null && st.ownerExists) {
        _setClaimFlowStage(
          _ClaimFlowStage.claimed,
          detail: 'Cihaz zaten owner atanmis.',
        );
        return;
      }

      String? id6 = await _getBleTargetId6FromPrefs();
      id6 = id6?.trim();
      if (id6 == null || id6.isEmpty) {
        id6 = (_deviceId6ForMqtt() ?? '').trim();
      }
      if (id6.isEmpty) {
        _setClaimFlowStage(
          _ClaimFlowStage.failed,
          detail:
              'Cihaz kimligi bulunamadi. BLE cihaz secimi icin kurulum sihirbazi aciliyor...',
        );
        openWizardAfter = true;
      }
      if (openWizardAfter) return;

      final claimSecret = await _resolveActivePairToken();
      if (claimSecret == null || claimSecret.trim().isEmpty) {
        _setClaimFlowStage(
          _ClaimFlowStage.failed,
          detail:
              'Cihaz dogrulama kodu bulunamadi. Soft recovery acip tekrar deneyin.',
        );
        return;
      }

      if (_cloudLoggedIn()) {
        _setClaimFlowStage(
          _ClaimFlowStage.claiming,
          detail: 'Cloud sahiplik dogrulamasi deneniyor...',
        );
        final cloudOk = await _claimViaCloudWithSecret(
          id6: id6,
          claimSecret: claimSecret,
          allowRecoveryPrompt: true,
        );
        if (cloudOk) {
          _setClaimFlowStage(
            _ClaimFlowStage.claimed,
            detail: 'Cloud owner claim tamamlandi.',
          );
          return;
        }
      }

      final setupCreds = await _loadBleSetupCredsForId6(id6);
      final setupUser = (setupCreds?['user'] ?? '').trim();
      final setupPass = (setupCreds?['pass'] ?? '').trim();
      if (setupUser.isEmpty || setupPass.isEmpty) {
        _setClaimFlowStage(
          _ClaimFlowStage.failed,
          detail:
              'Cihaz kurulum bilgisi bulunamadi. Recovery kodu ile cloud claim deneyin veya Bluetooth kurulumunu tekrar baslatin.',
        );
        return;
      }

      _setClaimFlowStage(
        _ClaimFlowStage.claiming,
        detail: 'AP/BLE dogrulamasi deneniyor...',
      );
      final ok = await _finalizeOwnerClaimAfterQr(
        id6: id6,
        setupUser: setupUser,
        setupPass: setupPass,
      );
      if (ok) {
        _setClaimFlowStage(
          _ClaimFlowStage.claimed,
          detail: 'Owner claim tamamlandi.',
        );
      } else {
        _setClaimFlowStage(
          _ClaimFlowStage.failed,
          detail: 'Owner claim tamamlanamadi. Bluetooth ile tekrar deneyin.',
        );
      }
    } finally {
      _claimFlowBusy = false;
    }
    if (openWizardAfter && mounted) {
      await _openBleManageAndProvision();
    }
  }

  // AP kontrol modunu tek giriş noktasından açar.
  Future<void> _toggleApControlImpl() async {
    final u = Uri.tryParse(api.baseUrl);
    final onDeviceAp = (u != null && u.host == '192.168.4.1');

    if (!onDeviceAp) {
      _showSnack('Once cihazin WiFi AP\'sine (192.168.4.1) baglanin.');
      return;
    }

    final okAuth = await _ensurePairTokenForAp(prompt: true);
    if (!okAuth) return;

    try {
      _showSnack('AP baglantisi kuruluyor...');
      await _applyProvisionedBaseUrl('http://192.168.4.1', showSnack: false);

      final ok = await api.testConnection();
      if (ok) {
        final nextState = await api.fetchState();
        if (mounted) {
          _safeSetState(() {
            connected = true;
            _lastLocalOkAt = DateTime.now();
            if (nextState != null) {
              state = nextState;
              _lastUpdate = DateTime.now();
            }
          });
          _showSnack(
            nextState == null
                ? 'AP baglantisi kuruldu (durum okunamadi).'
                : 'AP uzerinden baglanti basarili!',
          );
          _startPolling();
        }
        if (_localReadyForOnboardingPrompt()) {
          await _maybeShowPostOnboardingLocalReadyPrompt();
        }
      } else {
        _showSnack(
          'AP baglantisi basarisiz. Cihaz dogrulama kodunu ve soft recovery durumunu kontrol edin.',
        );
      }
    } catch (e) {
      debugPrint('[AP][CONTROL] Error: $e');
      _showSnack('AP baglanti hatasi: $e');
    }
  }

  Future<void> _openApProvisionImpl() async {
    await _applyProvisionedBaseUrl('http://192.168.4.1', showSnack: false);
    final okAuth = await _ensurePairTokenForAp(prompt: true);
    if (!okAuth) return;
    final activeBrand = _activeDevice?.brand.trim() ?? '';
    final runtimeBrand = brandFromDeviceProduct(
      state?.deviceProduct ?? '',
    ).trim();
    final provisionBrand = activeBrand.isNotEmpty
        ? activeBrand
        : (runtimeBrand.isNotEmpty ? runtimeBrand : kDefaultDeviceBrand);
    if (!mounted) return;
    final result = await showModalBottomSheet<ApProvisionResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ApProvisionSheet(
        brandLabel: provisionBrand,
        onScanWifi: (scanCtx, controller) =>
            _scanWifiNetworks(scanCtx, controller),
        onProvision: (ssid, pass) => _apProvisionSend(ssid, pass),
      ),
    );
    if (!mounted || result == null) return;
    if (result.success && mounted) {
      _safeSetState(() => _tab = 0);
    }
    if (result.message.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
    if (result.showReconnectHint) {
      final ip = result.ip?.isNotEmpty == true ? result.ip : null;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Kurulum tamamlandi'),
          content: Text(
            [
              if (ip != null) 'Cihaz IP adresi: $ip',
              'Telefonunuzla yeniden ev Wi-Fi\'nize baglanin ve uygulamada cihazi kontrol edin.',
            ].join('\n\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    }
  }
}
