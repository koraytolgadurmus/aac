part of 'main.dart';

extension _HomeScreenUiSettingsPart on _HomeScreenState {
  Widget _buildSettingsImpl() {
    final s = state;
    final redWarn = (s?.filterAlert ?? false) || (lastFilterMsg == 'BAD');
    final cloudOnlyMode =
        _cloudEnabledEffective() &&
        _cloudCommandEligibleForActive() &&
        !_localFallbackAvailableForUi();
    final showAdvanced = _showAdvancedSettings;
    final visibleCloudMembers = _visibleCloudMembers();
    final visibleCloudInvites = _visibleCloudInvites();

    return SingleChildScrollView(
      // Dikey boşlukları minimuma çek (2px üst/alt)
      padding: const EdgeInsets.fromLTRB(16, 1, 16, 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.literal('Baglanti ve Kurulum'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (cloudOnlyMode) ...[
                    const SizedBox(height: 6),
                    Text(
                      t.literal(
                        'Cloud aktif, ancak bu cihaz için yerel fallback yok. Bu yüzden sadece cloud kontrolleri gösteriliyor.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else if (_cloudEnabledEffective() &&
                      _cloudCommandEligibleForActive()) ...[
                    const SizedBox(height: 6),
                    Text(
                      t.literal(
                        'Cloud aktif. MQTT öncelikli kullanılır; cloud erişilemezse local/BLE/AP fallback denenir.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (showAdvanced) ...[
                    TextField(
                      controller: _urlCtl,
                      enabled: !cloudOnlyMode,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'http://192.168.4.1',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: cloudOnlyMode
                              ? null
                              : () async {
                                  String v = _urlCtl.text.trim();
                                  final normalized = _normalizeBaseUrl(v);
                                  if (normalized == null) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            t.t('invalid_base_url'),
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  baseUrl = normalized;
                                  api.baseUrl = baseUrl;
                                  final p =
                                      await SharedPreferences.getInstance();
                                  await p.setString('baseUrl', baseUrl);
                                  await _updateActiveDeviceBaseUrl(baseUrl);
                                  _allowNetworkAutoPolling();
                                  _startPolling();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${t.t('base_url_saved')}: $baseUrl',
                                        ),
                                      ),
                                    );
                                  }
                                },
                          child: Text(t.t('save')),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: cloudOnlyMode
                              ? null
                              : () async {
                                  final ok = await api.testConnection();
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${ok ? t.t('reachable_yes') : t.t('reachable_no')}  [${api.baseUrl}]',
                                      ),
                                    ),
                                  );
                                  _safeSetState(() => connected = ok);
                                },
                          child: Text(t.t('test')),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(
                      t.literal(
                        'Hızlı kurulum: 1) Bluetooth ile cihaza bağlan  2) Soft recovery aç  3) AP ile kurulumdan ev Wi‑Fi bilgilerini gönder.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (!cloudOnlyMode) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _claimFlowStage == _ClaimFlowStage.claimed
                                ? Icons.verified_user
                                : (_claimFlowStage == _ClaimFlowStage.failed
                                      ? Icons.error_outline
                                      : Icons.sync),
                            size: 18,
                            color: _claimFlowColor(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _claimFlowTitle(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _claimFlowColor(context),
                                  ),
                                ),
                                if ((_claimFlowDetail ?? '').trim().isNotEmpty)
                                  Text(
                                    _claimFlowDetail!,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                if (_claimFlowUpdatedText().isNotEmpty)
                                  Text(
                                    _claimFlowUpdatedText(),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _claimFlowBusy
                                ? null
                                : _retryOwnerClaimFlow,
                            child: Text(
                              _claimFlowBusy
                                  ? t.literal('Bekle...')
                                  : t.literal('Yeniden dene'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!cloudOnlyMode)
                        FilledButton.icon(
                          onPressed: _openBleManageAndProvision,
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text(
                            _bleControlMode
                                ? t.literal('Kurulum sihirbazı (Bağlı)')
                                : t.literal('Kurulum sihirbazını başlat'),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: _openApProvision,
                        icon: const Icon(Icons.wifi_tethering),
                        label: Text(t.literal('AP ile kurulum')),
                      ),
                      if (!cloudOnlyMode && showAdvanced)
                        OutlinedButton.icon(
                          onPressed: _openManualClaimSecretRecovery,
                          icon: const Icon(Icons.key),
                          label: Text(t.literal('Doğrulama kodu (ileri)')),
                        ),
                      if (!cloudOnlyMode && showAdvanced)
                        OutlinedButton.icon(
                          onPressed: _resetPairTokenForActiveDevice,
                          icon: const Icon(Icons.restart_alt),
                          label: Text(t.literal('Cihazi yeniden eslestir')),
                        ),
                      if (!cloudOnlyMode && showAdvanced)
                        OutlinedButton.icon(
                          onPressed: _factoryResetActiveDevice,
                          icon: const Icon(Icons.restore),
                          label: Text(t.literal('Fabrika ayarina don')),
                        ),
                      if (!cloudOnlyMode && showAdvanced)
                        OutlinedButton.icon(
                          onPressed: _toggleApControl,
                          icon: const Icon(Icons.wifi),
                          label: Text(t.literal('AP ile Yonet')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.literal('Cloud Bağlantı'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        _cloudLoggedIn()
                            ? Icons.verified_user
                            : Icons.person_outline,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _cloudLoggedIn()
                              ? '${t.literal('Giriş')}: ${_cloudUserEmail ?? 'ok'}'
                              : t.literal('Cloud girişi yapılmadı'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!_cloudLoggedIn())
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _handleCloudLoginSuccess(
                              signup: false,
                              promptPicker: true,
                            );
                          },
                          icon: const Icon(Icons.login),
                          label: Text(t.literal('Giriş')),
                        ),
                      if (!_cloudLoggedIn())
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _handleCloudLoginSuccess(
                              signup: true,
                              promptPicker: true,
                            );
                          },
                          icon: const Icon(Icons.app_registration),
                          label: Text(t.literal('Kayıt')),
                        ),
                      if (!_cloudLoggedIn())
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _openCloudConfirmDialog();
                          },
                          icon: const Icon(Icons.mark_email_read_outlined),
                          label: Text(t.literal('Doğrulama kodu')),
                        ),
                      if (!_cloudLoggedIn())
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _startCloudForgotPasswordFlow();
                          },
                          icon: const Icon(Icons.lock_reset),
                          label: Text(t.literal('Şifremi unuttum')),
                        ),
                      OutlinedButton.icon(
                        onPressed: _cloudLoggedIn() ? _cloudLogout : null,
                        icon: const Icon(Icons.logout),
                        label: Text(t.literal('Çıkış')),
                      ),
                      if (_cloudLoggedIn() &&
                          (_isOwnerRole() ||
                              !_activeDeviceOwnedByCurrentCloudUser()))
                        FilledButton.icon(
                          onPressed: () async {
                            final id6 = await _resolveDeviceId6ForCloudAction();
                            if (id6 == null || id6.isEmpty) {
                              _showSnack('Cihaz ID bulunamadı');
                              return;
                            }
                            if (!_cloudLoggedIn()) {
                              _showSnack('Önce cloud girişi yapın');
                              return;
                            }
                            final isClaimed =
                                _activeDeviceOwnedByCurrentCloudUser();
                            if (isClaimed) {
                              if (!mounted) return;
                              final okConfirm =
                                  await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Sahipliği Kaldır'),
                                      content: const Text(
                                        'Bu cihaz bu hesaptan ayrılacak. Devretmek istediğinize emin misiniz?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(false),
                                          child: Text(t.literal('Vazgeç')),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(true),
                                          child: Text(t.literal('Kaldır')),
                                        ),
                                      ],
                                    ),
                                  ) ??
                                  false;
                              if (!okConfirm) return;
                              if (!mounted) return;
                              var verifyInput = '';
                              final verifyOk =
                                  await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text(
                                        'Son Onay (Cloud Kaldırma)',
                                      ),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Cloud sahipliğini kaldırmak için cihaz kodunu yazın: $id6',
                                          ),
                                          const SizedBox(height: 10),
                                          TextField(
                                            onChanged: (v) =>
                                                verifyInput = v.trim(),
                                            decoration: const InputDecoration(
                                              hintText: 'Örn: 693133',
                                            ),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(false),
                                          child: Text(t.literal('Vazgeç')),
                                        ),
                                        FilledButton(
                                          onPressed: () {
                                            final okTyped = verifyInput == id6;
                                            Navigator.of(ctx).pop(okTyped);
                                          },
                                          child: Text(t.literal('Doğrula')),
                                        ),
                                      ],
                                    ),
                                  ) ??
                                  false;
                              if (!verifyOk) {
                                _showSnack(
                                  'Kod doğrulanmadı, cloud kaldırma iptal.',
                                );
                                return;
                              }
                              await _cloudRefreshIfNeeded();
                              final ok = await cloudApi.unclaimDevice(
                                id6,
                                const Duration(seconds: 6),
                              );
                              if (ok) {
                                await _syncCloudDevices(
                                  autoSelectIfNeeded: false,
                                  showSnack: false,
                                );
                              }
                              if (!mounted) return;
                              if (ok && state != null) {
                                state!.ownerExists = false;
                                state!.ownerSetupDone = false;
                                state!.cloudClaimed = false;
                                _safeSetState(() {});
                              }
                              _showSnack(
                                ok
                                    ? 'Sahiplik kaldırıldı (id6=$id6)'
                                    : 'Sahiplik kaldırılamadı',
                              );
                              return;
                            }
                            await _cloudRefreshIfNeeded();
                            final claimSecret = await _resolveActivePairToken();
                            if (claimSecret == null || claimSecret.isEmpty) {
                              _showSnack(
                                'Cloud sahiplik için cihaz doğrulama kodu bulunamadı. '
                                'Önce BLE üzerinden yeniden eşleştirin veya "Doğrulama kodu (ileri)" ile kodu girin.',
                              );
                              return;
                            }
                            if (!(await _cloudClaimAllowed(
                              source: 'manual_claim_button',
                              refreshLocalState: true,
                            ))) {
                              _showSnack(
                                'Cloud endpoint ayarlı değil. Önce firmware cloud secretlarını yükleyin.',
                              );
                              return;
                            }
                            final ok = await cloudApi.claimDeviceWithAutoSync(
                              id6,
                              const Duration(seconds: 6),
                              claimSecret: claimSecret,
                              userIdHash: _cloudUserIdHash(),
                              ownerPubKeyB64: _cloudOwnerPubKeyB64(),
                              deviceBrand: _activeDevice?.brand,
                              deviceSuffix: _activeDevice?.suffix,
                            );
                            if (ok) {
                              await _syncCloudDevices(
                                autoSelectIfNeeded: false,
                                showSnack: false,
                              );
                            }
                            if (!mounted) return;
                            if (ok && state != null) {
                              state!.cloudClaimed = true;
                              _safeSetState(() {});
                            }
                            if (ok) {
                              _showSnack(
                                'Cihazı sahiplenme başarılı (id6=$id6)',
                              );
                            } else {
                              final err = (cloudApi.lastClaimError ?? '')
                                  .trim();
                              if ((err == 'already_claimed' ||
                                      err == 'claim_proof_mismatch') &&
                                  claimSecret.isNotEmpty) {
                                final recovered =
                                    await _promptCloudOwnershipRecovery(
                                      id6: id6,
                                      claimSecret: claimSecret,
                                      userIdHash: _cloudUserIdHash(),
                                    );
                                if (recovered) {
                                  if (!mounted) return;
                                  if (state != null) {
                                    state!.cloudClaimed = true;
                                    _safeSetState(() {});
                                  }
                                  final setupCreds =
                                      await _loadBleSetupCredsForId6(id6);
                                  final setupUser = (setupCreds?['user'] ?? '')
                                      .trim();
                                  final setupPass = (setupCreds?['pass'] ?? '')
                                      .trim();
                                  if (setupUser.isNotEmpty &&
                                      setupPass.isNotEmpty) {
                                    await _maybeFinalizeLocalOwnerAfterCloudClaim(
                                      id6: id6,
                                      setupUser: setupUser,
                                      setupPass: setupPass,
                                      source: 'manual_claim_recovery',
                                    );
                                  }
                                  return;
                                }
                              }
                              if (err == 'claim_proof_mismatch') {
                                await _invalidateActiveClaimToken(reason: err);
                              }
                              _showSnack(_cloudClaimErrorMessage(err));
                            }
                          },
                          icon: const Icon(Icons.link),
                          label: Text(
                            (_activeDeviceOwnedByCurrentCloudUser())
                                ? 'Sahipligi Kaldir'
                                : 'Cihazi Sahiplen',
                          ),
                        ),
                      if (showAdvanced) ...[
                        OutlinedButton.icon(
                          onPressed: () async {
                            final id6 = await _resolveDeviceId6ForCloudAction();
                            if (id6 == null || id6.isEmpty) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cihaz ID bulunamadı'),
                                ),
                              );
                              return;
                            }
                            if (!_cloudLoggedIn()) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Önce cloud girişi yapın'),
                                ),
                              );
                              return;
                            }
                            await _cloudRefreshIfNeeded();
                            final ok = await cloudApi.testConnection(
                              id6,
                              kCloudConnectTimeout,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Cloud reachable (id6=$id6)'
                                      : 'Cloud unreachable (id6=$id6)',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.wifi_tethering),
                          label: Text(t.literal('Cloud Test')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            if (!_cloudLoggedIn()) {
                              _showSnack('Önce cloud girişi yapın');
                              return;
                            }
                            final devices = await _syncCloudDevices(
                              autoSelectIfNeeded: _activeDevice == null,
                              showSnack: false,
                            );
                            if (!mounted) return;
                            _safeSetState(() {});
                            _showSnack(
                              'Cloud sync tamamlandı · state=${_cloudStateLabel()} · devices=${devices ?? _cloudApiDeviceCount ?? 0}',
                            );
                          },
                          icon: const Icon(Icons.sync),
                          label: Text(t.literal('Cloud Sync')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final id6 = await _resolveDeviceId6ForCloudAction();
                            if (id6 == null || id6.isEmpty) {
                              _showSnack('Cihaz ID bulunamadı');
                              return;
                            }
                            if (!_cloudLoggedIn()) {
                              _showSnack('Önce cloud girişi yapın');
                              return;
                            }
                            final ok = await cloudApi.sendDesiredState(
                              id6,
                              <String, dynamic>{
                                'appDebugPing': true,
                                'appDebugTs':
                                    DateTime.now().millisecondsSinceEpoch,
                              },
                              const Duration(seconds: 6),
                              allowFallbackCmd: true,
                            );
                            if (!mounted) return;
                            _showSnack(
                              ok
                                  ? 'Desired ping gönderildi (id6=$id6)'
                                  : 'Desired ping gönderilemedi',
                            );
                          },
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: Text(t.literal('Desired Ping')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final id6 = await _resolveDeviceId6ForCloudAction();
                            if (id6 == null || id6.isEmpty) {
                              _showSnack('Cihaz ID bulunamadı');
                              return;
                            }
                            if (!_cloudLoggedIn()) {
                              _showSnack('Önce cloud girişi yapın');
                              return;
                            }
                            await _cloudRefreshIfNeeded();
                            final caps = await cloudApi.fetchCapabilities(
                              id6,
                              const Duration(seconds: 8),
                            );
                            if (!mounted) return;
                            if (caps == null) {
                              _showSnack('Capabilities alınamadı');
                              return;
                            }
                            final rawCaps = caps['capabilities'];
                            if (rawCaps is Map) {
                              _cloudCapabilities = Map<String, dynamic>.from(
                                rawCaps,
                              );
                            } else {
                              _cloudCapabilities = null;
                            }
                            _cloudCapabilitiesSchema =
                                (caps['schemaVersion'] ?? '').toString();
                            _cloudCapabilitiesSource = (caps['source'] ?? '')
                                .toString();
                            _cloudCapabilitiesFetchedAt = DateTime.now();
                            _safeSetState(() {});
                            _showSnack(
                              'Capabilities alındı · schema=${_cloudCapabilitiesSchema ?? "-"} · source=${_cloudCapabilitiesSource ?? "-"}',
                            );
                          },
                          icon: const Icon(Icons.extension_outlined),
                          label: Text(t.literal('Capabilities')),
                        ),
                      ],
                    ],
                  ),
                  if (_cloudLoggedIn()) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          'Bekleyen paylaşımlar',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _cloudPendingInvitesLoading
                              ? null
                              : () => _refreshPendingCloudInvites(force: true),
                          icon: const Icon(Icons.refresh),
                          label: Text(t.literal('Yenile')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_cloudPendingInvitesLoading)
                      Text(t.literal('Paylaşımlar yükleniyor...')),
                    if (!_cloudPendingInvitesLoading &&
                        (_cloudPendingInvites == null ||
                            _cloudPendingInvites!.isEmpty))
                      Text(
                        _cloudPendingInvitesErr == null
                            ? 'Bu hesap için bekleyen paylaşım yok.'
                            : 'Bekleyen paylaşımlar alınamadı.',
                      ),
                    if ((_cloudPendingInvites?.isNotEmpty ?? false))
                      Column(
                        children: [
                          for (final item in _cloudPendingInvites!)
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${(item['role'] ?? 'USER').toString().trim().toUpperCase()} • Cihaz ${(item['deviceId'] ?? item['id6'] ?? '').toString().trim()}',
                                    ),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: () =>
                                        _acceptPendingCloudInvite(item),
                                    child: Text(t.literal('Kabul et')),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.literal('Cloud’u Aç')),
                    subtitle: Text(_cloudSetupSubtitle()),
                    value: _cloudUserEnabledLocal,
                    onChanged: _isOwnerRole() && !_cloudSetupInFlight
                        ? (v) async {
                            if (!v) {
                              final okDisable =
                                  await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(t.literal('Cloud’u Kapat')),
                                      content: Text(
                                        t.literal(
                                          'Cloud kapanırsa uzaktan kontrol durur. Sadece yerel/BLE ile yönetebilirsiniz. Devam edilsin mi?',
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(false),
                                          child: Text(t.literal('Vazgeç')),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(true),
                                          child: Text(t.literal('Kapat')),
                                        ),
                                      ],
                                    ),
                                  ) ??
                                  false;
                              if (!okDisable) return;
                              _armCloudDisableIntent();
                            }
                            final previous = _cloudUserEnabledLocal;
                            if (v) {
                              _cloudManualDisableUntil = null;
                              _startCloudPreferWindow();
                              _cloudSetupTerminalError = null;
                              _cloudSetupStatus = 'Cloud aciliyor...';
                            } else {
                              _cloudManualDisableUntil = DateTime.now().add(
                                const Duration(minutes: 10),
                              );
                              _cloudPreferUntil = null;
                              _lastCloudOkAt = null;
                              _cloudFailUntil = null;
                              _cloudSetupTerminalError = null;
                              _cloudSetupStatus = null;
                            }
                            final p = await SharedPreferences.getInstance();
                            await _setCloudEnabledLocalForActiveDevice(
                              v,
                              prefs: p,
                            );
                            if (mounted) {
                              _safeSetState(() {});
                            }
                            if (v && _cloudEndpointMissingForActive()) {
                              await _setCloudEnabledLocalForActiveDevice(
                                previous,
                                prefs: p,
                              );
                              if (mounted) {
                                _safeSetState(() {});
                              }
                              _cloudSetupTerminalError = 'no_endpoint';
                              _cloudSetupStatus =
                                  'Cloud endpoint ayarlı değil (firmware cloud secret eksik).';
                              _showSnack(
                                'Cloud endpoint ayarlı değil. Önce firmware tarafında AWS IoT endpoint/cert ayarlarını tamamlayın.',
                              );
                              return;
                            }
                            final cloudPayload = <String, dynamic>{
                              'enabled': v,
                            };
                            final endpoint =
                                _effectiveCloudEndpointNormalized();
                            if (v && endpoint != null && endpoint.isNotEmpty) {
                              cloudPayload['endpoint'] = endpoint;
                              cloudPayload['iotEndpoint'] = endpoint;
                            }
                            final ok = await _send({
                              'cloud': cloudPayload,
                            }, forceLocalOnly: v);
                            if (!ok) {
                              if (v) {
                                await _recoverCloudEnableForActiveDevice();
                                final cloudReady =
                                    await _ensureCloudReadyForActiveDevice(
                                      force: true,
                                      showSnack: false,
                                    );
                                if (cloudReady ||
                                    _cloudCommandEligibleForActive()) {
                                  if (mounted) {
                                    _safeSetState(() {});
                                  }
                                  _showSnack(
                                    'Local komut zaman aşımına uğradı; cihaz cloud üzerinden devralındı.',
                                  );
                                  return;
                                }
                              }
                              await _setCloudEnabledLocalForActiveDevice(
                                previous,
                                prefs: p,
                              );
                              if (mounted) {
                                _safeSetState(() {});
                              }
                              _showSnack(
                                v
                                    ? 'Cloud açmak için cihazla local/ble/ap bağlantısı gerekir'
                                    : 'Cloud kapatmak için cihazla bağlantı gerekir (local veya cloud)',
                              );
                              return;
                            }
                            if (v) {
                              final refreshed =
                                  await _fetchStateSmart(force: true) ??
                                  await api.fetchState();
                              if (refreshed != null) {
                                state = refreshed;
                              }
                              final cloudReason =
                                  (refreshed?.cloudStateReason ??
                                          state?.cloudStateReason ??
                                          '')
                                      .trim()
                                      .toLowerCase();
                              if (cloudReason == 'no_endpoint') {
                                _cloudSetupTerminalError = 'no_endpoint';
                                _cloudSetupStatus =
                                    'Cloud endpoint ayarlı değil (firmware cloud secret eksik).';
                                if (mounted) _safeSetState(() {});
                                _showSnack(
                                  'Cloud endpoint ayarlı değil. Firmware tarafında AWS IoT endpoint/cert ayarlarını tamamlayın.',
                                );
                                return;
                              }
                              await _recoverCloudEnableForActiveDevice();
                              await _ensureCloudReadyForActiveDevice(
                                force: true,
                                showSnack: true,
                              );
                              if (!mounted) return;
                              _safeSetState(() {});
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 4),
                  if (showAdvanced)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Chip(
                          avatar: Icon(_cloudStateIcon(), size: 16),
                          label: Text('Cloud: ${_cloudStateLabel()}'),
                          backgroundColor: _cloudStateChipColor(context),
                        ),
                        Chip(
                          label: Text(
                            'DeviceCloud: ${_cloudEnabledByDeviceSignal() ? "ON" : "OFF"}',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          label: Text(
                            'Invites: ${_cloudInvitesSupported() ? "ON" : "OFF"}',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          label: Text(
                            'OtaJobs: ${_cloudOtaJobsSupported() ? "ON" : "OFF"}',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          label: Text(
                            'ShadowDesired: ${(_cloudFeatureShadowDesired ?? true) ? "ON" : "OFF"}',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          label: Text(
                            'ShadowState: ${(_cloudFeatureShadowState ?? true) ? "ON" : "OFF"}',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          label: Text(
                            'ShadowAclSync: ${(_cloudFeatureShadowAclSync ?? true) ? "ON" : "OFF"}',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        if (_cloudCapabilitiesSchema != null &&
                            _cloudCapabilitiesSchema!.isNotEmpty)
                          Chip(
                            label: Text(
                              'CapSchema: ${_cloudCapabilitiesSchema!}',
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        if (_cloudCapabilitiesSource != null &&
                            _cloudCapabilitiesSource!.isNotEmpty)
                          Chip(
                            label: Text('CapSrc: ${_cloudCapabilitiesSource!}'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Chip(
                          avatar: Icon(_cloudStateIcon(), size: 16),
                          label: Text('Cloud: ${_cloudStateLabel()}'),
                          backgroundColor: _cloudStateChipColor(context),
                        ),
                      ],
                    ),
                  if (showAdvanced && _cloudCapabilities != null) ...[
                    const SizedBox(height: 4),
                    Builder(
                      builder: (ctx) {
                        final caps = _cloudCapabilities!;
                        final switches = (caps['switches'] is Map)
                            ? Map<String, dynamic>.from(caps['switches'] as Map)
                            : const <String, dynamic>{};
                        final controls = (caps['controls'] is Map)
                            ? Map<String, dynamic>.from(caps['controls'] as Map)
                            : const <String, dynamic>{};
                        final sensors = (caps['sensors'] is Map)
                            ? Map<String, dynamic>.from(caps['sensors'] as Map)
                            : const <String, dynamic>{};
                        int countSupported(Map<String, dynamic> m) {
                          var c = 0;
                          for (final v in m.values) {
                            if (v is bool && v) c += 1;
                            if (v is Map && v['supported'] == true) c += 1;
                          }
                          return c;
                        }

                        final swCount = countSupported(switches);
                        final ctlCount = countSupported(controls);
                        final snsCount = countSupported(sensors);
                        final haPreview = _haEntityPreview(
                          caps,
                          _deviceId6ForMqtt() ?? '',
                        );
                        const previewLimit = 4;
                        final previewText = haPreview
                            .take(previewLimit)
                            .join(', ');
                        final previewMore = haPreview.length > previewLimit
                            ? ' +${haPreview.length - previewLimit}'
                            : '';
                        final fetchedText =
                            (_cloudCapabilitiesFetchedAt == null)
                            ? ''
                            : _cloudCapabilitiesFetchedAt!
                                  .toLocal()
                                  .toIso8601String()
                                  .substring(11, 19);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Capabilities: switches=$swCount controls=$ctlCount sensors=$snsCount'
                              '${fetchedText.isNotEmpty ? ' · $fetchedText' : ''}',
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                            if (haPreview.isNotEmpty)
                              Text(
                                'HA preview: $previewText$previewMore',
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                            if (haPreview.isNotEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    final id6 = _deviceId6ForMqtt() ?? '';
                                    String payload = '';
                                    final remote =
                                        await _fetchHaConfigFromCloud(id6);
                                    if (remote != null) {
                                      payload = const JsonEncoder.withIndent(
                                        '  ',
                                      ).convert(remote);
                                    }
                                    if (payload.isEmpty) {
                                      payload = _haDiscoveryPayloadDraft(
                                        caps,
                                        id6,
                                      );
                                    }
                                    await Clipboard.setData(
                                      ClipboardData(text: payload),
                                    );
                                    if (!mounted) return;
                                    _showSnack(
                                      'HA discovery payload panoya kopyalandı',
                                    );
                                  },
                                  icon: const Icon(Icons.copy, size: 16),
                                  label: const Text('HA Payload Kopyala'),
                                ),
                              ),
                            if (haPreview.isNotEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    final id6 = _deviceId6ForMqtt() ?? '';
                                    String text =
                                        _haConfigTextFromResponse(
                                          await _fetchHaConfigFromCloud(id6),
                                        ) ??
                                        '';
                                    if (text.isEmpty) {
                                      text = _haDiscoveryConfigMessagesText(
                                        caps,
                                        id6,
                                      );
                                    }
                                    await Clipboard.setData(
                                      ClipboardData(text: text),
                                    );
                                    if (!mounted) return;
                                    _showSnack(
                                      'HA config topic/payload panoya kopyalandı',
                                    );
                                  },
                                  icon: const Icon(Icons.topic, size: 16),
                                  label: const Text('HA Config Kopyala'),
                                ),
                              ),
                            if (haPreview.isNotEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    final id6 = _deviceId6ForMqtt() ?? '';
                                    try {
                                      String path;
                                      final remote =
                                          await _fetchHaConfigFromCloud(id6);
                                      final txt = _haConfigTextFromResponse(
                                        remote,
                                      );
                                      if (txt != null && txt.isNotEmpty) {
                                        path = await _saveTextDraft(
                                          'ha_config',
                                          id6,
                                          txt,
                                          ext: 'txt',
                                        );
                                      } else {
                                        path =
                                            await _saveHaDiscoveryPayloadDraft(
                                              caps,
                                              id6,
                                            );
                                      }
                                      if (!mounted) return;
                                      _showSnack(
                                        'HA payload kaydedildi: $path',
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      _showSnack(
                                        'HA payload kaydedilemedi: $e',
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.save_alt, size: 16),
                                  label: Text(t.literal('HA Payload Kaydet')),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                  if (showAdvanced) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: (_cloudLoggedIn() && !_cloudMembersLoading)
                              ? () => _refreshCloudMembers(force: true)
                              : null,
                          icon: const Icon(Icons.group_outlined),
                          label: const Text('Members'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              (_cloudLoggedIn() &&
                                  _cloudInvitesSupported() &&
                                  !_cloudInvitesLoading)
                              ? () => _refreshCloudInvites(force: true)
                              : null,
                          icon: const Icon(Icons.mark_email_read_outlined),
                          label: const Text('Invites'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _cloudLoggedIn()
                              ? () async {
                                  await _refreshOwnerFromCloud();
                                  if (mounted) _safeSetState(() {});
                                }
                              : null,
                          icon: const Icon(Icons.person_search_outlined),
                          label: const Text('Owner State'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          (state?.cloudMqttConnected ?? false)
                              ? Icons.cloud_done
                              : Icons.cloud_off,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'MQTT: ${state?.cloudMqttState.isNotEmpty ?? false ? state!.cloudMqttState : 'UNKNOWN'} (${state?.cloudMqttStateCode ?? 0})',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if ((state?.cloudStateReason ?? '').trim().isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Neden: ${_cloudReasonLabel((state?.cloudStateReason ?? '').trim())}',
                            ),
                          ),
                        ],
                      ),
                    if ((state?.sampleTsMs ?? 0) > 0 &&
                        (state?.cloudStateSinceMs ?? 0) > 0 &&
                        (state!.sampleTsMs >= state!.cloudStateSinceMs))
                      Row(
                        children: [
                          const Icon(Icons.schedule, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Süre: ${_formatElapsedShortMs(state!.sampleTsMs - state!.cloudStateSinceMs)}',
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          (state?.cloudClaimed == true)
                              ? Icons.verified
                              : Icons.link_off,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Claim: ${(state?.cloudClaimed ?? false) ? 'VAR' : 'YOK'}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cloud teşhis özeti',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          for (final row in _cloudDiagnosticsRows())
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 132,
                                    child: Text(
                                      row.key,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SelectableText(
                                      row.value,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          if (state != null)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Yetki ve Erişim',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        if (_effectiveOwnerExists())
                          Chip(
                            label: Text(t.literal('Owner atanmış')),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                          )
                        else if (_canClaimOwner)
                          Chip(
                            label: Text(t.literal('Sahip atanmadı')),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.errorContainer,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (_isOwnerRole())
                          FilledButton.tonalIcon(
                            onPressed: _startApRescueFromOwner,
                            icon: const Icon(Icons.wifi),
                            label: Text(t.literal('Soft recovery başlat')),
                          )
                        else
                          FilledButton.tonalIcon(
                            onPressed: _openInviteJoinFlow,
                            icon: const Icon(Icons.group_add_outlined),
                            label: Text(t.literal('Davet ile katıl')),
                          ),
                        if (_isOwnerRole())
                          FilledButton.icon(
                            onPressed: _startDeviceShareFlow,
                            icon: const Icon(Icons.share_outlined),
                            label: Text(t.literal('Paylaş')),
                          ),
                        if (showAdvanced && _isOwnerRole())
                          OutlinedButton.icon(
                            onPressed: _joinViaApWithInviteDialog,
                            icon: const Icon(Icons.share_outlined),
                            label: Text(t.literal('Davet JSON (ileri)')),
                          ),
                        if (state!.joinActive)
                          Chip(
                            avatar: const Icon(Icons.link, size: 16),
                            label: Text(t.literal('Davet penceresi açık')),
                          ),
                        if (state!.softRecoveryActive)
                          Chip(
                            avatar: const Icon(Icons.timer, size: 16),
                            label: Text(
                              state!.softRecoveryRemainingSec > 0
                                  ? 'Soft recovery aktif (${state!.softRecoveryRemainingSec}s)'
                                  : 'Soft recovery aktif',
                            ),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.tertiaryContainer,
                          ),
                        if (state!.pairingWindowActive)
                          Chip(
                            avatar: const Icon(Icons.bluetooth, size: 16),
                            label: Text(t.literal('BLE eşleşme açık')),
                          ),
                        if (state!.apSessionActive)
                          const Chip(
                            avatar: Icon(Icons.wifi_lock, size: 16),
                            label: Text('AP kurtarma aktif'),
                          ),
                      ],
                    ),
                    if (_isOwnerRole() && !showAdvanced) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Davet üretme ve kullanıcı yönetimi için ileri modu açabilirsiniz.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (!state!.softRecoveryActive) ...[
                      const SizedBox(height: 6),
                      Text(
                        'İpucu: Önce Bluetooth ile bağlanıp soft recovery açın, sonra AP ile kurulum yapın.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.verified_user, size: 18),
                        const SizedBox(width: 6),
                        Text('Rol: ${_authRoleLabel()}'),
                        const SizedBox(width: 8),
                        if (!_isOwnerRole())
                          Chip(
                            label: Text(t.literal('Kısıtlı')),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                      ],
                    ),
                    if (_isOwnerRole() && showAdvanced) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Davetli Kullanıcılar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      if (_cloudMembersLoading)
                        Text(t.literal('Üyeler yükleniyor...')),
                      if (!_cloudMembersLoading && visibleCloudMembers.isEmpty)
                        Text(t.literal('Henüz davetli kullanıcı yok.')),
                      if (visibleCloudMembers.isNotEmpty)
                        Column(
                          children: [
                            for (final item in visibleCloudMembers)
                              Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ((item['email'] ??
                                                    item['userEmail'] ??
                                                    '')
                                                .toString()
                                                .trim()
                                                .isNotEmpty)
                                            ? '${(item['role'] ?? 'USER').toString().trim().toUpperCase()} • ${(item['email'] ?? item['userEmail'] ?? '').toString().trim()}'
                                            : '${(item['role'] ?? 'USER').toString().trim().toUpperCase()} • ${_shortUserId((item['userSub'] ?? item['userId'] ?? '').toString().trim())}',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _cloudRevokeMember(
                                        (item['userSub'] ??
                                                item['userId'] ??
                                                '')
                                            .toString()
                                            .trim(),
                                      ),
                                      child: Text(t.literal('Yetkiyi kaldır')),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Aktif davetler',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      if (_cloudInvitesLoading)
                        Text(t.literal('Davetler yükleniyor...')),
                      if (!_cloudInvitesLoading && visibleCloudInvites.isEmpty)
                        const Text('Aktif davet yok.'),
                      if (visibleCloudInvites.isNotEmpty)
                        Column(
                          children: [
                            for (final item in visibleCloudInvites)
                              Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${(item['role'] ?? 'USER').toString().trim().toUpperCase()} • ${(item['inviteeEmail'] ?? '-').toString().trim()}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Durum: ${(item['status'] ?? 'pending').toString().trim()} • ${_formatInviteRemaining(item['expiresAt'])}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      if (showAdvanced) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Cloud uye ve davet yonetimi',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed:
                                  (_cloudEnabledEffective() &&
                                      _cloudLoggedIn() &&
                                      !_cloudMembersLoading)
                                  ? () => _refreshCloudMembers(force: true)
                                  : null,
                              icon: const Icon(Icons.group_outlined),
                              label: const Text('Uyeleri yenile'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  (_cloudEnabledEffective() &&
                                      _cloudLoggedIn() &&
                                      _cloudInvitesSupported() &&
                                      !_cloudInvitesLoading)
                                  ? () => _refreshCloudInvites(force: true)
                                  : null,
                              icon: const Icon(Icons.mail_outline),
                              label: Text(t.literal('Davetleri yenile')),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  (_cloudEnabledEffective() &&
                                      _cloudLoggedIn() &&
                                      !_cloudAclPushLoading)
                                  ? _cloudPushAcl
                                  : null,
                              icon: const Icon(Icons.upload),
                              label: Text(
                                _cloudAclPushLoading ? 'Push...' : 'ACL Push',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  (_cloudEnabledEffective() &&
                                      _cloudLoggedIn() &&
                                      !_cloudIntegrationsLoading)
                                  ? () => _refreshCloudIntegrations(force: true)
                                  : null,
                              icon: const Icon(Icons.hub_outlined),
                              label: const Text('Integration yenile'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  (_cloudEnabledEffective() && _cloudLoggedIn())
                                  ? _cloudCreateIntegrationLink
                                  : null,
                              icon: const Icon(Icons.add_link_outlined),
                              label: const Text('Integration ekle'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Cloud integration linkleri',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        if (_cloudIntegrationsLoading)
                          Text(t.literal('Integration listesi yükleniyor...')),
                        if (!_cloudIntegrationsLoading &&
                            (_cloudIntegrations == null ||
                                _cloudIntegrations!.isEmpty))
                          Text(
                            _cloudIntegrationsErr == null
                                ? 'Henüz integration link yok.'
                                : 'Integration listesi alınamadı.',
                          ),
                        if ((_cloudIntegrations?.isNotEmpty ?? false))
                          Column(
                            children: [
                              for (final item in _cloudIntegrations!)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (item['integrationId'] ?? '-')
                                                  .toString(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _formatIntegrationScopes(
                                                item['scopes'],
                                              ),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            _cloudRevokeIntegration(
                                              (item['integrationId'] ?? '')
                                                  .toString(),
                                            ),
                                        child: Text(t.literal('Kaldır')),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                      ],
                      if (!showAdvanced) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Cloud uye ve davet yonetimi gelistirici modunda gorunur.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 3),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.t('filter_care'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _canControlDevice ? _runCalibration : null,
                        icon: const Icon(Icons.tune),
                        label: Text(t.t('calibrate')),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _canControlDevice ? _runTest : null,
                        icon: const Icon(Icons.fact_check),
                        label: Text(t.t('test_run')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (redWarn)
                    Text(
                      t.t('red_warning'),
                      style: TextStyle(
                        color: Colors.red.shade400,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${t.t('theme')}: '),
                      DropdownButton<ThemeMode>(
                        value: Theme.of(context).brightness == Brightness.dark
                            ? ThemeMode.dark
                            : ThemeMode.light,
                        items: [
                          DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Text(t.t('theme_light')),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text(t.t('theme_dark')),
                          ),
                        ],
                        onChanged: (m) {
                          if (m != null) {
                            widget.onThemeChanged(m);
                            () async {
                              final p = await SharedPreferences.getInstance();
                              final brand =
                                  _activeDevice?.brand ?? kDefaultDeviceBrand;
                              final themeKey = _themeModeKeyForBrand(brand);
                              final themeUserKey = _themeUserSetKeyForBrand(
                                brand,
                              );
                              await p.setString(
                                themeKey,
                                m == ThemeMode.light ? 'light' : 'dark',
                              );
                              await p.setBool(themeUserKey, true);
                              _themeUserSet = true;
                            }();
                          }
                        },
                      ),
                      Text('${t.t('language')}: '),
                      DropdownButton<String>(
                        value: widget.i18n.code,
                        items: I18n.supported.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                        onChanged: (loc) {
                          if (loc != null) {
                            widget.onLanguageChanged(loc);
                            SharedPreferences.getInstance().then(
                              (p) => p.setString('lang', loc),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Gelistirici secenekleri'),
                    subtitle: const Text(
                      'Base URL, cloud debug ve gelismis araclari gosterir',
                    ),
                    value: _showAdvancedSettings,
                    onChanged: (v) async {
                      if (v && !_showAdvancedSettings) {
                        final ok = await _verifyAdvancedSettingsPassword();
                        if (!ok) return;
                      }
                      if (!mounted) return;
                      _safeSetState(() {
                        _showAdvancedSettings = v;
                      });
                      final p = await SharedPreferences.getInstance();
                      await p.setBool(kUiAdvancedSettingsKey, v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Calibration & Test =====
}
