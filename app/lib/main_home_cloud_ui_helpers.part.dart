part of 'main.dart';

extension _HomeScreenCloudUiHelpersPart on _HomeScreenState {
  String _formatIntegrationScopes(dynamic raw) {
    if (raw is List) {
      final scopes = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      if (scopes.isNotEmpty) return scopes.join(', ');
    }
    final s = raw?.toString().trim() ?? '';
    return s.isEmpty ? 'device:read' : s;
  }

  Future<void> _cloudCreateIntegrationLink() async {
    final now = DateTime.now();
    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return;
    if (!_cloudLoggedIn()) return;
    if (!_cloudReady(now)) return;

    final idCtl = TextEditingController();
    bool readScope = true;
    bool writeScope = false;
    bool adminScope = false;
    String ttlChoice = '30';
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              title: Text(t.literal('Integration link oluştur')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: idCtl,
                      decoration: const InputDecoration(
                        labelText: 'Integration ID',
                        hintText: 'homeassistant-main',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Scopes'),
                    CheckboxListTile(
                      value: readScope,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('device:read'),
                      onChanged: (v) {
                        setLocalState(() {
                          readScope = v ?? true;
                        });
                      },
                    ),
                    CheckboxListTile(
                      value: writeScope,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('device:write'),
                      onChanged: (v) {
                        setLocalState(() {
                          writeScope = v ?? false;
                        });
                      },
                    ),
                    CheckboxListTile(
                      value: adminScope,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('device:admin'),
                      onChanged: (v) {
                        setLocalState(() {
                          adminScope = v ?? false;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: ttlChoice,
                      decoration: const InputDecoration(labelText: 'Süre'),
                      items: [
                        DropdownMenuItem(
                          value: '7',
                          child: Text(t.literal('7 gün')),
                        ),
                        DropdownMenuItem(
                          value: '30',
                          child: Text(t.literal('30 gün')),
                        ),
                        DropdownMenuItem(
                          value: '90',
                          child: Text(t.literal('90 gün')),
                        ),
                        DropdownMenuItem(
                          value: '365',
                          child: Text(t.literal('365 gün')),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocalState(() {
                          ttlChoice = v;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(t.literal('Vazgeç')),
                ),
                FilledButton(
                  onPressed: () {
                    final integrationId = idCtl.text.trim();
                    final scopes = <String>[
                      if (readScope) 'device:read',
                      if (writeScope) 'device:write',
                      if (adminScope) 'device:admin',
                    ];
                    Navigator.of(ctx).pop(<String, dynamic>{
                      'integrationId': integrationId,
                      'scopes': scopes,
                      'ttlSec': (int.tryParse(ttlChoice) ?? 30) * 24 * 3600,
                    });
                  },
                  child: Text(t.literal('Oluştur')),
                ),
              ],
            );
          },
        );
      },
    );
    idCtl.dispose();

    if (created == null) return;
    final integrationId = (created['integrationId'] ?? '').toString().trim();
    final scopes = (created['scopes'] is List)
        ? (created['scopes'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final ttlSec = (created['ttlSec'] as int?) ?? (30 * 24 * 3600);
    if (integrationId.isEmpty) {
      _showSnack('Integration ID gerekli');
      return;
    }
    if (scopes.isEmpty) {
      _showSnack('En az bir scope seçin');
      return;
    }

    final refreshed = await _cloudRefreshIfNeeded();
    if (!_cloudAuthReady(now) && !refreshed) {
      if (!mounted) return;
      _showSnack('Cloud oturum gerekli');
      return;
    }
    final res = await cloudApi.createIntegrationLink(
      id6,
      integrationId: integrationId,
      scopes: scopes,
      ttlSec: ttlSec,
      timeout: const Duration(seconds: 8),
    );
    if (!mounted) return;
    if (res == null) {
      _showSnack('Integration link oluşturulamadı');
      return;
    }
    _showSnack('Integration link oluşturuldu');
    await _refreshCloudIntegrations(force: true);
  }

  Future<void> _cloudRevokeIntegration(String integrationId) async {
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
      final res = await cloudApi.revokeIntegrationLink(id6, integrationId);
      if (!mounted) return;
      if (res == null) {
        _showSnack('Integration revoke başarısız');
        return;
      }
      _showSnack('Integration revoke edildi');
      await _refreshCloudIntegrations(force: true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Integration revoke hata: $e');
    }
  }

  Future<bool> _autoCloudAclRecovery({
    bool force = false,
    String reason = '',
  }) async {
    final now = DateTime.now();
    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return false;
    if (!_cloudLoggedIn()) return false;
    if (!_cloudEnabledEffective()) return false;
    if (!_isOwnerRole()) return false;
    if (!_cloudReady(now)) return false;
    if (_cloudAclAutoInFlight) return false;
    if (!force &&
        _cloudAclAutoNextAt != null &&
        now.isBefore(_cloudAclAutoNextAt!)) {
      return false;
    }

    _cloudAclAutoInFlight = true;
    bool pushOk = false;
    try {
      final refreshed = await _cloudRefreshIfNeeded();
      if (!_cloudAuthReady(now) && !refreshed) {
        _cloudAclAutoNextAt = DateTime.now().add(const Duration(seconds: 45));
        return false;
      }

      // Keep cloud-side lists warm so owner can recover even when UI buttons are hidden.
      await _refreshCloudMembers(force: true);
      await _refreshCloudInvites(force: true);
      await _refreshCloudIntegrations(force: true);

      final res = await cloudApi.pushAcl(
        id6,
        timeout: const Duration(seconds: 8),
      );
      pushOk = res != null && (res['ok'] == true || res['pushed'] == true);
      final ver = (res?['version'] ?? '').toString().trim();
      final users = (res?['userCount'] ?? res?['user_count'] ?? 0);
      final err = (res?['reason'] ?? res?['err'] ?? res?['error'] ?? '')
          .toString()
          .trim();
      debugPrint(
        '[CLOUD][ACL][AUTO] reason=$reason id6=$id6 ok=$pushOk '
        'version=${ver.isEmpty ? "-" : ver} users=$users '
        'err=${err.isEmpty ? "-" : err}',
      );
      _cloudAclAutoNextAt = DateTime.now().add(
        pushOk ? const Duration(minutes: 2) : const Duration(seconds: 45),
      );
      return pushOk;
    } catch (e) {
      debugPrint('[CLOUD][ACL][AUTO] exception reason=$reason err=$e');
      _cloudAclAutoNextAt = DateTime.now().add(const Duration(seconds: 45));
      return false;
    } finally {
      _cloudAclAutoInFlight = false;
    }
  }

  Future<bool> _sendCloudCommandWithRecovery({
    required String id6,
    required Map<String, dynamic> body,
    required String reason,
  }) async {
    final bodyWithIdentity = Map<String, dynamic>.from(body);
    final userIdHash = _cloudUserIdHash();
    if ((bodyWithIdentity['userIdHash'] ?? '').toString().trim().isEmpty &&
        userIdHash != null &&
        userIdHash.isNotEmpty) {
      bodyWithIdentity['userIdHash'] = userIdHash;
    }
    debugPrint(
      '[CLOUD][CMD] reason=$reason id6=$id6 userIdHash='
      '${(bodyWithIdentity['userIdHash'] ?? '').toString().isNotEmpty ? 'set' : 'empty'}',
    );

    final authRole = (state?.authRole ?? '').trim().toUpperCase();
    final cloudRole = (_activeDevice?.cloudRole ?? '').trim().toUpperCase();
    final nonOwnerRole =
        authRole == 'USER' ||
        authRole == 'GUEST' ||
        cloudRole == 'USER' ||
        cloudRole == 'GUEST';
    final tryDesiredPath = nonOwnerRole
        ? false
        : (_cloudFeatureShadowDesired ?? true);
    if (nonOwnerRole) {
      debugPrint(
        '[CLOUD][CMD] force /cmd path for non-owner role auth=$authRole cloud=$cloudRole',
      );
    }

    final ok = await cloudApi.sendCommand(
      id6,
      bodyWithIdentity,
      kCloudCmdTimeout,
      tryDesired: tryDesiredPath,
    );
    if (ok) {
      _markCloudOk();
      return true;
    }

    if (_isMembershipCloudFailure()) {
      debugPrint(
        '[CLOUD][MEMBERSHIP] command denied id6=$id6 '
        'status=${cloudApi.lastCmdHttpStatus ?? "-"} '
        'err=${cloudApi.lastCmdError ?? "-"} '
        'msg=${cloudApi.lastCmdReason ?? "-"}',
      );
      final canClaim = await _cloudClaimAllowed(
        source: 'membership_auto_repair',
        refreshLocalState: true,
      );
      if (!canClaim) {
        _markCloudFail();
        return false;
      }
      final pairToken = await _resolveActivePairToken();
      final userIdHash = _cloudUserIdHash();
      bool repaired = false;
      if (pairToken != null && pairToken.isNotEmpty) {
        repaired = await cloudApi.claimDeviceWithAutoSync(
          id6,
          const Duration(seconds: 8),
          claimSecret: pairToken,
          userIdHash: userIdHash,
          ownerPubKeyB64: _cloudOwnerPubKeyB64(),
          deviceBrand: _activeDevice?.brand,
          deviceSuffix: _activeDevice?.suffix,
        );
        if (!repaired) {
          final claimErr = (cloudApi.lastClaimError ?? '').trim().toLowerCase();
          final canRecover =
              claimErr == 'already_claimed' ||
              claimErr == 'claim_proof_mismatch';
          if (canRecover) {
            repaired = await cloudApi.recoverOwnership(
              id6,
              const Duration(seconds: 8),
              claimSecret: pairToken,
              userIdHash: userIdHash,
              ownerPubKeyB64: _cloudOwnerPubKeyB64(),
              deviceBrand: _activeDevice?.brand,
              deviceSuffix: _activeDevice?.suffix,
            );
          }
        }
      }
      debugPrint(
        '[CLOUD][MEMBERSHIP][AUTO] reason=$reason repaired=$repaired '
        'claimErr=${cloudApi.lastClaimError ?? "-"} '
        'claimStatus=${cloudApi.lastClaimHttpStatus ?? "-"}',
      );
      if (repaired) {
        await _syncCloudDevices(autoSelectIfNeeded: false, showSnack: false);
        final retryOk = await cloudApi.sendCommand(
          id6,
          bodyWithIdentity,
          kCloudCmdTimeout,
          tryDesired: tryDesiredPath,
        );
        if (retryOk) {
          _markCloudOk();
          return true;
        }
      }
      _markCloudFail();
      return false;
    }

    if (_isUserIdHashRequiredCloudFailure()) {
      final cloudReason = (state?.cloudStateReason ?? '').trim().toLowerCase();
      if (cloudReason == 'no_endpoint') {
        debugPrint(
          '[CLOUD][IDENTITY][AUTO] skip repair reason=$reason cloudReason=no_endpoint',
        );
        return false;
      }
      if (!(await _cloudClaimAllowed(
        source: 'identity_auto_repair',
        refreshLocalState: true,
      ))) {
        return false;
      }
      final pairToken = await _resolveActivePairToken();
      final userIdHash = _cloudUserIdHash();
      bool repaired = false;
      if (pairToken != null &&
          pairToken.isNotEmpty &&
          userIdHash != null &&
          userIdHash.isNotEmpty) {
        repaired = await cloudApi.claimDeviceWithAutoSync(
          id6,
          const Duration(seconds: 6),
          claimSecret: pairToken,
          userIdHash: userIdHash,
          ownerPubKeyB64: _cloudOwnerPubKeyB64(),
          deviceBrand: _activeDevice?.brand,
          deviceSuffix: _activeDevice?.suffix,
        );
      }
      debugPrint(
        '[CLOUD][IDENTITY][AUTO] reason=$reason repaired=$repaired '
        'claimErr=${cloudApi.lastClaimError ?? "-"} '
        'claimStatus=${cloudApi.lastClaimHttpStatus ?? "-"}',
      );
      if (repaired) {
        final retryOk = await cloudApi.sendCommand(
          id6,
          bodyWithIdentity,
          kCloudCmdTimeout,
          tryDesired: _cloudFeatureShadowDesired ?? true,
        );
        if (retryOk) {
          _markCloudOk();
          return true;
        }
      }
    }

    final aclLikeFailure = _isAclLikeCloudFailure();
    if (!aclLikeFailure) {
      debugPrint(
        '[CLOUD][ACL][AUTO] skip reason=$reason '
        'status=${cloudApi.lastCmdHttpStatus ?? "-"} '
        'err=${cloudApi.lastCmdError ?? "-"} '
        'msg=${cloudApi.lastCmdReason ?? "-"}',
      );
      _markCloudFail();
      return false;
    }

    final recovered = await _autoCloudAclRecovery(
      force: true,
      reason: 'cmd_fail:$reason',
    );
    if (!recovered) return false;

    final retryOk = await cloudApi.sendCommand(
      id6,
      bodyWithIdentity,
      kCloudCmdTimeout,
      tryDesired: _cloudFeatureShadowDesired ?? true,
    );
    if (retryOk) {
      debugPrint('[CLOUD][ACL][AUTO] retry ok reason=$reason');
      _markCloudOk();
      return true;
    }
    _markCloudFail();
    return false;
  }

  bool _isUserIdHashRequiredCloudFailure() {
    final err = (cloudApi.lastCmdError ?? '').toLowerCase();
    final reason = (cloudApi.lastCmdReason ?? '').toLowerCase();
    final haystack = '$err $reason';
    return haystack.contains('user_id_hash_required') ||
        haystack.contains('useridhashrequired') ||
        haystack.contains('user_id_hash');
  }

  bool _isAclLikeCloudFailure() {
    final status = cloudApi.lastCmdHttpStatus;
    if (status == 401 || status == 403 || status == 409 || status == 423) {
      return true;
    }
    final err = (cloudApi.lastCmdError ?? '').toLowerCase();
    final reason = (cloudApi.lastCmdReason ?? '').toLowerCase();
    final haystack = '$err $reason';
    const needles = <String>[
      'acl',
      'role',
      'owner',
      'forbidden',
      'not_authorized',
      'not authorized',
      'unauthorized',
      'permission',
      'denied',
      'policy',
      'auth_required',
      'useridhash',
      'user_id_hash',
    ];
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }

  bool _isMembershipCloudFailure() {
    final err = (cloudApi.lastCmdError ?? '').toLowerCase();
    final reason = (cloudApi.lastCmdReason ?? '').toLowerCase();
    final path = (cloudApi.lastCmdPath ?? '').toLowerCase();
    final haystack = '$err $reason $path';
    return haystack.contains('not_member') ||
        haystack.contains('not member') ||
        haystack.contains('not_owner') ||
        haystack.contains('not owner') ||
        haystack.contains('member_required') ||
        haystack.contains('owner_required');
  }

  String? _cloudCmdFailureMessage() {
    final path = cloudApi.lastCmdPath;
    if (path == null || path.isEmpty) return null;
    final status = cloudApi.lastCmdHttpStatus;
    final err = (cloudApi.lastCmdError ?? '').trim();
    final reason = (cloudApi.lastCmdReason ?? '').trim();
    final details = <String>[];
    if (status != null) details.add('HTTP $status');
    if (err.isNotEmpty) details.add(err);
    if (reason.isNotEmpty && reason.toLowerCase() != err.toLowerCase()) {
      details.add(reason);
    }

    final lc = '${err.toLowerCase()} ${reason.toLowerCase()}';
    final isTr = t.code == 'tr';

    bool hasAny(Iterable<String> needles) {
      for (final n in needles) {
        if (lc.contains(n)) return true;
      }
      return false;
    }

    String friendly;
    if (status == 401 ||
        hasAny(const ['unauthorized', 'auth_required', 'token', 'expired'])) {
      friendly = isTr
          ? 'Cloud oturumu geçersiz. Lütfen tekrar giriş yapın.'
          : 'Cloud session is invalid. Please sign in again.';
    } else if (hasAny(const [
      'not_member',
      'not member',
      'not_owner',
      'not owner',
      'member_required',
      'owner_required',
    ])) {
      friendly = isTr
          ? 'Seçili cihaz bu cloud hesabına bağlı değil veya bu hesapta yetkiniz yok.'
          : 'The selected device is not linked to this cloud account or your account is not authorized.';
    } else if (status == 403 ||
        hasAny(const [
          'forbidden',
          'permission',
          'denied',
          'owner',
          'role',
          'acl',
          'useridhash',
          'user_id_hash',
        ])) {
      friendly = isTr
          ? 'Cloud yetkisi yetersiz. Owner/ACL senkronu gerekiyor olabilir.'
          : 'Cloud permission denied. Owner/ACL sync may be required.';
    } else if (status == 429 || hasAny(const ['rate', 'throttle'])) {
      friendly = isTr
          ? 'Cloud istek limiti aşıldı. Kısa süre sonra tekrar deneyin.'
          : 'Cloud rate limit reached. Please try again shortly.';
    } else if ((status != null && status >= 500) ||
        hasAny(const [
          'timeout',
          'network_error',
          'internal',
          'unavailable',
          'upstream',
          'gateway',
        ])) {
      friendly = isTr
          ? 'Cloud servisi geçici olarak yanıt vermiyor.'
          : 'Cloud service is temporarily unavailable.';
    } else {
      friendly = isTr
          ? 'Cloud komutu işlenemedi.'
          : 'Cloud command could not be processed.';
    }

    if (details.isEmpty) return 'Cloud: $friendly';
    return 'Cloud: $friendly (${details.join(' | ')})';
  }
}
