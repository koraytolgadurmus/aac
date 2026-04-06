part of 'main.dart';

// Onboarding + cihaz seçim ekranı tek yerde toplandı.
// Bu blok, ilk kurulum karar ağacını (cloud/local), AP'ye manuel geçiş
// diyaloglarını ve cihaz listesi CRUD işlemlerini içerir.
extension _HomeScreenOnboardingDevicePicker on _HomeScreenState {
  Future<void> _setOnboardingDone() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(kOnboardingV1DoneKey, true);
    } catch (_) {}
  }

  Future<String?> _showFirstLaunchPathDialog() async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.t('onb_welcome_title')),
          content: Text(t.t('onb_choose_path_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('skip'),
              child: Text(t.t('onb_skip')),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop('local'),
              child: Text(t.t('onb_local_connection')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('cloud'),
              child: Text(t.t('onb_cloud_connection')),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showCloudAuthChoiceDialog() async {
    if (!mounted) return null;
    await _settleRouteTransition();
    if (!mounted) return null;
    return Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ChoicePage(
          title: t.t('onb_cloud_signin_title'),
          description: t.t('onb_cloud_signin_body'),
          options: [
            _ChoiceOption(
              value: 'login',
              title: t.t('onb_signin'),
              icon: Icons.login,
              emphasized: true,
            ),
            _ChoiceOption(
              value: 'signup',
              title: t.t('onb_signup'),
              icon: Icons.app_registration,
            ),
            const _ChoiceOption(
              value: 'confirm',
              title: 'Doğrulama kodu',
              icon: Icons.mark_email_read_outlined,
            ),
            const _ChoiceOption(
              value: 'forgot',
              title: 'Şifremi unuttum',
              icon: Icons.lock_reset,
            ),
            _ChoiceOption(
              value: 'cancel',
              title: t.t('cancel'),
              icon: Icons.close,
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showLocalSetupChoiceDialog() async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.t('onb_local_setup_title')),
          content: Text(t.t('onb_local_setup_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: Text(t.t('cancel')),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop('ap_only'),
              child: Text(t.t('onb_join_device_network')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('provision'),
              child: Text(t.t('onb_connect_home_wifi')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMoveCloserWarning() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.t('onb_safety_title')),
          content: Text(t.t('onb_move_closer_body')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.t('onb_continue')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onboardingAskCloudAfterLocalReady() async {
    if (!mounted) return;
    _clearBlockingProgress();
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.t('onb_local_ready_title')),
          content: Text(t.t('onb_local_ready_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('local_only'),
              child: Text(t.t('onb_local_only')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('cloud'),
              child: Text(t.t('onb_enable_cloud')),
            ),
          ],
        );
      },
    );
    if (choice != 'cloud') {
      _safeSetState(() => _tab = 0);
      return;
    }
    _setBlockingProgress(
      title: t.t('please_wait'),
      body: t.t('onb_wait_device_discovery'),
    );
    final stillReady = await _awaitStableLocalReadyForPrompt(
      total: const Duration(seconds: 20),
    );
    _clearBlockingProgress();
    if (!stillReady || !mounted) {
      _showSnack('Önce yerel bağlantı tamamlanmalı, sonra cloud açılacak.');
      return;
    }
    final ownerReady = await _ensureLocalOwnerClaimAfterProvision(
      source: 'onb_local_ready_cloud_enable',
    );
    if (!ownerReady) {
      debugPrint(
        '[ONB] owner finalize not completed; continuing with cloud-enable best effort',
      );
    }
    final previousCloudEnabled = _cloudUserEnabledLocal;
    var cloudEnableStepOk = false;
    try {
      if (_cloudEndpointMissingForActive()) {
        _showSnack(
          'Cloud endpoint ayarlı değil. Önce firmware tarafında AWS IoT endpoint/cert ayarlarını tamamlayın.',
        );
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await _setCloudEnabledLocalForActiveDevice(true, prefs: prefs);
      final cloudPayload = <String, dynamic>{'enabled': true};
      final endpoint = _effectiveCloudEndpointNormalized();
      if (endpoint != null && endpoint.isNotEmpty) {
        cloudPayload['endpoint'] = endpoint;
        cloudPayload['iotEndpoint'] = endpoint;
      }
      final localCloudCmdOk = await _send({
        'cloud': cloudPayload,
      }, forceLocalOnly: true);
      if (!localCloudCmdOk) {
        await _recoverCloudEnableForActiveDevice();
        final cloudReady = await _ensureCloudReadyForActiveDevice(
          force: true,
          showSnack: false,
        );
        if (!cloudReady && !_cloudCommandEligibleForActive()) {
          await _setCloudEnabledLocalForActiveDevice(
            previousCloudEnabled,
            prefs: prefs,
          );
          _clearBlockingProgress();
          _showSnack('Cloud açmak için cihazla local bağlantı doğrulanamadı.');
          return;
        }
      }
      _setBlockingProgress(
        title: t.t('please_wait'),
        body: 'Cloud ayarı cihaza uygulanıyor...',
      );
      var ack = await _awaitCloudEnableAckForOnboarding(
        total: const Duration(seconds: 20),
      );
      if (!ack) {
        await _recoverCloudEnableForActiveDevice();
        ack = await _awaitCloudEnableAckForOnboarding(
          total: const Duration(seconds: 8),
        );
      }
      _clearBlockingProgress();
      if (!ack) {
        await _setCloudEnabledLocalForActiveDevice(
          previousCloudEnabled,
          prefs: prefs,
        );
        _showSnack('Cihaz cloud açma onayı vermedi, local modda kalındı.');
        return;
      }
      cloudEnableStepOk = true;
    } catch (_) {
      _showSnack(
        'Cloud açma adımı sırasında hata oluştu, local modda kalındı.',
      );
    }
    if (!cloudEnableStepOk) return;
    _safeSetState(() {});

    var loggedIn = _cloudLoggedIn();
    if (!loggedIn) {
      final authChoice = await _showCloudAuthChoiceDialog();
      if (authChoice == 'confirm') {
        await _openCloudConfirmDialog();
      } else if (authChoice == 'forgot') {
        await _startCloudForgotPasswordFlow();
      } else if (authChoice == 'login' || authChoice == 'signup') {
        await _handleCloudLoginSuccess(
          signup: authChoice == 'signup',
          promptPicker: true,
        );
      }
      loggedIn = _cloudLoggedIn();
    }
    var cloudReady = false;
    if (loggedIn) {
      _setBlockingProgress(
        title: t.t('please_wait'),
        body: 'Cloud bağlantısı hazırlanıyor...',
      );
      cloudReady = await _ensureCloudReadyForActiveDevice(
        force: true,
        showSnack: true,
      );
      _clearBlockingProgress();
      if (!cloudReady) {
        _showSnack('Cloud bağlantısı açılamadı, local modda devam ediliyor.');
      }
    } else {
      _showSnack('Cloud girişi tamamlanmadı, local modda devam ediliyor.');
    }

    try {
      final latest = await _fetchStateSmart(force: true);
      if (latest != null) {
        _safeSetState(() {
          state = latest;
          connected = true;
          _lastLocalOkAt = DateTime.now();
          _lastUpdate = DateTime.now();
        });
      }
    } catch (_) {}
    _safeSetState(() => _tab = 0);
  }

  Future<void> _runCloudFirstLaunchFlow() async {
    final authChoice = await _showCloudAuthChoiceDialog();
    if (authChoice == 'confirm') {
      await _openCloudConfirmDialog();
      return;
    }
    if (authChoice == 'forgot') {
      await _startCloudForgotPasswordFlow();
      return;
    }
    if (authChoice != 'login' && authChoice != 'signup') return;

    await _handleCloudLoginSuccess(
      signup: authChoice == 'signup',
      promptPicker: true,
    );
    if (!mounted || !_cloudLoggedIn()) return;

    final loadedCount = await _syncCloudDevices(
      autoSelectIfNeeded: true,
      showSnack: false,
    );
    if (!mounted) return;

    if ((loadedCount ?? 0) > 0) {
      final next = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return AlertDialog(
            title: Text(t.t('onb_cloud_devices_loaded_title')),
            content: Text(t.t('onb_cloud_devices_loaded_body')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('continue'),
                child: Text(t.t('onb_continue')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop('add_new'),
                child: Text(t.t('onb_add_new_device')),
              ),
            ],
          );
        },
      );

      await _openDevicePicker();
      if (next == 'add_new') {
        await _showMoveCloserWarning();
        await _openBleManageAndProvision();
      }
    } else {
      await _openDevicePicker();
      if (!mounted) return;
      _showSnack(t.t('onb_cloud_no_device_hint'));
      await _showMoveCloserWarning();
      await _openBleManageAndProvision();
    }

    if (_cloudLoggedIn()) {
      final ownerReady = await _ensureLocalOwnerClaimAfterProvision(
        source: 'cloud_first_onboarding',
      );
      if (!ownerReady) {
        _showSnack(
          'Owner doğrulaması tamamlanmadan cloud açılamaz. Lütfen BLE kurulumunu tekrar deneyin.',
        );
        return;
      }
      await _ensureCloudReadyForActiveDevice(force: true, showSnack: false);
    }
  }

  Future<bool?> _promptManualJoinToAp({
    required String ssid,
    required String pass,
  }) async {
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Future<void> copyText(String value, String label) async {
          try {
            await Clipboard.setData(ClipboardData(text: value));
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$label kopyalandı')));
            }
          } catch (_) {}
        }

        Widget credRow({
          required String label,
          required String value,
          bool obscure = false,
        }) {
          final shown = obscure && value.isNotEmpty
              ? ('*' * value.length.clamp(4, 24))
              : (value.isEmpty ? '(yok)' : value);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(ctx).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: Theme.of(ctx).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      SelectableText(
                        shown,
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Kopyala',
                  onPressed: value.isEmpty
                      ? null
                      : () => copyText(value, label),
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          );
        }

        return AlertDialog(
          title: Text(t.literal('Cihaz AP Bilgileri')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BLE ile cihazdan alınan AP bilgileri aşağıda.\n'
                  'Telefon Wi-Fi ayarlarından bu ağa bağlanın, sonra devam edin.',
                ),
                const SizedBox(height: 12),
                credRow(label: 'SSID', value: ssid),
                credRow(label: 'Şifre', value: pass, obscure: false),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.t('cancel')),
            ),
            OutlinedButton(
              onPressed: () async {
                await openAppSettings();
              },
              child: const Text('Ayarları aç'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await _probeInfoReachable(
                  'http://192.168.4.1',
                  timeout: const Duration(seconds: 2),
                );
                if (!ok) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'AP erişimi doğrulanamadı. '
                          'Lütfen sadece "$ssid" ağına bağlandığınızı kontrol edin.',
                        ),
                      ),
                    );
                  }
                  return;
                }
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              },
              child: Text(t.literal('Bağlandım, devam et')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runLocalFirstLaunchFlow() async {
    final localChoice = await _showLocalSetupChoiceDialog();
    if (localChoice == null || localChoice == 'cancel') return;
    _armPostOnboardingLocalReadyPrompt();

    if (localChoice == 'ap_only') {
      await _showMoveCloserWarning();
      await _openBleManageAndProvision();
      return;
    }

    await _openDevicePicker();
    await _showMoveCloserWarning();
    await _openBleManageAndProvision();
  }

  Future<void> _maybeRunFirstLaunchOnboarding({
    required bool freshInstallCandidate,
  }) async {
    if (!freshInstallCandidate || _onboardingFlowStarted || !mounted) return;
    _onboardingFlowStarted = true;
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(kOnboardingV1DoneKey) == true) return;
      for (var i = 0; i < 40; i++) {
        final lang = (p.getString('lang') ?? '').trim();
        if (lang.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      if (_onboardingPreparing) {
        _safeSetState(() => _onboardingPreparing = false);
      }

      final nextStep = await _showFirstLaunchPathDialog();

      if (nextStep == null || nextStep == 'skip') {
        await _setOnboardingDone();
        return;
      }

      if (nextStep == 'cloud') {
        _armPostOnboardingLocalReadyPrompt();
        await _runCloudFirstLaunchFlow();
      } else if (nextStep == 'local') {
        await _runLocalFirstLaunchFlow();
      }
      await _setOnboardingDone();
    } finally {
      if (_onboardingPreparing) {
        _safeSetState(() => _onboardingPreparing = false);
      }
      _onboardingFlowStarted = false;
    }
  }

  Future<void> _openDevicePicker({
    bool autoStartProvisionOnNewDevice = false,
  }) async {
    if (!mounted) return;
    await _settleRouteTransition();
    if (!mounted) return;
    final selected = await Navigator.of(context, rootNavigator: true).push<_SavedDevice>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) {
          final brandOptions = kKnownDeviceBrands;
          String brand = brandOptions.first;
          final suffixCtl = TextEditingController();
          bool addingNew = false;

          return StatefulBuilder(
            builder: (ctx, setPageState) {
              return Scaffold(
                appBar: AppBar(
                  title: Text(t.t('device_picker_title')),
                  actions: [
                    if (_cloudLoggedIn())
                      IconButton(
                        icon: const Icon(Icons.cloud_download_outlined),
                        tooltip: 'Cloud cihazlarını yenile',
                        onPressed: () async {
                          await _syncCloudDevices(
                            autoSelectIfNeeded: _activeDevice == null,
                            showSnack: true,
                          );
                          setPageState(() {});
                        },
                      ),
                  ],
                ),
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!addingNew) ...[
                          if (_devices.isEmpty)
                            ListTile(title: Text(t.t('device_picker_empty')))
                          else
                            ..._devices.map((d) {
                              final displayBase =
                                  _preferredDisplayBaseUrlForDevice(d);
                              return ListTile(
                                title: Text(d.displayName),
                                subtitle: Text(
                                  [
                                    if (d.cloudLinked)
                                      'Cloud${(d.cloudRole ?? '').isNotEmpty ? ' · ${d.cloudRole}' : ''}',
                                    if (displayBase.isNotEmpty) displayBase,
                                  ].join('\n'),
                                ),
                                isThreeLine: d.cloudLinked,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_activeDeviceId == d.id)
                                      const Icon(
                                        Icons.check,
                                        color: Colors.teal,
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () async {
                                        await _editDevicePresentation(d);
                                        setPageState(() {});
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        await _deleteDevice(d);
                                        setPageState(() {});
                                      },
                                    ),
                                  ],
                                ),
                                onTap: () => Navigator.pop(ctx, d),
                              );
                            }),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.add),
                            title: Text(t.t('device_picker_add')),
                            subtitle: const Text(
                              'Davet kodu ile ekle, paylaşım isteğini yapıştır veya yeni cihaz kur',
                            ),
                            onTap: () async {
                              await _settleRouteTransition();
                              if (!ctx.mounted) return;
                              final action =
                                  await Navigator.of(
                                    ctx,
                                    rootNavigator: true,
                                  ).push<String>(
                                    MaterialPageRoute(
                                      fullscreenDialog: true,
                                      builder: (_) => const _ChoicePage(
                                        title: 'Yeni cihaz ekle',
                                        options: [
                                          _ChoiceOption(
                                            value: 'scan_invite',
                                            title: 'Davet kodu ile ekle',
                                            subtitle:
                                                'Owner cihazından gelen paylaşım verisini okut veya yapıştır.',
                                            icon: Icons.qr_code_scanner,
                                            emphasized: true,
                                          ),
                                          _ChoiceOption(
                                            value: 'cloud_invites',
                                            title: 'Davet ile kullanım',
                                            subtitle:
                                                'Cloud hesabınıza gelen davetleri görüntüleyin.',
                                            icon: Icons.mail_outline,
                                          ),
                                          _ChoiceOption(
                                            value: 'setup_new',
                                            title: 'Yeni cihaz kur',
                                            subtitle:
                                                'Yakındaki yeni cihazı Bluetooth ile kur.',
                                            icon: Icons.bluetooth,
                                          ),
                                          _ChoiceOption(
                                            value: 'ap_guided',
                                            title: 'Cihaz Wi-Fi ile kurulum',
                                            subtitle:
                                                'BLE ile doğrula, ardından telefonu cihaz Wi-Fi ağına bağlayıp devam et.',
                                            icon: Icons.wifi_tethering,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                              if (!ctx.mounted || action == null) return;
                              if (action == 'setup_new') {
                                setPageState(() {
                                  addingNew = true;
                                });
                                return;
                              }
                              Navigator.pop(ctx);
                              if (action == 'scan_invite') {
                                await _startInviteJoinFlow(
                                  initialAction: 'scan',
                                );
                                return;
                              }
                              if (action == 'cloud_invites') {
                                await _openPendingCloudInvitesFlow();
                                return;
                              }
                              if (action == 'ap_guided') {
                                await _runApGuidedSetupFlow();
                              }
                            },
                          ),
                        ] else ...[
                          DropdownButtonFormField<String>(
                            value: brand,
                            decoration: const InputDecoration(
                              labelText: 'Model',
                              border: OutlineInputBorder(),
                            ),
                            items: brandOptions
                                .map(
                                  (b) => DropdownMenuItem(
                                    value: b,
                                    child: Text(b),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setPageState(() => brand = v);
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: suffixCtl,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: 'Ek isim (örn. Salon)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () {
                                  setPageState(() {
                                    addingNew = false;
                                  });
                                },
                                child: Text(t.literal('Vazgeç')),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () {
                                  var suffix = suffixCtl.text.trim();
                                  if (suffix.length > 6) {
                                    suffix = suffix.substring(0, 6);
                                  }
                                  final candidateDisplay = suffix.isEmpty
                                      ? brand
                                      : '$brand $suffix';
                                  final existingNames = _devices
                                      .map((d) => d.displayName.toLowerCase())
                                      .toSet();
                                  if (existingNames.contains(
                                    candidateDisplay.toLowerCase(),
                                  )) {
                                    _showSnack(t.t('device_name_exists'));
                                    return;
                                  }
                                  if (suffix.isEmpty &&
                                      _devices.any(
                                        (d) =>
                                            d.brand == brand &&
                                            d.suffix.trim().isEmpty,
                                      )) {
                                    _showSnack(t.t('device_model_exists'));
                                    return;
                                  }
                                  if (_devices.any(
                                    (d) =>
                                        d.brand == brand &&
                                        d.suffix.trim().toLowerCase() ==
                                            suffix.toLowerCase(),
                                  )) {
                                    _showSnack(
                                      t.t('device_model_suffix_exists'),
                                    );
                                    return;
                                  }
                                  final dev = _SavedDevice(
                                    id: 'dev_${DateTime.now().millisecondsSinceEpoch}',
                                    brand: brand,
                                    suffix: suffix,
                                    baseUrl: '',
                                  );
                                  Navigator.pop(ctx, dev);
                                },
                                child: Text(t.literal('Kaydet ve seç')),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );

    if (selected != null) {
      final wasExisting = _devices.any((d) => d.id == selected.id);
      await _setActiveDevice(selected);
      if (autoStartProvisionOnNewDevice && !wasExisting && mounted) {
        await _settleRouteTransition();
        if (!mounted) return;
        await _openBleManageAndProvision();
      }
    }
  }

  Future<void> _editDevicePresentation(_SavedDevice dev) async {
    if (!mounted) return;
    final brandOptions = kKnownDeviceBrands;
    String selectedBrand = brandOptions.contains(dev.brand)
        ? dev.brand
        : brandOptions.first;
    final suffixCtl = TextEditingController(text: dev.suffix);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(t.literal('Cihaz adını düzenle')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedBrand,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      border: OutlineInputBorder(),
                    ),
                    items: brandOptions
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() => selectedBrand = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: suffixCtl,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Ek isim (örn. Salon)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(t.literal('Vazgeç')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(t.literal('Kaydet')),
                ),
              ],
            );
          },
        );
      },
    );
    if (updated != true) return;

    var suffix = suffixCtl.text.trim();
    if (suffix.length > 6) suffix = suffix.substring(0, 6);
    final candidateDisplay = suffix.isEmpty
        ? selectedBrand
        : '$selectedBrand $suffix';
    final existingNames = _devices
        .where((d) => d.id != dev.id)
        .map((d) => d.displayName.toLowerCase())
        .toSet();
    if (existingNames.contains(candidateDisplay.toLowerCase())) {
      _showSnack(t.t('device_name_exists'));
      return;
    }
    if (suffix.isEmpty &&
        _devices.any(
          (d) =>
              d.id != dev.id &&
              d.brand == selectedBrand &&
              d.suffix.trim().isEmpty,
        )) {
      _showSnack(t.t('device_model_exists'));
      return;
    }
    if (_devices.any(
      (d) =>
          d.id != dev.id &&
          d.brand == selectedBrand &&
          d.suffix.trim().toLowerCase() == suffix.toLowerCase(),
    )) {
      _showSnack(t.t('device_model_suffix_exists'));
      return;
    }

    dev.brand = selectedBrand;
    dev.suffix = suffix;
    await _saveDevicesToPrefs();
    _safeSetState(() {});

    final id6 = normalizeDeviceId6(dev.id);
    final id6Cloud = (id6 ?? '').trim();
    final canPushCloudName =
        id6Cloud.isNotEmpty &&
        dev.cloudLinked &&
        _cloudLoggedIn() &&
        (dev.cloudRole ?? '').toUpperCase() == 'OWNER';
    if (!canPushCloudName) return;

    await _cloudRefreshIfNeeded();
    final out = await cloudApi.updateDeviceName(
      id6Cloud,
      brand: dev.brand,
      suffix: dev.suffix,
      timeout: const Duration(seconds: 6),
    );
    if (out == null) {
      _showSnack(t.t('warn_cloud_name_update_failed'));
      return;
    }
    await _syncCloudDevices(autoSelectIfNeeded: false, showSnack: false);
  }

  Future<void> _deleteDevice(_SavedDevice dev) async {
    if (dev.cloudLinked && _cloudLoggedIn()) {
      final canUnlinkFromCloud = (dev.cloudRole ?? '').toUpperCase() == 'OWNER';
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.literal('Cihazı kaldır')),
          content: Text(
            canUnlinkFromCloud
                ? 'Bu cihazı sadece bu telefondan kaldırabilir veya cloud hesabınızdan da ayırabilirsiniz.'
                : 'Bu cihazı bu telefondan kaldırabilirsiniz. Cloud üyeliği korunur.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: Text(t.literal('Vazgeç')),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop('local'),
              child: Text(t.literal('Sadece uygulamadan kaldır')),
            ),
            if (canUnlinkFromCloud)
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop('cloud'),
                child: Text(t.literal('Cloud’dan da kaldır')),
              ),
          ],
        ),
      );
      if (action == null || action == 'cancel') return;
      if (action == 'cloud') {
        final id6 = normalizeDeviceId6(dev.id);
        if (id6 == null || id6.isEmpty) {
          _showSnack('Cloud cihaz kimliği bulunamadı');
          return;
        }
        await _cloudRefreshIfNeeded();
        final ok = await cloudApi.unclaimDevice(
          id6,
          const Duration(seconds: 6),
        );
        if (!ok) {
          _showSnack('Cloud kaldırma başarısız');
          return;
        }
        dev.cloudLinked = false;
        dev.cloudRole = null;
        dev.cloudSource = null;
      }
    }
    final idx = _devices.indexWhere((d) => d.id == dev.id);
    if (idx == -1) return;
    final wasActive = _activeDeviceId == dev.id;
    _deviceRuntime.remove(_runtimeKeyForDeviceId(dev.id));
    _devices.removeAt(idx);
    try {
      await _clearPairTokenForDevice(dev.id);
    } catch (_) {}
    if (wasActive && _devices.isNotEmpty) {
      await _setActiveDevice(_devices.first);
    } else if (_devices.isEmpty) {
      _activeDeviceId = null;
      state = null;
      connected = false;
      baseUrl = 'http://192.168.4.1';
      api.baseUrl = baseUrl;
      api.setPairToken(null);
      _urlCtl.text = baseUrl;
      await _saveDevicesToPrefs();
      _safeSetState(() {});
    } else {
      await _saveDevicesToPrefs();
    }
  }
}
