part of 'main.dart';

extension _HomeScreenMaintenanceOtaPart on _HomeScreenState {
  Future<void> _maybeShowOtaPrompt(
    DeviceState st, {
    bool showWhenNoUpdate = false,
  }) async {
    if (!mounted) return;
    final hasPendingApproval =
        st.otaPending && st.otaJobId.isNotEmpty && st.otaNewVersion.isNotEmpty;
    final hasLegacyUpdate = st.otaAvailable && st.otaNewVersion.isNotEmpty;
    final hasUpdate = hasPendingApproval || hasLegacyUpdate;
    final currentVersion = st.fwVersion;

    // Otomatik çağrılarda (showWhenNoUpdate=false) bu oturumda OTA uyarısı
    // zaten gösterildiyse tekrar gösterme.
    if (hasUpdate && !showWhenNoUpdate && _otaPromptShownThisSession) {
      return;
    }

    if (!hasUpdate && !showWhenNoUpdate) return;

    if (!hasUpdate) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.t('ota_no_update_title')),
          content: Text('${t.t('ota_no_update_message')}\n\n$currentVersion'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.t('ok')),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.t('ota_update_title')),
        content: Text(
          '${t.t('ota_update_message')}\n\n'
          'FW: $currentVersion\n'
          '${st.otaNewVersion}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.t('ota_update_now')),
          ),
        ],
      ),
    );
    // Bu oturumda OTA uyarısı bir kez gösterildi; otomatik çağrıları engelle.
    _otaPromptShownThisSession = true;
    if (confirmed == true && mounted) {
      String prettyOtaErr(String raw, {int? retryAfterMs}) {
        final e = raw.trim().toLowerCase();
        if (e.isEmpty) return t.t('command_failed');
        if (e == 'cloud_job_failed') return 'Cloud OTA job oluşturulamadı';
        if (e == 'ota_approve_failed') return 'OTA onayı cihaza iletilemedi';
        if (e == 'local_ota_failed') return 'Yerel OTA yükleme başarısız';
        if (e == 'sha256_required') return 'Firmware SHA256 zorunlu';
        if (e == 'bad_sha256') return 'Firmware SHA256 geçersiz';
        if (e == 'sha256_mismatch' || e == 'sha256_mismatch_local') {
          return 'Firmware bütünlük doğrulaması başarısız';
        }
        if (e == 'auth_signature_required') {
          return 'OTA için imzalı owner yetkisi gerekiyor';
        }
        if (e == 'ota_cooldown') {
          if (retryAfterMs != null && retryAfterMs > 0) {
            return 'OTA bekleme süresi aktif (${(retryAfterMs / 1000).ceil()} sn)';
          }
          return 'OTA bekleme süresi aktif';
        }
        if (e.startsWith('fw_download_http_')) {
          return 'Firmware indirilemedi (${e.replaceFirst('fw_download_http_', 'HTTP ')})';
        }
        if (e == 'fw_download_bad_url') return 'Firmware URL geçersiz';
        if (e == 'ota_start_failed') {
          return 'Cihaz OTA başlatma komutu reddetti';
        }
        return raw;
      }

      final otaStage = ValueNotifier<String>(t.t('ota_updating_message'));
      // Kullanıcı güncellemeyi onayladı; cihazda OTA başlatılırken
      // basit bir "yükleniyor" diyaloğu göster.
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            title: Text(t.t('ota_update_title')),
            content: ValueListenableBuilder<String>(
              valueListenable: otaStage,
              builder: (ctx, stage, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(stage, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      );
      var ok = false;
      var usedApprovalCmd = false;
      var usedCloudOta = false;
      var usedLocalUpload = false;
      String? otaErr;
      final cloudId6 = _deviceId6ForMqtt();
      final now = DateTime.now();
      if (hasPendingApproval) {
        otaStage.value = 'Güncelleme onayı cihaza gönderiliyor...';
        final approveOk = await _sendToDevice({
          'type': 'OTA_APPROVE',
          'jobId': st.otaJobId,
        });
        if (approveOk) {
          ok = true;
          usedApprovalCmd = true;
        } else {
          otaErr = 'ota_approve_failed';
        }
      }
      final canCloudOta =
          !hasPendingApproval &&
          _cloudOtaJobsSupported() &&
          _cloudReady(now) &&
          _cloudMqttReady() &&
          cloudId6 != null &&
          cloudId6.isNotEmpty &&
          st.otaFirmwareUrl.isNotEmpty &&
          st.otaSha256.length == 64 &&
          st.otaNewVersion.isNotEmpty;
      if (canCloudOta) {
        otaStage.value = 'Cloud OTA job hazırlanıyor...';
        final refreshed = await _cloudRefreshIfNeeded();
        if (_cloudAuthReady(now) || refreshed) {
          final job = await cloudApi.createOtaJob(
            cloudId6,
            firmwareUrl: st.otaFirmwareUrl,
            sha256: st.otaSha256,
            version: st.otaNewVersion,
            minVersion: st.otaMinVersion.isEmpty ? null : st.otaMinVersion,
            product: st.deviceProduct,
            hwRev: st.deviceHwRev,
            boardRev: st.deviceBoardRev,
            fwChannel: st.deviceFwChannel,
            force: false,
            dryRun: false,
          );
          if (job != null) {
            ok = true;
            usedCloudOta = true;
            _markCloudOk();
          } else {
            _markCloudFail();
            otaErr = 'cloud_job_failed';
          }
        }
      }
      if (!ok &&
          !hasPendingApproval &&
          st.otaFirmwareUrl.isNotEmpty &&
          st.otaSha256.length == 64 &&
          st.otaNewVersion.isNotEmpty) {
        try {
          otaStage.value = 'Firmware indiriliyor...';
          final fwUri = Uri.tryParse(st.otaFirmwareUrl.trim());
          if (fwUri != null && fwUri.scheme == 'https') {
            final fwResp = await http
                .get(fwUri)
                .timeout(const Duration(seconds: 120));
            if (fwResp.statusCode >= 200 && fwResp.statusCode < 300) {
              otaStage.value = 'Yerel OTA yükleniyor...';
              final up = await api.uploadLocalOta(
                firmwareBytes: fwResp.bodyBytes,
                sha256Hex: st.otaSha256,
                fileName: 'aac-${st.otaNewVersion}.bin',
              );
              if (up != null && up['ok'] == true) {
                ok = true;
                usedLocalUpload = true;
              } else {
                final retryAfterMs = int.tryParse(
                  (up?['retryAfterMs'] ?? '').toString(),
                );
                otaErr = (up?['err'] ?? up?['error'] ?? 'local_ota_failed')
                    .toString();
                otaErr = prettyOtaErr(otaErr, retryAfterMs: retryAfterMs);
              }
            } else {
              otaErr = 'fw_download_http_${fwResp.statusCode}';
              otaErr = prettyOtaErr(otaErr);
            }
          } else {
            otaErr = 'fw_download_bad_url';
            otaErr = prettyOtaErr(otaErr);
          }
        } catch (e) {
          otaErr = prettyOtaErr(e.toString());
        }
      }
      if (!ok) {
        otaStage.value = 'Cihaz OTA komutu tetikleniyor...';
        ok = await _sendToDevice({'otaStart': true});
        if (!ok && (otaErr?.isEmpty ?? true)) {
          otaErr = prettyOtaErr('ota_start_failed');
        }
      }
      if (!ok && mounted) {
        _showSnack(
          otaErr == null ? t.t('command_failed') : 'OTA hata: $otaErr',
        );
        Navigator.of(context, rootNavigator: true).pop(); // progress dialog
      } else if (mounted) {
        otaStage.value = 'Tamamlandı. Cihaz yeniden başlatılıyor...';
        if (usedApprovalCmd) {
          _showSnack('OTA onayı gönderildi. Cihaz güncellemeye başlayacak.');
        } else if (usedCloudOta) {
          _showSnack('Cloud OTA job kuyruğa alındı.');
        } else if (usedLocalUpload) {
          _showSnack('Yerel OTA yüklendi, cihaz yeniden başlatılıyor.');
        }
        // Kısa bir süre sonra diyaloğu kapat; cihaz OTA sırasında reset atacak.
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        });
      }
    }
  }

  Future<void> _runCalibration() async {
    _showSnack(widget.i18n.t('calibrating'));
    await _send({'mode': 1});
    final steps = [20, 30, 40, 50, 60, 70, 80, 90, 100];
    final results = <int>[];
    for (final p in steps) {
      await _send({'fanPercent': p});
      final rpm = await _waitStableRPM();
      results.add(rpm);
    }
    await _sendToDevice({'calibSave': results});
    final st = await _fetchStateSmart();
    if (st != null) {
      _safeSetState(() {
        state = st;
        _syncAutoHumControlsFromState(st);
        _pushHistorySample(st);
      });
    }
    _showSnack(widget.i18n.t('ok'));
  }

  Future<void> _runTest() async {
    _showSnack(widget.i18n.t('testing'));
    await _send({'mode': 1});
    const p = 50;
    await _send({'fanPercent': p});
    final cur = await _waitStableRPM();
    final s = state;
    if (s == null || s.calibRPM.length != 9) return;
    final ref = s.calibRPM[3];
    String msg = 'OK';
    if (ref > 0) {
      final drop = 1 - (cur / ref.toDouble());
      if (drop >= 0.20) msg = 'BAD';
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString('filterMsg', msg);
    _safeSetState(() => lastFilterMsg = msg);
    _showSnack(
      msg == 'BAD' ? widget.i18n.t('filter_bad') : widget.i18n.t('filter_ok'),
    );
  }

  Future<int> _waitStableRPM() async {
    final samples = <int>[];
    final end = DateTime.now().isUtc
        ? DateTime.now().toUtc().add(const Duration(seconds: 8))
        : DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(end)) {
      final s = await _fetchStateSmart();
      if (mounted && s != null) {
        _safeSetState(() {
          state = s;
          _syncAutoHumControlsFromState(s);
        });
      }
      if (s?.rpm != null) {
        samples.add(s!.rpm);
        if (samples.length >= 3) {
          final a = samples[samples.length - 3].toDouble();
          final b = samples[samples.length - 2].toDouble();
          final c = samples[samples.length - 1].toDouble();
          final avg = (a + b + c) / 3.0;
          final ok =
              (((a - avg).abs() / avg < 0.03) &&
              ((b - avg).abs() / avg < 0.03) &&
              ((c - avg).abs() / avg < 0.03));
          if (ok) return avg.round();
        }
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    return samples.isNotEmpty ? samples.last : 0;
  }

  Future<void> _checkOtaNow() async {
    if (!_canControlDevice) {
      _showSnack(t.t('device_not'));
      return;
    }
    _showSnack(t.t('connecting'));
    // otaCheckNow is deprecated in firmware. Refresh state and use cloud.ota
    // fields (pending/jobId/version) to decide update prompt.
    final s = await _fetchStateSmart();
    if (!mounted || s == null) return;
    _safeSetState(() {
      state = s;
      _syncAutoHumControlsFromState(s);
    });
    await _maybeShowOtaPrompt(s, showWhenNoUpdate: true);
  }
}
