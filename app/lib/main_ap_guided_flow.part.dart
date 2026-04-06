part of 'main.dart';

// AP-GUIDED KURULUM AKIŞI
// Bu bölüm, "BLE ile cihazı seç -> AP bilgilerini al -> kullanıcıyı AP'ye yönlendir"
// akışını tek yerde toplar. Böylece ana ekran dosyasında onboarding detayları
// dağılmaz ve ileride marka bazlı UI ayrıştırması daha kolay yapılır.

extension _HomeScreenApGuidedFlow on _HomeScreenState {
  Future<void> _requestApSessionViaBleBestEffort({int ttlSec = 600}) async {
    if (!_bleControlMode || _bleCtrlCmdChar == null) return;
    final completer = Completer<Map<String, String>>();
    _bleApSessionCompleter = completer;
    try {
      final payload = <String, dynamic>{
        'type': 'AP_START',
        'ttl': ttlSec.clamp(60, 900),
      };
      final sent = await _bleSendJson(payload);
      if (!sent) return;
      final apSession = await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => <String, String>{},
      );
      final token = (apSession['token'] ?? '').trim();
      final nonce = (apSession['nonce'] ?? '').trim();
      if (token.isEmpty) return;
      _apSessionToken = token;
      _apSessionNonce = nonce.isNotEmpty ? nonce : null;
      api.setApSessionToken(_apSessionToken);
      api.setApSessionNonce(_apSessionNonce);
      debugPrint(
        '[BLE][AP] AP_START session received tokenLen=${token.length} nonceLen=${nonce.length}',
      );
    } catch (_) {
      // Best-effort only; AP flow can still continue with pairToken fallback.
    } finally {
      if (_bleApSessionCompleter == completer) {
        _bleApSessionCompleter = null;
      }
    }
  }

  /// AP-guided akış için BLE kontrol kanalını garanti eder.
  ///
  /// Mantık:
  /// 1) Hedef BLE cihazından id6 bulunur.
  /// 2) Aktif cihaz/prefs id6 ile hizalanır.
  /// 3) Eski BLE oturumu varsa temizlenir.
  /// 4) Yeni BLE kontrol oturumu açılır.
  /// 5) Cihaz owned ise owner auth tamamlanmadan devam edilmez.
  Future<bool> _ensureBleControlForApGuidedFlow() async {
    final picked = await _pickBleTargetId6ForApGuidedFlow();
    if (picked == null || picked.isEmpty) return false;
    await _setBleTargetId6InPrefs(picked);
    try {
      await _ensureActiveDeviceForId6(picked);
    } catch (_) {}

    if (_bleControlMode) {
      try {
        await _cleanupBleControlSession();
      } catch (_) {}
    }
    if (!_bleControlMode || _bleCtrlCmdChar == null) {
      await _toggleBleControl(
        interactive: false,
        allowUnownedWithoutSetupCreds: true,
      );
    }
    if (!_bleControlMode || _bleCtrlCmdChar == null) return false;
    if (state?.ownerExists == true) {
      await _bleEnsureOwnerAuthed();
      if (!_bleSessionAuthed) return false;
    }
    return true;
  }

  /// Yakındaki BLE cihazlar arasından AP-guided kurulum hedefini seçtirir ve id6 döndürür.
  ///
  /// Önce reklam isminden id6 çözmeye çalışır; çözemezse:
  /// - prefs/aktif cihaz fallback'i,
  /// - son çare GET_NONCE probe ile doğrulama yapar.
  Future<String?> _pickBleTargetId6ForApGuidedFlow() async {
    final bleReady = await _ensureBluetoothOnWithUi();
    if (!bleReady || !mounted) return null;

    final found = <ScanResult>[];
    StreamSubscription<List<ScanResult>>? sub;
    try {
      sub = FlutterBluePlus.scanResults.listen((batch) {
        for (final r in batch) {
          final name = r.device.platformName.trim();
          final adv = r.advertisementData.advName.trim();
          final merged = (name.isNotEmpty ? name : adv).toLowerCase();
          final isKnown = isKnownBleName(merged);
          if (!isKnown) continue;
          if (!found.any((e) => e.device.remoteId == r.device.remoteId)) {
            found.add(r);
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(seconds: 5));
      await FlutterBluePlus.stopScan();
    } catch (_) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    } finally {
      await sub?.cancel();
    }

    if (!mounted || found.isEmpty) {
      _showSnack('Yakında BLE cihaz bulunamadı.');
      return null;
    }

    found.sort((a, b) => b.rssi.compareTo(a.rssi));
    final picked = await showModalBottomSheet<ScanResult>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView.separated(
          itemCount: found.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = found[i];
            final id6 =
                _extractId6FromBleName(r.device.platformName) ??
                _extractId6FromBleName(r.advertisementData.advName);
            final bleName = r.device.platformName.trim().isNotEmpty
                ? r.device.platformName.trim()
                : (r.advertisementData.advName.trim().isNotEmpty
                      ? r.advertisementData.advName.trim()
                      : r.device.remoteId.str);
            return ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(
                id6 != null && id6.isNotEmpty
                    ? 'AP_$id6'
                    : bleName,
              ),
              subtitle: Text('$bleName • RSSI ${r.rssi}'),
              onTap: () => Navigator.of(context).pop(r),
            );
          },
        ),
      ),
    );
    if (picked == null) return null;

    var id6 =
        _extractId6FromBleName(picked.device.platformName) ??
        _extractId6FromBleName(picked.advertisementData.advName);
    String? fallbackId6;
    try {
      final prefId6 = await _getBleTargetId6FromPrefs();
      final activeId6 = _deviceId6ForMqtt();
      fallbackId6 =
          _normalizeDeviceId6(prefId6 ?? '') ??
          _normalizeDeviceId6(activeId6 ?? '');
    } catch (_) {
      fallbackId6 = null;
    }

    if (id6 == null || id6.isEmpty) {
      if (fallbackId6 != null && fallbackId6.isNotEmpty) {
        id6 = fallbackId6;
        debugPrint(
          '[BLE][AP] using fallback id6=$id6 for picked=${picked.device.remoteId.str}',
        );
      } else {
        _setBlockingProgress(
          title: t.t('please_wait'),
          body: 'Lütfen bekleyiniz. Cihaz kimliği doğrulanıyor...',
        );
        try {
          id6 = await _probeId6ViaGetNonce(picked.device);
        } finally {
          _clearBlockingProgress();
        }
      }
    }
    if (id6 == null || id6.isEmpty) {
      _showSnack('BLE cihaz bulundu ama ID çözülemedi.');
      return null;
    }
    return id6;
  }

  /// GET_NONCE mesajı ile cihazdan dönen JSON içinde id6 alanını parse eder.
  ///
  /// Bu yol, reklam isminde id6 yoksa kimlik doğrulamak için kullanılır.
  /// Geçici probe bağlantısı başarısızsa güvenli şekilde disconnect edilir.
  Future<String?> _probeId6ViaGetNonce(BluetoothDevice device) async {
    StreamSubscription<List<int>>? sub;
    final buf = StringBuffer();
    var connectedByProbe = false;
    String? resolvedId6;
    try {
      try {
        await device.connect(timeout: const Duration(seconds: 5));
        connectedByProbe = true;
      } catch (_) {}

      final services = await device.discoverServices();
      BluetoothCharacteristic? infoChar;
      BluetoothCharacteristic? cmdChar;
      BluetoothCharacteristic? infoFallback;
      BluetoothCharacteristic? cmdFallback;
      BluetoothCharacteristic? cmdAnyWritable;
      for (final s in services) {
        for (final c in s.characteristics) {
          final canNotify = c.properties.notify || c.properties.indicate;
          final canWrite =
              c.properties.write || c.properties.writeWithoutResponse;
          if (_guidEq(c.uuid, kInfoCharUuidHint)) {
            infoChar = c;
          } else if (canNotify && infoFallback == null) {
            infoFallback = c;
          }
          if (_guidEq(c.uuid, kCmdCharUuidHint)) {
            cmdChar = c;
          } else if (canWrite && cmdAnyWritable == null) {
            cmdAnyWritable = c;
            if (!_guidEq(c.uuid, kProvCharUuidHint) &&
                !_guidEq(c.uuid, kInfoCharUuidHint) &&
                cmdFallback == null) {
              cmdFallback = c;
            }
          }
        }
      }
      infoChar ??= infoFallback;
      cmdChar ??= cmdFallback ?? cmdAnyWritable;
      if (infoChar == null || cmdChar == null) return null;

      final id6Completer = Completer<String?>();
      sub = infoChar.lastValueStream.listen((data) {
        try {
          final chunk = utf8.decode(data, allowMalformed: true);
          buf.write(chunk);
          final m = RegExp(
            r'"id6"\s*:\s*"([0-9A-Fa-f]{6})"',
          ).firstMatch(buf.toString());
          if (m != null && !id6Completer.isCompleted) {
            id6Completer.complete(m.group(1));
          }
          if (buf.length > 4096) {
            final txt = buf.toString();
            buf.clear();
            buf.write(txt.substring(txt.length - 512));
          }
        } catch (_) {}
      });

      await infoChar.setNotifyValue(true);
      await cmdChar.write(
        utf8.encode(jsonEncode({'cmd': 'GET_NONCE'})),
        withoutResponse: !cmdChar.properties.write,
      );
      final id6 = await id6Completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
      resolvedId6 = _normalizeDeviceId6(id6 ?? '');
      return resolvedId6;
    } catch (_) {
      return null;
    } finally {
      try {
        await sub?.cancel();
      } catch (_) {}
      if (connectedByProbe && (resolvedId6 == null || resolvedId6.isEmpty)) {
        try {
          await safeBleDisconnect(device, reason: 'ap_guided_probe_done');
        } catch (_) {}
      }
    }
  }

  /// BLE üzerinden `ap_credentials` ister.
  ///
  /// Kritik nokta: token bulunduğu anda `api.setPairToken(...)` ve
  /// `_applyPairToken(...)` çağrıları yapılarak AP tarafındaki `/api` isteklerinin
  /// unauthorized olmasının önüne geçilir.
  Future<Map<String, String>?> _requestApCredentialsViaBle() async {
    if (!_bleControlMode || _bleCtrlCmdChar == null) return null;
    final completer = Completer<Map<String, String>>();
    _bleApCredsCompleter = completer;
    try {
      String? pairToken = (_bleControlPairToken ?? '').trim();
      if (pairToken.isEmpty) {
        pairToken = await _resolveActivePairToken();
      }
      if (pairToken == null || pairToken.trim().isEmpty) {
        final nonceProbe = Completer<Map<String, dynamic>>();
        _bleNonceMapCompleter = nonceProbe;
        try {
          await _bleSendJson(const {'cmd': 'GET_NONCE'});
          final nonceObj = await nonceProbe.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () => <String, dynamic>{},
          );
          final tok = (nonceObj['pairToken'] ?? nonceObj['qrToken'] ?? '')
              .toString()
              .trim();
          if (tok.isNotEmpty) {
            pairToken = tok;
            _bleControlPairToken = tok;
            final id6 = await _getBleTargetId6FromPrefs();
            if (id6 != null && id6.trim().isNotEmpty) {
              await _applyPairToken(tok, deviceListId: id6.trim());
            }
          }
        } catch (_) {
        } finally {
          if (_bleNonceMapCompleter == nonceProbe) {
            _bleNonceMapCompleter = null;
          }
        }
      }
      final payload = <String, dynamic>{'get': 'ap_credentials'};
      if (pairToken != null && pairToken.trim().isNotEmpty) {
        final normalizedToken = pairToken.trim();
        payload['qrToken'] = normalizedToken;
        api.setPairToken(normalizedToken);
        final id6 =
            _normalizeDeviceId6(await _getBleTargetId6FromPrefs() ?? '') ??
            _normalizeDeviceId6(_deviceId6ForMqtt() ?? '');
        await _applyPairToken(normalizedToken, deviceListId: id6);
      }
      debugPrint(
        '[BLE][AP] request ap_credentials qrTokenLen=${(payload['qrToken'] ?? '').toString().length}',
      );
      var sent = await _bleSendJson(payload);
      if (!sent) {
        debugPrint(
          '[BLE][AP] first ap_credentials write failed; trying one BLE reconnect/retry',
        );
        final recovered = await _ensureBleControlForApGuidedFlow();
        if (!recovered) return null;
        sent = await _bleSendJson(payload);
      }
      if (!sent) return null;
      return await completer.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    } finally {
      _bleApCredsCompleter = null;
    }
  }

  /// Uçtan uca AP-guided kurulum akışı.
  ///
  /// 1) BLE kontrol + kimlik doğrulama
  /// 2) BLE'den AP SSID/şifre alma
  /// 3) Kullanıcıyı manuel Wi-Fi geçişine yönlendirme
  /// 4) AP base URL + token doğrulama
  /// 5) Provision ekranını açma
  Future<void> _runApGuidedSetupFlow() async {
    if (!mounted) return;

    _setBlockingProgress(
      title: t.t('please_wait'),
      body: 'Lütfen bekleyiniz. Cihaz AP bilgileri hazırlanıyor...',
    );
    try {
      final bleReady = await _ensureBleControlForApGuidedFlow();
      if (!bleReady) {
        _showSnack('BLE bağlantısı kurulamadı.');
        return;
      }

      final apCreds = await _requestApCredentialsViaBle();
      if (apCreds != null) {
        await _requestApSessionViaBleBestEffort(ttlSec: 600);
      }
      _clearBlockingProgress();
      bool joined = false;
      if (apCreds != null) {
        joined =
            await _promptManualJoinToAp(
              ssid: apCreds['ssid'] ?? '',
              pass: apCreds['pass'] ?? '',
            ) ==
            true;
      } else {
        _showSnack(
          'Cihaz AP bilgileri Bluetooth üzerinden alınamadı. IR ile pair/recovery penceresini yeniden açıp kurulumu tekrar başlatın.',
        );
        return;
      }

      if (!joined) {
        _showSnack(
          'Kurulum için önce telefonu cihazın Wi-Fi ağına bağlamalısınız.',
        );
        return;
      }

      await _applyProvisionedBaseUrl('http://192.168.4.1', showSnack: false);
      final hasApSession = (_apSessionToken ?? '').trim().isNotEmpty;
      final okAuth = hasApSession || await _ensurePairTokenForAp(prompt: false);
      if (!okAuth) {
        _showSnack(
          'AP yetkilendirmesi doğrulanamadı. BLE ile soft recovery açıp tekrar deneyin.',
        );
        return;
      }

      await _openApProvision();
    } finally {
      _clearBlockingProgress();
    }
  }
}
