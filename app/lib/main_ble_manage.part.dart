part of 'main.dart';

extension _HomeScreenBleManagePart on _HomeScreenState {
  // BLE manage/provision ekranını açan ana akış.
  Future<void> _openBleManageAndProvisionImpl() async {
    if (_bleManageSheetOpen) return;
    _bleManageSheetOpen = true;
    _beginTransportSession('ble-manage');
    _pauseBackground(reason: 'ble-manage');
    try {
      await _cleanupBleControlSession();
      final supported = await FlutterBluePlus.isSupported;
      if (!mounted) return;
      if (supported == false) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.t('ble_not_supported'))));
        return;
      }

      final st = await safeAdapterState(timeout: const Duration(seconds: 5));
      if (st == BluetoothAdapterState.off) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t.t('ble_turn_on'))));
        }
        return;
      }

      String? targetId6;
      String? setupUser;
      String? setupPass;
      String? pairToken;

      final activeId6 = _deviceId6ForMqtt();
      final lastId6 = await _getBleTargetId6FromPrefs();
      final preferredId6 = (activeId6 != null && activeId6.trim().isNotEmpty)
          ? activeId6.trim()
          : null;
      final autoTargetId6 = preferredId6;
      debugPrint(
        '[BLE][MANAGE] target id6 decision active=$activeId6 last=$lastId6 chosen=$autoTargetId6',
      );
      if (autoTargetId6 != null) {
        final cached = await _loadBleSetupCredsForId6(autoTargetId6);
        if (cached != null) {
          targetId6 = autoTargetId6;
          setupUser = cached['user'];
          setupPass = cached['pass'];
          debugPrint(
            '[BLE][MANAGE] cached BLE setup creds bulundu: id6=$targetId6, user=${setupUser?.substring(0, 3) ?? "null"}...',
          );

          final thingName = thingNameFromAny(targetId6);
          debugPrint('[BLE][MANAGE] pairToken yükleniyor: id6=$targetId6');
          pairToken = await _loadPairToken(targetId6);
          debugPrint(
            '[BLE][MANAGE] pairToken (id6) len=${pairToken?.length ?? 0}',
          );
          if ((pairToken == null || pairToken.isEmpty) && thingName != null) {
            debugPrint(
              '[BLE][MANAGE] pairToken yükleniyor (thingName): $thingName',
            );
            pairToken = await _loadPairToken(thingName);
            debugPrint(
              '[BLE][MANAGE] pairToken (thingName) len=${pairToken?.length ?? 0}',
            );
          }
          debugPrint(
            '[BLE][MANAGE] Final pairToken for id6=$targetId6 len=${pairToken?.length ?? 0}',
          );
        } else {
          debugPrint(
            '[BLE][MANAGE] UYARI: targetId6=$autoTargetId6 için cached creds bulunamadı!',
          );
        }
      } else {
        debugPrint(
          '[BLE][MANAGE] aktif id6 yok -> otomatik BLE hedefleme kapatıldı (manual seçim)',
        );
      }
      if ((targetId6 == null || targetId6.trim().isEmpty) &&
          ((setupUser ?? '').trim().isEmpty ||
              (setupPass ?? '').trim().isEmpty) &&
          (pairToken == null || pairToken.trim().isEmpty)) {
        _showSnack(
          'Cihazı IR kumanda ile eşleştirme moduna alın, sonra BLE cihazını seçin.',
        );
      }

      BluetoothDevice? initialDevice;
      if (_bleControlMode && _bleCtrlDevice != null) {
        initialDevice = _bleCtrlDevice;
        debugPrint(
          '[BLE][MANAGE] Using already connected device: ${_bleCtrlDevice!.remoteId.str}',
        );
      }

      var provisionSucceeded = false;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => BleProvisionSheet(
          initialDevice: initialDevice,
          targetId6: targetId6,
          setupUser: setupUser,
          setupPass: setupPass,
          pairToken: pairToken,
          onBaseUrlResolved: (url) async {
            final applied = await _applyProvisionedBaseUrl(url);
            if (applied && mounted) _safeSetState(() {});
          },
          onSend: (ssid, pass, device) async {
            debugPrint(
              '[BLE] onSend callback from sheet (ssid=' +
                  ssid +
                  ', passLen=' +
                  pass.length.toString() +
                  ')',
            );
            final ok = await _bleProvisionSend(
              ssid: ssid,
              pass: pass,
              preferredDevice: device,
            );
            provisionSucceeded = ok;
            return ok;
          },
          onOwnerClaimed: () async {
            await _refreshOwnerSigningKey();
          },
          onPairTokenDiscovered: (token, idHint) async {
            final normalizedHint = (idHint ?? '').trim();
            final target =
                (normalizedHint.isNotEmpty
                        ? (canonicalizeDeviceId(normalizedHint) ??
                              normalizedHint)
                        : (targetId6 ?? _activeDeviceId ?? ''))
                    .trim();
            await _applyPairToken(
              token,
              deviceListId: target.isNotEmpty ? target : null,
            );
          },
          onScanWifi: (sheetCtx, ctl) => _scanWifiNetworks(sheetCtx, ctl),
          loadPairToken: _pairTokenForBleSheet,
          clearPairToken: _clearPairTokenForBleSheet,
          loadSetupCreds: _loadBleSetupCredsForId6,
        ),
      );
      if (provisionSucceeded) {
        final ownerReady = await _ensureLocalOwnerClaimAfterProvision(
          idHint: targetId6,
          setupUserHint: setupUser,
          setupPassHint: setupPass,
          source: 'ble_manage_sheet',
        );
        if (!ownerReady) {
          _setClaimFlowStage(
            _ClaimFlowStage.failed,
            detail:
                'Owner ataması doğrulanamadı. Cloud öncesi BLE kurulumunu tekrar başlatın.',
          );
        }
      }
      if (provisionSucceeded && _postOnboardingLocalReadyPromptPending) {
        await _maybeShowPostOnboardingLocalReadyPrompt();
      }
    } on StateError catch (e, st) {
      debugPrint('[BLE][MANAGE] state error: $e');
      debugPrint(st.toString());
      if (mounted) {
        _showSnack(
          'BLE akışında beklenmeyen durum oluştu. Lütfen tekrar deneyin.',
        );
      }
    } catch (e, st) {
      debugPrint('[BLE][MANAGE] unexpected error: $e');
      debugPrint(st.toString());
      if (mounted) {
        _showSnack('BLE yönetim akışı başarısız oldu. Yeniden deneyin.');
      }
    } finally {
      _postOnboardingLocalReadyPromptPending = false;
      _clearBlockingProgress();
      _endTransportSession('ble-manage');
      _bleManageSheetOpen = false;
      _resumeBackground(reason: 'ble-manage');
    }
  }

  Future<String?> _pairTokenForBleSheetImpl(String? id6) async {
    if (id6 != null && id6.trim().isNotEmpty) {
      final raw = id6.trim();
      final normalized = normalizeDeviceId6(raw);
      final candidates = <String>[
        if (normalized != null && normalized.isNotEmpty) normalized,
        if (canonicalizeDeviceId(raw) != null) canonicalizeDeviceId(raw)!,
        raw,
      ];
      for (final key in candidates.toSet()) {
        final stored = await _loadPairToken(key);
        if (stored != null && stored.isNotEmpty) {
          debugPrint(
            '[BLE][TOKEN] Loaded pairToken for device=$key len=${stored.length}',
          );
          return stored;
        }
      }
    }
    if (id6 != null && id6.trim().isNotEmpty) {
      return null;
    }
    final active = await _resolveActivePairToken();
    if (active != null && active.isNotEmpty) {
      debugPrint(
        '[BLE][TOKEN] Using active device pairToken len=${active.length}',
      );
    }
    return active;
  }

  Future<void> _clearPairTokenForBleSheetImpl(String? id6) async {
    String? targetId;
    if (id6 != null && id6.trim().isNotEmpty) {
      targetId = canonicalizeDeviceId(id6.trim()) ?? id6.trim();
    } else if (_activeDeviceId != null && _activeDeviceId!.trim().isNotEmpty) {
      targetId =
          canonicalizeDeviceId(_activeDeviceId!.trim()) ??
          _activeDeviceId!.trim();
    }
    if (targetId != null && targetId.isNotEmpty) {
      await _applyPairToken(null, deviceListId: targetId);
    }
  }

  Future<void> _resetPairTokenForActiveDeviceImpl() async {
    final deviceId = canonicalizeDeviceId(
      _activeCanonicalDeviceId ?? _activeDeviceId ?? '',
    );
    if (deviceId == null || deviceId.trim().isEmpty) {
      _showSnack(t.literal('Aktif cihaz bulunamadı.'));
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.literal('Cihazı yeniden eşleştir')),
          content: const Text(
            'Bu işlem cihazın kayıtlı doğrulama kodunu siler. Devam etmek için IR ile pair/recovery penceresini açıp Bluetooth kurulumunu tekrar yapmanız gerekecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.literal('Devam')),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await _applyPairToken(null, deviceListId: deviceId);
    _showSnack(
      'Cihaz doğrulama kodu temizlendi. IR ile pair/recovery penceresini açıp tekrar eşleştirin.',
    );
  }

  Future<void> _factoryResetActiveDeviceImpl() async {
    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) {
      _showSnack(t.literal('Aktif cihaz bulunamadı.'));
      return;
    }
    if (!_bleControlMode || _bleCtrlCmdChar == null) {
      _showSnack(t.literal('Önce BLE ile cihaza bağlanın.'));
      return;
    }
    if (!mounted) return;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text(t.literal('Fabrika Ayarlarına Dön')),
              content: const Text(
                'Bu işlem cihazdaki Wi-Fi ayarlarını, owner bilgisini ve kayıtlı güvenilen kullanıcıları siler. Cihazın recovery/doğrulama kodu değişmez. Devam edilsin mi?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(t.t('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(t.literal('Sıfırla')),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!ok) return;

    try {
      await _bleEnsureOwnerAuthed(targetId6: id6);
      if (!_bleSessionAuthed) {
        _showSnack('BLE owner doğrulaması gerekli.');
        return;
      }

      final sent = await _bleSendJson(<String, dynamic>{
        'type': 'FACTORY_RESET',
      });
      if (!sent) {
        _showSnack('Factory reset komutu gönderilemedi.');
        return;
      }

      await _applyProvisionedBaseUrl('http://192.168.4.1', showSnack: false);
      connected = false;
      state?.ownerExists = false;
      state?.ownerSetupDone = false;
      state?.cloudClaimed = false;
      _setClaimFlowStage(
        _ClaimFlowStage.waitingQr,
        detail:
            'Factory reset sonrası IR ile pair/recovery penceresini açıp owner kurulumu yapın.',
      );
      if (mounted) _safeSetState(() {});

      unawaited(safeBleDisconnect(_bleCtrlDevice, reason: 'factory_reset'));
      _showSnack('Factory reset komutu gönderildi. Cihaz yeniden başlıyor.');
      _allowNetworkAutoPolling();
      _startPolling();
    } catch (e) {
      debugPrint('[RESET] factory reset error: $e');
      _showSnack('Factory reset başarısız.');
    }
  }
}
