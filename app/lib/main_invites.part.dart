part of 'main.dart';

// Davet/paylaşım akışlarının tek yerde toplanmış hali.
extension _HomeScreenInvites on _HomeScreenState {
  String _inviteBrandLabel() {
    final active = _activeDevice?.brand.trim() ?? '';
    if (active.isNotEmpty) return active;
    final runtime = brandFromDeviceProduct(state?.deviceProduct ?? '').trim();
    if (runtime.isNotEmpty) return runtime;
    return kDefaultDeviceBrand;
  }

  Future<String?> _selectInviteRole() async {
    if (!mounted) return null;
    await _settleRouteTransition();
    if (!mounted) return null;
    return Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _ChoicePage(
          title: 'Davet rolü seç',
          description: 'Owner davetle atanamaz. User veya Guest seçin.',
          options: [
            _ChoiceOption(
              value: 'USER',
              title: 'User',
              subtitle:
                  'Kontrol edebilir, planlama/bağlantı/güncelleme yapamaz.',
              icon: Icons.manage_accounts_outlined,
              emphasized: true,
            ),
            _ChoiceOption(
              value: 'GUEST',
              title: 'Guest',
              subtitle: 'Sadece görüntüleme.',
              icon: Icons.visibility_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateInviteQr() async {
    await _joinViaApWithInviteDialog();
  }

  Map<String, dynamic> _buildCloudInviteSharePayload(
    String id6,
    Map<String, dynamic> invite,
  ) {
    final payload = Map<String, dynamic>.from(invite);
    payload['t'] = 'device_invite';
    payload['source'] = 'cloud';
    payload['cloud'] = true;
    payload['deviceId'] = id6;
    payload['id6'] = id6;
    final nested = Map<String, dynamic>.from(invite);
    nested['source'] = 'cloud';
    nested['cloud'] = true;
    payload['invite'] = nested;
    payload['cloudInvite'] = Map<String, dynamic>.from(payload);
    return payload;
  }

  String _inviteShareText(Map<String, dynamic> invitePayload) {
    final role = (invitePayload['role'] ?? 'USER').toString().toUpperCase();
    final id6 = (invitePayload['id6'] ?? invitePayload['deviceId'] ?? '')
        .toString();
    final pretty = const JsonEncoder.withIndent('  ').convert(invitePayload);
    final brand = _inviteBrandLabel();
    return '$brand cihaz daveti\n'
        'Rol: $role\n'
        'Cihaz: $id6\n\n'
        'Bu metni uygulamada "Davet ile katıl" ekranına yapıştırın veya QR olarak okutun.\n\n'
        '$pretty';
  }

  Future<String?> _promptInviteeEmail({
    String title = 'E-posta adresi',
    String hintText = 'ornek@email.com',
    String initialValue = '',
    String submitLabel = 'Devam',
  }) async {
    if (!mounted) return null;
    await _settleRouteTransition();
    if (!mounted) return null;
    final email = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CloudEmailPage(
          title: title,
          initialEmail: initialValue,
          submitLabel: submitLabel,
        ),
      ),
    );
    return email;
  }

  bool _looksLikeEmail(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s);
  }

  Future<String?> _scanQrText({required String title}) async {
    if (!mounted) return null;
    await _settleRouteTransition();
    if (!mounted) return null;
    final cameraOk = await _ensureCameraPermissionForQr();
    if (!mounted || !cameraOk) return null;
    final controller = MobileScannerController();
    String? scanned;
    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (ctx) {
            return Scaffold(
              appBar: AppBar(title: Text(title)),
              body: MobileScanner(
                controller: controller,
                errorBuilder: (context, error) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('${t.literal('Kamera açılamadı')}: $error'),
                    ),
                  );
                },
                onDetect: (capture) {
                  final codes = capture.barcodes;
                  if (codes.isEmpty) return;
                  final raw = codes.first.rawValue;
                  if (raw == null || raw.isEmpty) return;
                  scanned = raw;
                  Navigator.of(ctx).pop();
                },
              ),
            );
          },
        ),
      );
    } finally {
      controller.dispose();
    }
    return scanned;
  }

  Future<String?> _promptInviteTextInput({String? initialText}) async {
    if (!mounted) return null;
    await _settleRouteTransition();
    if (!mounted) return null;
    final text = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TextEntryPage(
          title: 'Davet kodu',
          submitLabel: 'Katıl',
          hintText: 'QR içeriğini veya paylaşılan davet metnini yapıştırın',
          initialText: initialText ?? '',
          maxLines: 8,
        ),
      ),
    );
    return text;
  }

  Future<bool> _submitInvitePayloadFromText(
    String inviteText, {
    bool allowLoginRedirect = true,
  }) async {
    final raw = inviteText.trim();
    if (raw.isEmpty) return false;
    Map<String, dynamic>? inviteObj;
    try {
      final obj = jsonDecode(raw);
      if (obj is Map) {
        inviteObj = Map<String, dynamic>.from(obj);
      }
    } catch (_) {
      inviteObj = null;
    }
    if (inviteObj == null) {
      _showSnack('Geçersiz davet metni');
      return false;
    }

    if (_isCloudInvitePayload(inviteObj) && !_cloudLoggedIn()) {
      await _cachePendingCloudInvite(raw);
      if (!allowLoginRedirect) {
        _showSnack('Önce cloud girişi yapın.');
        return false;
      }
      final authChoice = await _showCloudAuthChoiceDialog();
      if (authChoice == 'login' || authChoice == 'signup') {
        await _handleCloudLoginSuccess(
          signup: authChoice == 'signup',
          promptPicker: false,
        );
        return _cloudLoggedIn();
      }
      if (authChoice == 'confirm') {
        await _openCloudConfirmDialog();
      } else if (authChoice == 'forgot') {
        await _startCloudForgotPasswordFlow();
      }
      _showSnack('Paylaşımı tamamlamak için cloud girişi gerekli.');
      return false;
    }

    if (await _joinInviteViaCloud(inviteObj)) {
      await _clearPendingCloudInvite();
      return true;
    }

    final localPayload = Map<String, dynamic>.from(inviteObj);
    final pub = _clientPubQ65B64;
    if (pub != null && pub.isNotEmpty) {
      localPayload['user_pubkey'] = pub;
    }
    if (api.baseUrl.trim().isNotEmpty) {
      final localOk = await api.joinInviteLocal(localPayload);
      if (localOk) {
        _showSnack('Davetle cihaza katılım başarılı.');
        return true;
      }
    }
    _showSnack('Davet kabul edilemedi.');
    return false;
  }

  Future<void> _startInviteJoinFlow({String? initialAction}) async {
    if (!mounted) return;
    var action = initialAction;
    if (action == null) {
      await _settleRouteTransition();
      if (!mounted) return;
      action = await Navigator.of(context, rootNavigator: true).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const _ChoicePage(
            title: 'Paylaşılan cihaz ekle',
            options: [
              _ChoiceOption(
                value: 'scan',
                title: 'QR tara',
                icon: Icons.qr_code_scanner,
                emphasized: true,
              ),
              _ChoiceOption(
                value: 'cloud',
                title: 'Davet ile kullanım',
                subtitle: 'Cloud hesabınıza gelen davetleri görüntüleyin.',
                icon: Icons.mail_outline,
              ),
            ],
          ),
        ),
      );
    }
    if (action == null) return;

    String? inviteText;
    if (action == 'scan') {
      inviteText = await _scanQrText(title: 'Paylaşılan cihaz QR tara');
    } else if (action == 'paste') {
      inviteText = await _promptInviteTextInput();
    } else if (action == 'cloud') {
      await _openPendingCloudInvitesFlow();
      return;
    }
    if (inviteText == null || inviteText.isEmpty) return;
    await _submitInvitePayloadFromText(inviteText);
  }

  Future<void> _openInviteJoinFlow() async {
    await _startInviteJoinFlow();
  }

  Future<void> _startDeviceShareFlow() async {
    if (!mounted) return;
    final id6 = await _resolveDeviceId6ForCloudAction();
    if (id6 == null || id6.isEmpty) {
      _showSnack('Cihaz ID bulunamadı');
      return;
    }
    if (!_cloudLoggedIn()) {
      _showSnack('Önce cloud girişi yapın');
      return;
    }
    final role = await _selectInviteRole();
    if (role == null || role.isEmpty) return;
    String? inviteeEmail;

    final refreshed = await _cloudRefreshIfNeeded();
    if (!_cloudAuthReady(DateTime.now()) && !refreshed) {
      _showSnack('Cloud oturumu gerekli');
      return;
    }

    if (!mounted) return;
    await _settleRouteTransition();
    if (!mounted) return;
    final action = await Navigator.of(context, rootNavigator: true)
        .push<String>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _ChoicePage(
              title: 'Paylaşım seçenekleri',
              description: 'Rol: $role',
              options: [
                const _ChoiceOption(
                  value: 'qr',
                  title: 'QR göster',
                  icon: Icons.qr_code_2,
                  emphasized: true,
                ),
                const _ChoiceOption(
                  value: 'email',
                  title: 'E-posta hesabına davet ver',
                  icon: Icons.mail_outline,
                ),
                if (_showAdvancedSettings)
                  const _ChoiceOption(
                    value: 'preview',
                    title: 'JSON önizleme',
                    icon: Icons.data_object,
                  ),
              ],
            ),
          ),
        );
    if (action == null) return;
    if (action == 'email') {
      inviteeEmail = await _promptInviteeEmail();
      if (inviteeEmail == null || inviteeEmail.trim().isEmpty) return;
      if (!_looksLikeEmail(inviteeEmail)) {
        _showSnack('Geçerli bir e-posta girin');
        return;
      }
    }

    final invite = await cloudApi.createInvite(
      id6,
      role: role,
      ttl: 600,
      userIdHash: _cloudUserIdHash(),
      inviteeEmail: inviteeEmail,
      timeout: const Duration(seconds: 8),
    );
    if (invite == null) {
      _showSnack('Davet oluşturulamadı');
      return;
    }
    final payload = _buildCloudInviteSharePayload(id6, invite);

    if (action == 'qr') {
      await _showInviteQrAndOpenJoin(payload);
      return;
    }
    if (action == 'email') {
      await _refreshCloudInvites(force: true);
      _showSnack('Davet ${inviteeEmail!.trim()} hesabına atandı.');
      return;
    }
    if (action == 'preview') {
      final shareText = _inviteShareText(payload);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(t.literal('Davet JSON')),
            content: SingleChildScrollView(child: SelectableText(shareText)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(t.literal('Kapat')),
              ),
            ],
          );
        },
      );
    }
  }

  Future<Map<String, dynamic>?> _waitForCloudInvite(
    String id6,
    String inviteId,
    Duration timeout,
  ) async {
    final canon = _canonicalInviteId(inviteId) ?? inviteId.toLowerCase();
    if (canon.isEmpty) return null;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final j = await cloudApi.fetchStateJson(id6, const Duration(seconds: 10));
      if (j != null && j['lastInvite'] is Map) {
        final inv = Map<String, dynamic>.from(j['lastInvite'] as Map);
        final invId = (inv['inviteId'] ?? '').toString().toLowerCase();
        if (invId == canon) {
          return inv;
        }
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }
    return null;
  }

  Future<bool> _joinInviteViaCloud(Map<String, dynamic> inviteObj) async {
    if (!_cloudInvitesSupported()) {
      _showSnack('Cloud davet özelliği bu ortamda kapalı.');
      return false;
    }

    final cloudPartRaw = inviteObj['cloudInvite'];
    final cloudPart = (cloudPartRaw is Map)
        ? Map<String, dynamic>.from(cloudPartRaw)
        : inviteObj;

    final src = cloudPart['source'] ?? cloudPart['cloud'];
    final inviteInner = cloudPart['invite'];
    final innerSrc = (inviteInner is Map)
        ? (inviteInner['source'] ?? inviteInner['cloud'])
        : null;
    final isCloudInvite =
        src == 'cloud' ||
        src == true ||
        (cloudPart['t'] ?? '').toString() == 'device_invite' ||
        innerSrc == 'cloud' ||
        innerSrc == true;
    if (!isCloudInvite) {
      debugPrint('[JOIN][CLOUD] skip: invite source is not cloud');
      return false;
    }
    final rawInviteId = (cloudPart['inviteId'] ?? cloudPart['invite_id'] ?? '')
        .toString();
    final inviteId = _canonicalInviteId(rawInviteId);
    if (inviteId == null || inviteId.isEmpty) {
      debugPrint(
        '[JOIN][CLOUD] invalid inviteId raw=${_maskInviteId(rawInviteId)}',
      );
      return false;
    }
    final id6Raw =
        (cloudPart['id6'] ??
                cloudPart['deviceId'] ??
                cloudPart['device_id'] ??
                '')
            .toString();
    final id6 = _normalizeDeviceId6(id6Raw) ?? _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return false;
    final now = DateTime.now();
    cloudPart['inviteId'] = inviteId;
    cloudPart['invite_id'] = inviteId;
    final payloadKeys = cloudPart.keys
        .map((e) => e.toString())
        .take(6)
        .join(',');
    final sigLen =
        (cloudPart['sig'] ?? cloudPart['sig_owner'] ?? cloudPart['sigOwner'])
            ?.toString()
            .length;
    debugPrint(
      '[JOIN][CLOUD] start inviteId=${_maskInviteId(inviteId)} id6=$id6 '
      'cloudReady=${_cloudReadyForInvite(now, id6: id6)} keys=[$payloadKeys] '
      'sigLen=${sigLen ?? 0}',
    );
    if (!_cloudReadyForInvite(now, id6: id6)) {
      _showSnack('Cloud hazır değil. Giriş yapın ve tekrar deneyin.');
      return false;
    }
    final refreshed = await _cloudRefreshIfNeeded();
    debugPrint(
      '[JOIN][CLOUD] refreshed=$refreshed authReady=${_cloudAuthReady(now)}',
    );
    if (!_cloudAuthReady(now) && !refreshed) {
      _showSnack('Cloud kimliği geçerli değil. Lütfen giriş yapın.');
      return false;
    }
    final joinRes = await cloudApi.joinInvite(
      id6,
      inviteId,
      invitePayload: cloudPart,
      userIdHash: _cloudUserIdHash(),
    );
    final ok = joinRes != null;
    final role = (joinRes?['role'] ?? '').toString();
    debugPrint(
      '[JOIN][CLOUD] result ok=$ok role=$role keys='
      '${joinRes?.keys.map((e) => e.toString()).take(8).join(",") ?? ""}',
    );
    if (ok) {
      await _ensureActiveDeviceForId6(id6);
      final prefs = await SharedPreferences.getInstance();
      await _setCloudEnabledLocalForActiveDevice(true, prefs: prefs);
      if (role.isNotEmpty) {
        await _saveCloudRole(id6, role);
        if (state != null && !_authRoleKnown(state!.authRole)) {
          state!.authRole = role.toUpperCase();
        }
      }
      final saved = _findDeviceByCanonical(id6);
      var savedChanged = false;
      if (saved != null) {
        final roleUp = role.trim().toUpperCase();
        final desiredRole = roleUp.isEmpty ? saved.cloudRole : roleUp;
        if (!saved.cloudLinked ||
            saved.cloudRole != desiredRole ||
            saved.cloudSource != 'cloud') {
          saved.cloudLinked = true;
          saved.cloudRole = desiredRole;
          saved.cloudSource = 'cloud';
          savedChanged = true;
        }
      }
      if (savedChanged) {
        await _saveDevicesToPrefs();
        _safeSetState(() {});
      }
      for (var i = 0; i < 3; i++) {
        await _syncCloudDevices(
          autoSelectIfNeeded: false,
          showSnack: false,
          force: true,
        );
        if (_cloudApiDeviceIds.contains(id6)) break;
        if (i < 2) {
          await Future.delayed(const Duration(milliseconds: 900));
        }
      }
      _startCloudPreferWindow();
      if (api.baseUrl.trim().isEmpty ||
          Uri.tryParse(api.baseUrl)?.host == 'api' ||
          Uri.tryParse(api.baseUrl)?.host == 'state') {
        await _applyProvisionedBaseUrl(
          'http://${mdnsHostForId6(id6, rawIdHint: id6)}.local',
          showSnack: false,
        );
      }
      final localPayload = Map<String, dynamic>.from(inviteObj);
      localPayload['deviceId'] = id6;
      localPayload['id6'] = id6;
      final pub = _clientPubQ65B64;
      if (pub != null && pub.isNotEmpty) {
        localPayload['user_pubkey'] = pub;
      }
      bool joinOk = false;
      if (api.baseUrl.trim().isNotEmpty) {
        joinOk = await api.joinInviteLocal(localPayload);
      }
      if (!joinOk) {
        joinOk = await _sendJoinViaCloudMqtt(id6, localPayload);
      }
      debugPrint('[JOIN][CLOUD] device JOIN sent ok=$joinOk');
      if (!joinOk) {
        _showSnack(
          'Davet kabul edildi. Cihaz listesi daha sonra güncellenecek.',
        );
        return true;
      }
      _showSnack('Davet kabul edildi (cihaz güncellendi).');
      return true;
    }
    _showSnack('Davet kabul edilemedi.');
    return false;
  }

  Future<bool> _sendJoinViaCloudMqtt(
    String id6,
    Map<String, dynamic> inviteObj,
  ) async {
    final now = DateTime.now();
    if (!_cloudReady(now) || id6.isEmpty) {
      debugPrint('[JOIN][CLOUD] mqtt skip: cloud not ready id6=$id6');
      return false;
    }
    final refreshed = await _cloudRefreshIfNeeded();
    if (!_cloudAuthReady(now) && !refreshed) {
      _markCloudFail();
      debugPrint('[JOIN][CLOUD] mqtt skip: auth not ready');
      return false;
    }
    final body = <String, dynamic>{'type': 'JOIN', 'invite': inviteObj};
    final idHash = _cloudUserIdHash();
    if (idHash != null && idHash.isNotEmpty) {
      body['userIdHash'] = idHash;
    }
    final invSigLen =
        (inviteObj['sig'] ?? inviteObj['sig_owner'] ?? inviteObj['sigOwner'])
            ?.toString()
            .length;
    debugPrint(
      '[JOIN][CLOUD] mqtt send id6=$id6 idHash=${idHash != null ? "set" : "empty"} '
      'inviteKeys=${inviteObj.keys.map((e) => e.toString()).take(8).join(",")} '
      'sigLen=${invSigLen ?? 0}',
    );
    final ok = await cloudApi.sendCommand(id6, body, kCloudCmdTimeout);
    debugPrint('[JOIN][CLOUD] mqtt JOIN sent ok=$ok');
    if (ok) {
      _markCloudOk();
    } else {
      _markCloudFail();
    }
    return ok;
  }

  Future<void> _showInviteQrAndOpenJoin(Map<String, dynamic> invite) async {
    final rawInviteId = (invite['inviteId'] ?? '').toString();
    final inviteId = _canonicalInviteId(rawInviteId);
    final role = (invite['role'] ?? 'USER').toString();
    final isCloud =
        (invite['source'] ?? invite['cloud']) == 'cloud' ||
        invite['source'] == true ||
        invite['cloud'] == true;
    debugPrint(
      '[INVITE][QR] show inviteId=${_maskInviteId(inviteId ?? rawInviteId)} role=$role isCloud=$isCloud',
    );
    if (inviteId != null && inviteId.isNotEmpty) {
      invite['inviteId'] = inviteId;
      invite['invite_id'] = inviteId;
      unawaited(
        _sendToDevice(<String, dynamic>{
          'type': 'OPEN_JOIN_WINDOW',
          'inviteId': inviteId,
          'ttl': 180,
          'role': role,
        }),
      );
      debugPrint(
        '[INVITE][QR] OPEN_JOIN_WINDOW sent inviteId=$inviteId role=$role',
      );
    } else {
      _showSnack('Geçersiz davet kimliği (inviteId).');
      return;
    }

    final signing = api.signingPrivD32;
    if (signing == null || signing.isEmpty) {
      _showSnack(
        'Owner anahtarı yok. IR ile pair/recovery penceresini açıp Bluetooth kurulumunu tekrar başlatın.',
      );
      return;
    }
    final id6 = _normalizeDeviceId6(
      (invite['deviceId'] ?? invite['device_id'] ?? invite['id6'] ?? '')
          .toString(),
    );
    final expRaw = invite['exp'];
    final exp = expRaw is int
        ? expRaw
        : int.tryParse(expRaw?.toString() ?? '') ??
              (DateTime.now()
                      .add(const Duration(minutes: 10))
                      .millisecondsSinceEpoch ~/
                  1000);
    if (inviteId != null &&
        inviteId.isNotEmpty &&
        id6 != null &&
        id6.isNotEmpty) {
      final sig = _signOwnerInvite(
        privD32: signing,
        deviceId6: id6,
        inviteId: inviteId,
        role: (role.toUpperCase() == 'GUEST') ? 'GUEST' : 'USER',
        exp: exp,
      );
      if (sig != null && sig.isNotEmpty) {
        invite['sig_owner'] = sig;
        invite['sigOwner'] = sig;
        debugPrint(
          '[INVITE][QR] sig_owner len=${sig.length} id6=$id6 exp=$exp',
        );
      }
    }

    final data = jsonEncode(invite);
    debugPrint('[INVITE][QR] payload len=${data.length}');
    if (!mounted) return;
    await _settleRouteTransition();
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _InviteQrPage(role: role, data: data),
      ),
    );
  }

  Future<bool> _ensureCameraPermissionForQr() async {
    PermissionStatus st;
    try {
      st = await Permission.camera.status;
    } catch (_) {
      st = PermissionStatus.denied;
    }

    if (st.isGranted) return true;

    if (st.isDenied) {
      try {
        st = await Permission.camera.request();
      } catch (_) {
        st = PermissionStatus.denied;
      }
      if (st.isGranted) return true;
    }

    if (!mounted) return false;

    if (st.isPermanentlyDenied || st.isRestricted) {
      final goSettings = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) {
          return AlertDialog(
            title: Text(t.literal('Kamera izni gerekli')),
            content: Text(
              'QR kod taramak için kamera izni verilmeli. '
              'Ayarlar > Gizlilik > Kamera bölümünden izin verebilirsiniz.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(t.literal('Vazgeç')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(t.literal('Ayarları aç')),
              ),
            ],
          );
        },
      );
      if (goSettings == true) {
        await openAppSettings();
      }
      return false;
    }

    _showSnack('Kamera izni gerekli.');
    return false;
  }

  Future<void> _revokeUser(String userIdHash) async {
    if (!_canControlDevice) {
      _showSnack(t.t('not_connected'));
      return;
    }
    final id = userIdHash.trim();
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.literal('Yetkiyi Kaldır')),
        content: Text('Bu kullanıcıdan kontrol yetkisi kaldırılsın mı?\n\n$id'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.literal('Vazgeç')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.literal('Kaldır')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final cmdOk = await _sendToDevice(<String, dynamic>{
      'type': 'REVOKE_USER',
      'userIdHash': id,
    });
    if (cmdOk) {
      _showSnack(t.literal('Yetki kaldırıldı.'));
    } else {
      _showSnack(t.t('command_failed'));
    }
  }

  Future<void> _joinViaApWithInviteDialog({String? initialInvite}) async {
    if (!mounted) return;
    final ctl = TextEditingController(text: initialInvite ?? '');
    final invite = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.literal('Davet JSON ile katıl')),
          content: TextField(
            controller: ctl,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'QR içeriğini buraya yapıştırın',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
              child: Text(t.literal('Katıl')),
            ),
          ],
        );
      },
    );
    if (invite == null || invite.isEmpty) return;

    try {
      debugPrint('[JOIN][AP] send len=${invite.length}');
      final uri = Uri.parse('http://192.168.4.1/join');
      final r = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: invite,
          )
          .timeout(const Duration(seconds: 8));
      debugPrint('[JOIN][AP] http status=${r.statusCode} body=${r.body}');
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final obj = jsonDecode(r.body);
        if (obj is Map<String, dynamic> && obj['ok'] == true) {
          _showSnack('Davetle cihaza katılım başarılı.');
          return;
        }
      }
      _showSnack('Katılım başarısız: HTTP ${r.statusCode}');
    } catch (e, st) {
      debugPrint('[JOIN][AP] error: $e');
      debugPrint(st.toString());
      _showSnack('Katılım hatası: $e');
    }
  }

  Future<void> _startApRescueFromOwner() async {
    if (!_canControlDevice) return;
    _showSnack('Kurtarma AP başlatılıyor...');
    final ok = await _sendToDevice(<String, dynamic>{
      'type': 'AP_START',
      'ttl': 600,
    });
    if (!mounted) return;
    if (!ok) {
      _showSnack(t.t('command_failed'));
    } else {
      final brand = _inviteBrandLabel();
      _showSnack(
        'AP kurtarma modu açıldı. Telefondan "${brand}_AP_xxxx" ağına bağlanın.',
      );
    }
  }

  Future<void> _scanInviteQrAndJoinViaAp() async {
    await _joinViaApWithInviteDialog();
  }
}
