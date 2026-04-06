part of 'main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.i18n,
    required this.onThemeChanged,
    required this.onLanguageChanged,
  });
  final I18n i18n;
  final void Function(ThemeMode) onThemeChanged;
  final void Function(String) onLanguageChanged;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late ApiService api;
  late CloudApiService cloudApi;
  DeviceState? state;
  Timer? _poller;
  bool _pollTickInFlight = false;
  int _pollGeneration = 0;
  DateTime? _pollFastUntil;
  int _backgroundSuspendCount = 0;
  bool _connTickInFlight = false;
  DateTime? _connNextTryAt;
  int _connBackoffSeconds = 2;
  DateTime? _lastLocalOkAt;
  DateTime? _lastMdnsFixAt;
  DateTime? _localDnsFailUntil;
  DateTime? _localUnreachableUntil;
  DateTime? _lastCloudOkAt;
  DateTime? _cloudFailUntil;
  DateTime? _cloudPreferUntil;
  DateTime? _cloudManualDisableUntil;
  DateTime? _cloudCmdPathCheckedAt;
  String? _cloudCmdPathCheckedId6;
  bool? _cloudCmdPathReadyCached;
  String _lastCmdTransport = 'none';
  DateTime? _deviceMismatchWarnUntil;
  final Map<String, String> _endpointId6ByBase = {};
  final Map<String, DateTime> _endpointId6SeenAtByBase = {};
  DateTime? _preferApUntil;
  DateTime? _lastApReachableAt;
  String _lastStateFetchSource = 'none'; // cloud | local | ap | none
  bool? _cloudOwnerExistsOverride;
  bool? _cloudOwnerSetupDoneOverride;
  String baseUrl = 'http://192.168.4.1';
  String _cloudApiBase = '';
  String? _cloudIotEndpoint;
  bool _cloudUserEnabledLocal = false;
  String? _cloudIdToken;
  String? _cloudRefreshToken;
  DateTime? _cloudTokenExp;
  String? _cloudUserEmail;
  bool? _cloudFeatureInvites;
  bool? _cloudFeatureOtaJobs;
  bool? _cloudFeatureShadowDesired;
  bool? _cloudFeatureShadowState;
  bool? _cloudFeatureShadowAclSync;
  String? _cloudApiState;
  String? _cloudApiStateReason;
  int? _cloudApiDeviceCount;
  List<String> _cloudApiDeviceIds = [];
  Map<String, dynamic>? _cloudCapabilities;
  String? _cloudCapabilitiesSchema;
  String? _cloudCapabilitiesSource;
  DateTime? _cloudCapabilitiesFetchedAt;
  DateTime? _cloudFeaturesFetchedAt;
  Future<bool>? _cloudRefreshFuture;
  DateTime? _cloudRefreshBlockedUntil;
  Future<int?>? _cloudDeviceSyncFuture;
  DateTime? _cloudDevicesFetchedAt;
  DateTime? _cloudOwnerAuxPolledAt;
  DateTime? _lastCloudStateFetchAt;
  String? _lastCloudStateFetchId6;
  List<Map<String, dynamic>>? _cloudMembers;
  DateTime? _cloudMembersFetchedAt;
  bool _cloudMembersLoading = false;
  String? _cloudMembersErr;
  bool _cloudAclPushLoading = false;
  bool _cloudAclAutoInFlight = false;
  DateTime? _cloudAclAutoNextAt;
  bool _cloudSetupInFlight = false;
  bool _cloudStartupClaimInFlight = false;
  DateTime? _cloudStartupClaimRetryAt;
  String? _cloudSetupStatus;
  String? _cloudSetupTerminalError;
  DateTime? _cloudSetupLastAttemptAt;
  List<Map<String, dynamic>>? _cloudInvites;
  DateTime? _cloudInvitesFetchedAt;
  bool _cloudInvitesLoading = false;
  String? _cloudInvitesErr;
  List<Map<String, dynamic>>? _cloudPendingInvites;
  DateTime? _cloudPendingInvitesFetchedAt;
  bool _cloudPendingInvitesLoading = false;
  String? _cloudPendingInvitesErr;
  List<Map<String, dynamic>>? _cloudIntegrations;
  DateTime? _cloudIntegrationsFetchedAt;
  bool _cloudIntegrationsLoading = false;
  String? _cloudIntegrationsErr;
  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  // Çoklu cihaz desteği: kayıtlı cihaz listesi + aktif cihaz ID
  List<_SavedDevice> _devices = [];
  String? _activeDeviceId;
  int _activeDeviceSwitchEpoch = 0;
  final Map<String, _DeviceRuntimeContext> _deviceRuntime = {};
  int _tab = 0;
  bool _showAdvancedSettings = false;
  bool _onboardingFlowStarted = false;
  bool _onboardingPreparing = false;
  bool _postOnboardingLocalReadyPromptPending = false;
  String? _blockingProgressTitle;
  String? _blockingProgressBody;
  bool connected = false;
  DateTime? _lastUpdate;
  List<_PlanItem> _plans = [];
  late TextEditingController _urlCtl;
  late TextEditingController _cloudUrlCtl;
  late TextEditingController _cloudEmailCtl;
  late List<int>
  _appliedStartMin; // per plan: which start-minute was last applied (only at start or on force)
  bool _rgbExpanded = false; // UI: RGB paleti aç/kapa
  int? _rgbBrightnessDraft;
  String? lastFilterMsg;
  bool _plannerWasActive = false;
  // After plans end or when there are no plans, ensure AUTO is triggered only once
  bool _autoAfterNoPlanSent = false;
  // If user changes mode/fan manually during an active plan, don't auto-reapply plan
  bool _manualOverride = false;
  // Snapshot of pre-plan state so we can restore user settings
  bool _hasPrePlanSnapshot = false;
  int? _prePlanMode;
  int? _prePlanFanPercent;
  bool? _prePlanLightOn;
  bool? _prePlanIonOn;
  bool? _prePlanRgbOn;
  bool? _prePlanAutoHumEnabled;
  double? _prePlanAutoHumTarget;
  bool _bleBusy = false;
  final bool _autoBleReconnectEnabled = false;
  bool _networkAutoPollingAllowed = false;
  String? _transportSessionOwner;
  DateTime? _transportRecoveryCooldownUntil;
  DateTime? _lastInvalidQrTokenAt;
  bool _cloudClaimNeedsQrRefresh = false;
  _ClaimFlowStage _claimFlowStage = _ClaimFlowStage.idle;
  String? _claimFlowDetail;
  DateTime? _claimFlowUpdatedAt;
  bool _claimFlowBusy = false;
  int _localUnauthorizedHits = 0;
  bool _localUnauthorizedRecoveryInFlight = false;
  DateTime? _nextLocalUnauthorizedRecoveryAt;
  int _activeSwitchRecoverySeq = 0;
  DateTime? _lastActiveDeviceSwitchAt;
  DateTime? _lastEndpointMismatchAt;

  String _literal(String raw) =>
      I18n(Localizations.localeOf(context).languageCode).literal(raw);

  void _setClaimFlowStage(_ClaimFlowStage stage, {String? detail}) {
    final stamp = DateTime.now();
    if (mounted) {
      setState(() {
        _claimFlowStage = stage;
        _claimFlowDetail = detail;
        _claimFlowUpdatedAt = stamp;
      });
    } else {
      _claimFlowStage = stage;
      _claimFlowDetail = detail;
      _claimFlowUpdatedAt = stamp;
    }
  }

  String _claimFlowTitle() {
    switch (_claimFlowStage) {
      case _ClaimFlowStage.idle:
        return _literal('Claim durumu: Hazır');
      case _ClaimFlowStage.waitingQr:
        return _literal('Claim durumu: Doğrulama bekleniyor');
      case _ClaimFlowStage.qrStored:
        return _literal('Claim durumu: Doğrulama kaydedildi');
      case _ClaimFlowStage.claiming:
        return _literal('Claim durumu: Cihaz sahipliği doğrulanıyor');
      case _ClaimFlowStage.claimed:
        return _literal('Claim durumu: Tamamlandı');
      case _ClaimFlowStage.failed:
        return _literal('Claim durumu: Başarısız');
    }
  }

  Color _claimFlowColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (_claimFlowStage) {
      case _ClaimFlowStage.claimed:
        return cs.primary;
      case _ClaimFlowStage.failed:
        return cs.error;
      case _ClaimFlowStage.claiming:
        return cs.tertiary;
      case _ClaimFlowStage.waitingQr:
      case _ClaimFlowStage.qrStored:
        return cs.secondary;
      case _ClaimFlowStage.idle:
        return cs.onSurfaceVariant;
    }
  }

  String _claimFlowUpdatedText() {
    final ts = _claimFlowUpdatedAt;
    if (ts == null) return '';
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    final ss = ts.second.toString().padLeft(2, '0');
    return '${_literal('Son güncelleme')}: $hh:$mm:$ss';
  }

  void _markConnected() {
    if (mounted) {
      setState(() {
        connected = true;
      });
    } else {
      connected = true;
    }
  }

  bool get _blockingProgressVisible =>
      (_blockingProgressTitle != null &&
          _blockingProgressTitle!.trim().isNotEmpty) ||
      (_blockingProgressBody != null &&
          _blockingProgressBody!.trim().isNotEmpty);

  void _setBlockingProgress({required String title, String? body}) {
    if (!mounted) return;
    setState(() {
      _blockingProgressTitle = title.trim().isEmpty
          ? t.t('please_wait')
          : title;
      _blockingProgressBody = body != null && body.trim().isNotEmpty
          ? body.trim()
          : null;
    });
  }

  void _clearBlockingProgress() {
    if (!mounted || !_blockingProgressVisible) return;
    setState(() {
      _blockingProgressTitle = null;
      _blockingProgressBody = null;
    });
  }

  void _armPostOnboardingLocalReadyPrompt() {
    _postOnboardingLocalReadyPromptPending = true;
  }

  Future<void> _maybeShowPostOnboardingLocalReadyPrompt() async {
    if (!_postOnboardingLocalReadyPromptPending || !mounted) return;
    final ready = await _awaitStableLocalReadyForPrompt(
      total: const Duration(seconds: 35),
    );
    if (!ready || !mounted) {
      _postOnboardingLocalReadyPromptPending = false;
      _clearBlockingProgress();
      _showSnack('Yerel bağlantı henüz stabil değil, biraz daha bekleniyor...');
      return;
    }
    _postOnboardingLocalReadyPromptPending = false;
    _clearBlockingProgress();
    await _onboardingAskCloudAfterLocalReady();
  }

  bool _localReadyForOnboardingPrompt() {
    if (!connected || state == null) return false;
    final now = DateTime.now();
    final ts = _lastLocalOkAt;
    if (ts == null || now.difference(ts) >= const Duration(seconds: 45)) {
      return false;
    }
    final upd = _lastUpdate;
    if (upd == null || now.difference(upd) >= const Duration(seconds: 45)) {
      return false;
    }
    return true;
  }

  Future<bool> _awaitStableLocalReadyForPrompt({
    Duration total = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(total);
    var attempt = 0;
    var unauthorizedHits = 0;
    while (DateTime.now().isBefore(deadline)) {
      attempt += 1;
      _setBlockingProgress(
        title: t.t('please_wait'),
        body: t.t('onb_wait_device_discovery'),
      );
      debugPrint(
        '[ONB] local-ready check attempt=$attempt base=${api.baseUrl}',
      );

      if (_localReadyForOnboardingPrompt()) return true;

      try {
        final reachable = await api.testConnection();
        if (reachable) {
          final s = await api.fetchState();
          if (s != null) {
            unauthorizedHits = 0;
            if (mounted) {
              setState(() {
                state = s;
                connected = true;
                _lastUpdate = DateTime.now();
                _syncAutoHumControlsFromState(s);
              });
            } else {
              state = s;
              connected = true;
              _lastUpdate = DateTime.now();
            }
            _lastLocalOkAt = DateTime.now();
            _localDnsFailUntil = null;
            _localUnreachableUntil = null;
            debugPrint('[ONB] local-ready success');
            return true;
          } else if ((api.lastErrCode ?? '').toLowerCase() == 'unauthorized') {
            unauthorizedHits++;
            debugPrint(
              '[ONB] local-ready unauthorized hit=$unauthorizedHits base=${api.baseUrl}',
            );
            if (unauthorizedHits >= 3) {
              // Do not treat unauthorized as success; try to repair owner session
              // and keep waiting for an authenticated local-ready state.
              await api.ensureOwnerSession();
              debugPrint(
                '[ONB] local-ready unauthorized persisted; waiting for authenticated readiness',
              );
            }
          }
        }
      } catch (e) {
        if (_looksLikeDnsLookupFailure(e) &&
            !_baseHostLooksLikeIpv4(api.baseUrl)) {
          _markLocalDnsFailure();
        } else if (_looksLikeLocalUnreachable(e)) {
          _markLocalUnreachable();
        }
        unauthorizedHits = 0;
      }

      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
    debugPrint('[ONB] local-ready timeout');
    return false;
  }

  Future<bool> _awaitCloudEnableAckForOnboarding({
    Duration total = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(total);
    var attempt = 0;
    while (DateTime.now().isBefore(deadline)) {
      attempt += 1;
      debugPrint('[ONB] cloud-enable ack check attempt=$attempt');
      try {
        final reachable = await api.testConnection();
        if (reachable) {
          final s = await api.fetchState();
          if (s != null) {
            if (mounted) {
              setState(() {
                state = s;
                connected = true;
                _lastUpdate = DateTime.now();
                _syncAutoHumControlsFromState(s);
              });
            } else {
              state = s;
              connected = true;
              _lastUpdate = DateTime.now();
            }
            _lastLocalOkAt = DateTime.now();
            _localDnsFailUntil = null;
            _localUnreachableUntil = null;

            final cloudState = s.cloudState.trim().toUpperCase();
            final mqttState = s.cloudMqttState.trim().toUpperCase();
            final enabledSignal =
                s.cloudEnabled ||
                cloudState == 'CONNECTED' ||
                cloudState == 'LINKED' ||
                cloudState == 'PROVISIONING' ||
                cloudState == 'SETUP_REQUIRED' ||
                cloudState == 'DEGRADED' ||
                mqttState == 'CONNECTED' ||
                mqttState == 'READY' ||
                mqttState == 'SETUP_REQUIRED';
            if (enabledSignal) {
              debugPrint(
                '[ONB] cloud-enable ack success state=$cloudState mqtt=$mqttState enabled=${s.cloudEnabled}',
              );
              return true;
            }
          }
        }
      } catch (e) {
        if (_looksLikeDnsLookupFailure(e) &&
            !_baseHostLooksLikeIpv4(api.baseUrl)) {
          _markLocalDnsFailure();
        } else if (_looksLikeLocalUnreachable(e)) {
          _markLocalUnreachable();
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
    debugPrint('[ONB] cloud-enable ack timeout');
    return false;
  }

  String _effectiveCloudStateUpper() {
    final fromDevice = ((state?.cloudState ?? state?.cloudMqttState) ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (fromDevice.isNotEmpty && fromDevice != 'UNKNOWN') return fromDevice;
    final fromApi = (_cloudApiState ?? '').trim().toUpperCase();
    if (fromApi.isNotEmpty && fromApi != 'UNKNOWN') return fromApi;
    if (!_cloudUserEnabledLocal) return 'DISABLED';
    return '';
  }

  bool _cloudEnabledByDeviceSignal() {
    if (state?.cloudEnabled == true) return true;
    final s = _effectiveCloudStateUpper();
    if (s.isEmpty) return false;
    return s == 'CONNECTED' ||
        s == 'LINKED' ||
        s == 'PROVISIONING' ||
        s == 'SETUP_REQUIRED' ||
        s == 'DEGRADED';
  }

  bool _cloudEnabledEffective() {
    if (_cloudEnabledByDeviceSignal()) return true;
    if (!_cloudUserEnabledLocal) return false;
    // If this phone already sees the selected device in its cloud inventory,
    // do not require a fresh local device signal. Otherwise cloud/local can
    // deadlock when the device has moved to cloud but local mDNS/IP is stale.
    if (_cloudCommandEligibleForActive()) return true;
    return false;
  }

  bool _activeDeviceInCloudList() {
    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return false;
    return _cloudApiDeviceIds.contains(id6);
  }

  bool _cloudMembershipKnownForActive() {
    if (!_cloudLoggedIn()) return false;
    // Unknown must stay unknown until we actually receive a cloud device list
    // or an explicit deviceCount from backend.
    return _cloudApiDeviceIds.isNotEmpty || _cloudApiDeviceCount != null;
  }

  bool _cloudLinkedHintForActive() {
    final active = _activeDevice;
    if (active != null && active.cloudLinked) return true;
    final s = state;
    if (s == null) return false;
    final cloudState = s.cloudState.trim().toUpperCase();
    final mqttState = s.cloudMqttState.trim().toUpperCase();
    if (s.cloudMqttConnected) return true;
    if (cloudState == 'CONNECTED' || cloudState == 'LINKED') return true;
    if (mqttState == 'CONNECTED') return true;
    return false;
  }

  bool _activeDeviceOwnedByCurrentCloudUser() {
    return _activeDeviceInCloudList() &&
        (_activeDevice?.cloudRole ?? '').trim().toUpperCase() == 'OWNER';
  }

  bool _cloudCommandEligibleForActive() {
    if (!_cloudLoggedIn()) return false;
    final now = DateTime.now();
    final activeId6 = _deviceId6ForMqtt();
    if (activeId6 != null && activeId6.isNotEmpty && _cloudPreferActive(now)) {
      debugPrint('[CLOUD] eligible via prefer window id6=$activeId6');
      return true;
    }
    if (_activeDeviceInCloudList()) return true;
    final membershipKnown = _cloudMembershipKnownForActive();
    final linkedHint = _cloudLinkedHintForActive();
    // Prefer cloud whenever active device has a strong local linked signal.
    // This avoids false negatives when `/devices` is empty/stale on mobile
    // networks while device MQTT is already connected.
    if (linkedHint) {
      debugPrint(
        membershipKnown
            ? '[CLOUD] eligible via linked hint'
            : '[CLOUD] eligible via linked hint (membership unknown)',
      );
      return true;
    }
    // Last-resort fallback: when cloud membership is temporarily unknown
    // (token refresh race, /devices timeout, mobile network switch), prefer
    // attempting cloud with active id6 instead of forcing local .local path.
    // Backend auth/ownership checks still apply server-side.
    if (!membershipKnown) {
      final id6 = _deviceId6ForMqtt();
      if (id6 != null && id6.isNotEmpty) {
        debugPrint('[CLOUD] eligible via id6 fallback (membership unknown)');
        return true;
      }
    }
    debugPrint(
      '[CLOUD] ineligible active device '
      'membershipKnown=$membershipKnown '
      'linkedHint=$linkedHint '
      'id6=${_deviceId6ForMqtt() ?? '-'} '
      'apiIds=${_cloudApiDeviceIds.length} '
      'apiCount=${_cloudApiDeviceCount?.toString() ?? 'null'}',
    );
    return false;
  }

  String? _effectiveCloudEndpointNormalized() {
    final local = _normalizeCloudEndpointForDevice(state?.cloudIotEndpoint);
    if (local != null && local.isNotEmpty) return local;
    final cached = _normalizeCloudEndpointForDevice(_cloudIotEndpoint);
    if (cached != null && cached.isNotEmpty) return cached;
    return null;
  }

  bool _cloudEndpointMissingForActive() {
    final reason = (state?.cloudStateReason ?? '').trim().toLowerCase();
    if (reason == 'no_endpoint') return true;
    return _effectiveCloudEndpointNormalized() == null;
  }

  String _cloudSetupSubtitle() {
    final s = (_cloudSetupStatus ?? '').trim();
    if (s.isNotEmpty) return s;
    if (!_isOwnerRole()) {
      return _literal('Bu ayar sadece owner tarafindan degistirilebilir');
    }
    if (_cloudUserEnabledLocal && _cloudEndpointMissingForActive()) {
      return _literal(
        'Cloud endpoint ayarlı değil; firmware cloud secret ayarlarını tamamlayın',
      );
    }
    if (_cloudUserEnabledLocal &&
        !_cloudCommandEligibleForActive() &&
        _cloudMembershipKnownForActive()) {
      return _literal(
        'Cloud açık ama seçili cihaz bu hesaba bağlı değil; local kontrol kullanılacak',
      );
    }
    if (_cloudEnabledEffective()) {
      return _literal('Cloud aktif (MQTT baglaninca oncelikli)');
    }
    return _literal('Kapali (sadece local)');
  }

  bool _cloudStateLooksReady(DeviceState? s) {
    if (s == null) return false;
    final updatedAtMs = s.cloudStateUpdatedAtMs;
    final freshEnough =
        updatedAtMs > 0 &&
        (DateTime.now().millisecondsSinceEpoch - updatedAtMs) <= 45000;
    if (!freshEnough) return false;
    if (s.cloudMqttConnected) return true;
    final cloudState = s.cloudState.trim().toUpperCase();
    final mqttState = s.cloudMqttState.trim().toUpperCase();
    return cloudState == 'CONNECTED' ||
        mqttState == 'CONNECTED' ||
        mqttState == 'READY';
  }

  bool _cloudBringupNeeded() {
    if (!_cloudLoggedIn()) return false;
    if (!_cloudUserEnabledLocal) return false;
    if (_cloudStartupClaimInFlight) return false;
    if (_cloudStartupClaimRetryAt != null &&
        DateTime.now().isBefore(_cloudStartupClaimRetryAt!)) {
      return false;
    }
    if (_cloudClaimNeedsQrRefresh) {
      _cloudSetupTerminalError = 'claim_proof_mismatch';
      _cloudSetupStatus = _literal(
        'Cloud claim doğrulaması eşleşmedi. IR ile pair/recovery penceresini açıp Bluetooth kurulumunu yenileyin.',
      );
      return false;
    }
    final reason = (state?.cloudStateReason ?? '').trim().toLowerCase();
    final noEndpoint = reason == 'no_endpoint';

    // If firmware/cloud secrets are missing, claiming/recovery retries are noisy and pointless.
    if (noEndpoint) {
      _cloudSetupTerminalError = 'no_endpoint';
      _cloudSetupStatus = _literal(
        'Cloud endpoint ayarlı değil (firmware cloud secret eksik).',
      );
      return false;
    }

    // Auto-clear previous terminal no_endpoint lock once firmware reports a valid reason/state.
    final terminalErr = (_cloudSetupTerminalError ?? '').trim();
    if (terminalErr == 'no_endpoint') {
      _cloudSetupTerminalError = null;
      if ((_cloudSetupStatus ?? '').trim().isNotEmpty &&
          (_cloudSetupStatus ?? '').contains('endpoint')) {
        _cloudSetupStatus = null;
      }
    } else if (terminalErr.isNotEmpty) {
      final retryable =
          terminalErr == 'already_claimed' ||
          terminalErr == 'claim_proof_required' ||
          terminalErr == 'cloud_setup_failed';
      if (!retryable) return false;
      _cloudSetupTerminalError = null;
    }

    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return false;
    if (_cloudCommandEligibleForActive()) {
      if (!_cloudMqttReady()) return true;
      // MQTT connected but backend membership/list can still be missing
      // (e.g. not_member / stale cloud inventory). Allow owner auto-repair.
      if (!_activeDeviceInCloudList() && _isOwnerRole()) {
        debugPrint(
          '[CLOUD][BRINGUP] eligible+mqtt but not listed -> auto repair',
        );
        return true;
      }
      return false;
    }
    return _isOwnerRole();
  }

  String? _cloudTerminalStatusForClaimError(String err) {
    switch (err.trim()) {
      case 'claim_proof_mismatch':
        return _literal(
          'Cloud baglanamadi. Pair token cloud kaydiyla uyusmuyor; sahiplik recovery gerekebilir.',
        );
      case 'already_claimed':
        return _literal(
          'Cloud baglanamadi. Cihaz baska bir hesaba bagli gorunuyor.',
        );
      case 'claim_proof_required':
        return _literal(
          'Cloud baglanamadi. Cihaz icin guncel Bluetooth dogrulama oturumu gerekli.',
        );
      default:
        return null;
    }
  }

  String _cloudClaimErrorMessage(String err) {
    switch (err.trim()) {
      case 'claim_proof_required':
        return _literal(
          'Claim doğrulaması başarısız. Cihaz doğrulama oturumu eksik veya geçersiz.',
        );
      case 'claim_proof_mismatch':
        return _literal(
          'Claim proof uyuşmuyor. Kayıtlı doğrulama bilgisi temizlendi; IR ile pair/recovery penceresini açıp Bluetooth kurulumunu tekrar deneyin.',
        );
      case 'already_claimed':
        return _literal('Cihaz başka bir hesap tarafından sahiplenilmiş.');
      case 'recovery_claim_proof_unavailable':
        return _literal(
          'Recovery için cihazın güncel claim bilgisi cloud state/shadow üzerinde henüz görünmüyor.',
        );
      case 'recovery_confirmation_required':
        return _literal('Recovery işlemi için açık kullanıcı onayı gerekli.');
      default:
        return _literal('Cihazı sahiplenme başarısız');
    }
  }

  Future<bool> _promptCloudOwnershipRecovery({
    required String id6,
    required String claimSecret,
    required String? userIdHash,
  }) async {
    if (!mounted) return false;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.literal('Eski sahipliği kaldır')),
            content: const Text(
              'Bu cihaz başka bir cloud sahipliği ile kayıtlı görünüyor. Devam edersen eski cloud sahipliği kaldırılacak, mevcut üyeler ve bekleyen davetler iptal edilip cihaz bu hesaba yeniden bağlanacak.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(t.literal('Vazgeç')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(t.literal('Kaldır ve yeniden kur')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return false;

    _showSnack('Eski cloud sahipliği kaldırılıyor...');
    await _cloudRefreshIfNeeded();
    final ok = await cloudApi.recoverOwnership(
      id6,
      const Duration(seconds: 10),
      claimSecret: claimSecret,
      userIdHash: userIdHash,
      ownerPubKeyB64: _cloudOwnerPubKeyB64(),
      deviceBrand: _activeDevice?.brand,
      deviceSuffix: _activeDevice?.suffix,
    );
    if (!ok) {
      if (!mounted) return false;
      _showSnack(
        _cloudClaimErrorMessage((cloudApi.lastClaimError ?? '').trim()),
      );
      return false;
    }

    await _syncCloudDevices(
      autoSelectIfNeeded: false,
      showSnack: false,
      force: true,
    );
    await _refreshOwnerFromCloud();
    await _refreshCloudMembers(force: true);
    await _refreshCloudIntegrations(force: true);
    if (_cloudInvitesSupported()) {
      await _refreshCloudInvites(force: true);
    }
    _cloudSetupTerminalError = null;
    _cloudSetupStatus = 'Bulut hazir';
    _startCloudPreferWindow();
    if (state != null) {
      state!.cloudClaimed = true;
    }
    final setupCreds = await _loadBleSetupCredsForId6(id6);
    final setupUser = (setupCreds?['user'] ?? '').trim();
    final setupPass = (setupCreds?['pass'] ?? '').trim();
    if (setupUser.isNotEmpty && setupPass.isNotEmpty) {
      await _maybeFinalizeLocalOwnerAfterCloudClaim(
        id6: id6,
        setupUser: setupUser,
        setupPass: setupPass,
        source: 'recover_ownership',
      );
    }
    if (mounted) setState(() {});
    _showSnack('Eski sahiplik kaldırıldı. Cihaz bu hesaba bağlandı.');
    return true;
  }

  Future<void> _invalidateActiveClaimToken({
    String reason = 'claim_proof_mismatch',
  }) async {
    _cloudClaimNeedsQrRefresh = true;

    final detail =
        'Cloud claim doğrulaması ($reason) başarısız. Local kontrol korunuyor; cloud için QR\'ı yeniden okutun.';
    _setClaimFlowStage(_ClaimFlowStage.waitingQr, detail: detail);
    if (mounted) {
      _showSnack(
        'Cloud doğrulaması eşleşmedi. Local kontrol devam eder; cloud için QR kodunu yeniden okutun.',
      );
    }
    debugPrint('[CLOUD][CLAIM] token marked stale for cloud reason=$reason');
  }

  Future<bool> _ensureCloudReadyForActiveDevice({
    bool force = false,
    bool showSnack = false,
  }) async {
    if (_cloudSetupInFlight) return false;
    if (!_cloudBringupNeeded()) {
      return _cloudCommandEligibleForActive() && _cloudMqttReady();
    }

    final now = DateTime.now();
    if (!force &&
        _cloudSetupLastAttemptAt != null &&
        now.difference(_cloudSetupLastAttemptAt!) <
            const Duration(seconds: 15)) {
      return false;
    }

    String statusText = 'Bulut baglantisi hazirlaniyor...';
    void updateStatus(String value) {
      statusText = value;
      _cloudSetupStatus = value;
      if (mounted) setState(() {});
    }

    void setTerminalFailure(String err, String status) {
      _cloudSetupTerminalError = err.trim().isEmpty
          ? 'cloud_setup_failed'
          : err;
      updateStatus(status);
    }

    _cloudSetupInFlight = true;
    _cloudSetupLastAttemptAt = now;
    updateStatus(statusText);

    try {
      if (!_cloudLoggedIn()) {
        _cloudSetupTerminalError = null;
        updateStatus('Cloud oturumu gerekli');
        return false;
      }
      final id6 = await _resolveDeviceId6ForCloudAction();
      if (id6 == null || id6.isEmpty) {
        updateStatus('Cihaz kimligi bulunamadi');
        return false;
      }
      final localCloudReason = (state?.cloudStateReason ?? '')
          .trim()
          .toLowerCase();
      if (localCloudReason == 'no_endpoint') {
        setTerminalFailure(
          'no_endpoint',
          'Cloud endpoint ayarlı değil (firmware cloud secret eksik).',
        );
        return false;
      }

      final claimSecret = await _resolveActivePairToken();
      final userIdHash = _cloudUserIdHash();
      final canAttemptClaim =
          _isOwnerRole() &&
          claimSecret != null &&
          claimSecret.isNotEmpty &&
          userIdHash != null &&
          userIdHash.isNotEmpty;

      final attempts = force ? 5 : 2;
      for (var attempt = 0; attempt < attempts; attempt++) {
        final refreshed = await _cloudRefreshIfNeeded();
        if (!_cloudAuthReady(DateTime.now()) && !refreshed) {
          updateStatus('Cloud oturumu yenilenemedi');
          return false;
        }

        updateStatus('Cloud hesabi kontrol ediliyor...');
        await _syncCloudDevices(
          autoSelectIfNeeded: false,
          showSnack: false,
          force: true,
        );

        var listed = _cloudApiDeviceIds.contains(id6);
        if (!listed && canAttemptClaim) {
          _cloudSetupTerminalError = null;
          updateStatus('Cihaz cloud hesabina ekleniyor...');
          final claimed = await cloudApi.claimDeviceWithAutoSync(
            id6,
            const Duration(seconds: 20),
            claimSecret: claimSecret,
            userIdHash: userIdHash,
            ownerPubKeyB64: _cloudOwnerPubKeyB64(),
            deviceBrand: _activeDevice?.brand,
            deviceSuffix: _activeDevice?.suffix,
          );
          debugPrint(
            '[CLOUD][BRINGUP] claim attempt=${attempt + 1} ok=$claimed '
            'err=${cloudApi.lastClaimError ?? "-"} '
            'status=${cloudApi.lastClaimHttpStatus ?? "-"}',
          );
          if (!claimed) {
            final claimErr = (cloudApi.lastClaimError ?? '').trim();
            final terminalStatus = _cloudTerminalStatusForClaimError(claimErr);
            if (terminalStatus != null) {
              final canRecover =
                  showSnack &&
                  (claimErr == 'already_claimed' ||
                      claimErr == 'claim_proof_mismatch') &&
                  claimSecret.isNotEmpty;
              if (canRecover) {
                final recovered = await _promptCloudOwnershipRecovery(
                  id6: id6,
                  claimSecret: claimSecret,
                  userIdHash: userIdHash,
                );
                if (recovered) {
                  await _syncCloudDevices(
                    autoSelectIfNeeded: false,
                    showSnack: false,
                    force: true,
                  );
                  listed = _cloudApiDeviceIds.contains(id6);
                  if (listed) continue;
                }
              }
              if (claimErr == 'already_claimed' ||
                  claimErr == 'claim_proof_required') {
                await _syncCloudDevices(
                  autoSelectIfNeeded: false,
                  showSnack: false,
                  force: true,
                );
                listed = _cloudApiDeviceIds.contains(id6);
                if (listed) continue;
                _cloudStartupClaimRetryAt = DateTime.now().add(
                  const Duration(seconds: 20),
                );
                _cloudSetupTerminalError = null;
                updateStatus(
                  'Cloud sahiplik yayilimi bekleniyor; otomatik tekrar denenecek.',
                );
                if (showSnack) {
                  _showSnack(
                    'Cloud sahiplik bilgisi bekleniyor. Uygulama otomatik tekrar deneyecek.',
                  );
                }
                return false;
              }
              if (claimErr == 'claim_proof_mismatch') {
                await _invalidateActiveClaimToken(reason: claimErr);
              }
              setTerminalFailure(claimErr, terminalStatus);
              if (showSnack) _showSnack(terminalStatus);
              return false;
            }
          }
          await _syncCloudDevices(
            autoSelectIfNeeded: false,
            showSnack: false,
            force: true,
          );
          listed = _cloudApiDeviceIds.contains(id6);
        }

        DeviceState? cloudState;
        if (listed) {
          updateStatus('Bulut durumu dogrulaniyor...');
          cloudState = await cloudApi.fetchState(id6, kCloudConnectTimeout);
          if (cloudState != null) {
            _cloudOwnerExistsOverride = cloudState.ownerExists;
            _cloudOwnerSetupDoneOverride = cloudState.ownerSetupDone;
            if (_cloudStateLooksReady(cloudState)) {
              _markCloudOk();
            }
          }
        }

        final readyByState = listed && _cloudStateLooksReady(cloudState);
        if (readyByState) {
          updateStatus('Bulut komutu test ediliyor...');
          final probeOk = await cloudApi.sendDesiredState(
            id6,
            <String, dynamic>{
              'appDebugPing': true,
              'appDebugTs': DateTime.now().millisecondsSinceEpoch,
            },
            const Duration(seconds: 6),
            allowFallbackCmd: true,
          );
          if (probeOk) {
            _cloudSetupTerminalError = null;
            _markCloudOk();
            _startCloudPreferWindow();
            await _syncCloudDevices(
              autoSelectIfNeeded: false,
              showSnack: false,
              force: true,
            );
            await _refreshOwnerFromCloud();
            await _refreshCloudMembers(force: true);
            if (_cloudInvitesSupported()) {
              await _refreshCloudInvites(force: true);
            }
            updateStatus('Bulut hazir');
            if (showSnack) {
              _showSnack('Bulut hazir. Cihaz uzaktan kullanima acik.');
            }
            return true;
          }
        }

        if (attempt < attempts - 1) {
          updateStatus('Bulut baglaniyor, tekrar kontrol ediliyor...');
          await Future.delayed(Duration(seconds: 2 + attempt * 2));
        }
      }

      updateStatus(
        _cloudCommandEligibleForActive()
            ? 'Bulut aciliyor. Uygulama arka planda kontrol etmeye devam edecek.'
            : 'Cloud acildi. Cihaz hesaba baglanana kadar kontrol suruyor.',
      );
      if (showSnack) {
        _showSnack(_cloudSetupStatus!);
      }
      return false;
    } finally {
      _cloudSetupInFlight = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _recoverCloudEnableForActiveDevice() async {
    if (!_cloudLoggedIn()) return;
    final refreshedLocal =
        await _fetchStateSmart(force: true) ?? await api.fetchState();
    if (refreshedLocal != null) {
      state = refreshedLocal;
      if (mounted) setState(() {});
    }
    final reason =
        (refreshedLocal?.cloudStateReason ?? state?.cloudStateReason ?? '')
            .trim()
            .toLowerCase();
    if (reason == 'no_endpoint') {
      final endpoint = _effectiveCloudEndpointNormalized();
      if (endpoint != null && endpoint.isNotEmpty) {
        final sent = await _send({
          'cloud': {
            'enabled': true,
            'endpoint': endpoint,
            'iotEndpoint': endpoint,
          },
        }, forceLocalOnly: true);
        if (sent) {
          final refreshed =
              await _fetchStateSmart(force: true) ?? await api.fetchState();
          if (refreshed != null) {
            state = refreshed;
            if (mounted) setState(() {});
          }
          final retryReason = (state?.cloudStateReason ?? '')
              .trim()
              .toLowerCase();
          if (retryReason != 'no_endpoint') {
            _cloudSetupTerminalError = null;
            _cloudSetupStatus = null;
            if (mounted) setState(() {});
            return;
          }
        }
      }
      _cloudSetupTerminalError = 'no_endpoint';
      _cloudSetupStatus =
          'Cloud endpoint ayarlı değil (firmware cloud secret eksik).';
      if (mounted) setState(() {});
      return;
    }
    final id6 = await _resolveDeviceId6ForCloudAction();
    if (id6 == null || id6.isEmpty) return;

    final refreshed = await _cloudRefreshIfNeeded();
    if (!_cloudAuthReady(DateTime.now()) && !refreshed) return;

    await _syncCloudDevices(
      autoSelectIfNeeded: false,
      showSnack: false,
      force: true,
    );

    final alreadyListed = _cloudApiDeviceIds.contains(id6);
    final claimSecret = await _resolveActivePairToken();
    final userIdHash = _cloudUserIdHash();
    final canAttemptClaim =
        _isOwnerRole() &&
        claimSecret != null &&
        claimSecret.isNotEmpty &&
        userIdHash != null &&
        userIdHash.isNotEmpty;

    if (!alreadyListed && canAttemptClaim) {
      final ok = await cloudApi.claimDeviceWithAutoSync(
        id6,
        const Duration(seconds: 8),
        claimSecret: claimSecret,
        userIdHash: userIdHash,
        ownerPubKeyB64: _cloudOwnerPubKeyB64(),
        deviceBrand: _activeDevice?.brand,
        deviceSuffix: _activeDevice?.suffix,
      );
      debugPrint(
        '[CLOUD][ENABLE] recovery claim id6=$id6 ok=$ok '
        'err=${cloudApi.lastClaimError ?? "-"} '
        'status=${cloudApi.lastClaimHttpStatus ?? "-"}',
      );
    }

    await _syncCloudDevices(autoSelectIfNeeded: false, showSnack: false);
    await _refreshOwnerFromCloud();
    await _refreshCloudMembers(force: true);
    await _refreshCloudIntegrations(force: true);
    if (_cloudInvitesSupported()) {
      await _refreshCloudInvites(force: true);
    }
    if (_cloudBringupNeeded()) {
      unawaited(
        _ensureCloudReadyForActiveDevice(force: false, showSnack: false),
      );
    }
  }

  Future<bool> _cloudRefreshIfNeeded() async {
    if (_transportRecoveryBlocked(reason: 'cloud_refresh')) return false;
    if (_cloudRefreshToken == null || _cloudRefreshToken!.isEmpty) return false;
    final now = DateTime.now();
    if (_cloudRefreshBlockedUntil != null &&
        now.isBefore(_cloudRefreshBlockedUntil!)) {
      return false;
    }
    if (_cloudIdToken != null && _cloudIdToken!.isNotEmpty) {
      if (_cloudTokenExp != null &&
          now.isBefore(_cloudTokenExp!.subtract(const Duration(minutes: 2)))) {
        return true;
      }
    }
    final existing = _cloudRefreshFuture;
    if (existing != null) {
      return await existing;
    }
    final cognitoBase = _cloudCognitoBaseUrl();
    if (cognitoBase.isEmpty) return false;
    final url = Uri.parse('$cognitoBase/oauth2/token');
    final body = {
      'grant_type': 'refresh_token',
      'client_id': kCognitoClientId,
      'refresh_token': _cloudRefreshToken!,
    };
    final future = () async {
      try {
        final r = await http
            .post(
              url,
              headers: const {
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 8));
        if (r.statusCode < 200 || r.statusCode >= 300) {
          _cloudRefreshBlockedUntil = DateTime.now().add(
            const Duration(seconds: 5),
          );
          return false;
        }
        final obj = jsonDecode(r.body);
        if (obj is! Map) {
          _cloudRefreshBlockedUntil = DateTime.now().add(
            const Duration(seconds: 5),
          );
          return false;
        }
        final idToken = (obj['id_token'] ?? '').toString();
        if (idToken.isEmpty) {
          _cloudRefreshBlockedUntil = DateTime.now().add(
            const Duration(seconds: 5),
          );
          return false;
        }
        _cloudIdToken = idToken;
        _cloudTokenExp = _parseJwtExp(_cloudIdToken!);
        _cloudUserEmail = _parseJwtEmail(_cloudIdToken!) ?? _cloudUserEmail;
        _cloudRefreshBlockedUntil = null;
        await _saveCloudAuth();
        _logCloudIdToken('refresh');
        return true;
      } catch (_) {
        _cloudRefreshBlockedUntil = DateTime.now().add(
          const Duration(seconds: 5),
        );
        return false;
      }
    }();
    _cloudRefreshFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_cloudRefreshFuture, future)) {
        _cloudRefreshFuture = null;
      }
    }
  }

  Future<void> _refreshOwnerFromCloud() async {
    final now = DateTime.now();
    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return;
    if (!_cloudCommandEligibleForActive()) return;
    if (!_cloudReady(now)) return;
    final refreshed = await _cloudRefreshIfNeeded();
    if (!_cloudAuthReady(now) && !refreshed) return;
    final needsFeatureRefresh =
        _cloudFeaturesFetchedAt == null ||
        now.difference(_cloudFeaturesFetchedAt!) > const Duration(minutes: 5);
    if (needsFeatureRefresh) {
      try {
        final me = await cloudApi.fetchMe(const Duration(seconds: 8));
        _applyCloudFeaturesFromMe(me);
      } catch (_) {}
    }
    if (!_cloudShadowStateSupported()) return;
    try {
      final cloudState = await cloudApi.fetchState(id6, kCloudConnectTimeout);
      if (cloudState == null) return;
      _cloudOwnerExistsOverride = cloudState.ownerExists;
      _cloudOwnerSetupDoneOverride = cloudState.ownerSetupDone;
      if (state != null) {
        state!.cloudClaimed = cloudState.cloudClaimed;
      }
      if (state == null) {
        setState(() {
          state = cloudState;
        });
        return;
      }
      if (state!.ownerExists != cloudState.ownerExists ||
          state!.ownerSetupDone != cloudState.ownerSetupDone) {
        setState(() {
          state!.ownerExists = cloudState.ownerExists;
          state!.ownerSetupDone = cloudState.ownerSetupDone;
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshCloudMembers({bool force = false}) async {
    final now = DateTime.now();
    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return;
    if (!_cloudLoggedIn()) return;
    if (!_cloudReady(now)) return;
    if (_cloudMembersLoading) return;
    if (!force &&
        _cloudMembersFetchedAt != null &&
        now.difference(_cloudMembersFetchedAt!) < const Duration(seconds: 15)) {
      return;
    }

    if (mounted) {
      setState(() {
        _cloudMembersLoading = true;
        _cloudMembersErr = null;
      });
    } else {
      _cloudMembersLoading = true;
      _cloudMembersErr = null;
    }

    try {
      final refreshed = await _cloudRefreshIfNeeded();
      if (!_cloudAuthReady(now) && !refreshed) {
        if (mounted) {
          setState(() {
            _cloudMembersLoading = false;
            _cloudMembersErr = 'cloud_auth_required';
          });
        } else {
          _cloudMembersLoading = false;
          _cloudMembersErr = 'cloud_auth_required';
        }
        return;
      }

      final members = await cloudApi.listMembers(
        id6,
        const Duration(seconds: 8),
      );
      if (mounted) {
        setState(() {
          _cloudMembers = members;
          _cloudMembersFetchedAt = DateTime.now();
          _cloudMembersLoading = false;
          _cloudMembersErr = members == null ? 'cloud_members_failed' : null;
        });
      } else {
        _cloudMembers = members;
        _cloudMembersFetchedAt = DateTime.now();
        _cloudMembersLoading = false;
        _cloudMembersErr = members == null ? 'cloud_members_failed' : null;
      }
    } catch (e) {
      debugPrint('[CLOUD][MEMBERS] refresh error: $e');
      if (mounted) {
        setState(() {
          _cloudMembersLoading = false;
          _cloudMembersErr = 'cloud_members_failed';
        });
      } else {
        _cloudMembersLoading = false;
        _cloudMembersErr = 'cloud_members_failed';
      }
    }
  }

  Future<void> _refreshCloudInvites({bool force = false}) async {
    final now = DateTime.now();
    final id6 = _deviceId6ForMqtt();
    if (id6 == null || id6.isEmpty) return;
    if (!_cloudLoggedIn()) return;
    if (!_cloudReady(now)) return;
    if (!_cloudInvitesSupported()) return;
    if (_cloudInvitesLoading) return;
    if (!force &&
        _cloudInvitesFetchedAt != null &&
        now.difference(_cloudInvitesFetchedAt!) < const Duration(seconds: 15)) {
      return;
    }

    if (mounted) {
      setState(() {
        _cloudInvitesLoading = true;
        _cloudInvitesErr = null;
      });
    } else {
      _cloudInvitesLoading = true;
      _cloudInvitesErr = null;
    }

    try {
      final refreshed = await _cloudRefreshIfNeeded();
      if (!_cloudAuthReady(now) && !refreshed) {
        if (mounted) {
          setState(() {
            _cloudInvitesLoading = false;
            _cloudInvitesErr = 'cloud_auth_required';
          });
        } else {
          _cloudInvitesLoading = false;
          _cloudInvitesErr = 'cloud_auth_required';
        }
        return;
      }

      final invites = await cloudApi.listInvites(
        id6,
        const Duration(seconds: 8),
      );
      if (mounted) {
        setState(() {
          _cloudInvites = invites;
          _cloudInvitesFetchedAt = DateTime.now();
          _cloudInvitesLoading = false;
          _cloudInvitesErr = invites == null ? 'cloud_invites_failed' : null;
        });
      } else {
        _cloudInvites = invites;
        _cloudInvitesFetchedAt = DateTime.now();
        _cloudInvitesLoading = false;
        _cloudInvitesErr = invites == null ? 'cloud_invites_failed' : null;
      }
    } catch (e) {
      debugPrint('[CLOUD][INVITES] refresh error: $e');
      if (mounted) {
        setState(() {
          _cloudInvitesLoading = false;
          _cloudInvitesErr = 'cloud_invites_failed';
        });
      } else {
        _cloudInvitesLoading = false;
        _cloudInvitesErr = 'cloud_invites_failed';
      }
    }
  }

  DateTime? _lastCloudAutoClaimAt;
  DateTime? _lastLocalOwnerFinalizeAt;
  bool _localOwnerFinalizeInFlight = false;

  bool _cloudPreferActive(DateTime now) {
    if (_cloudPreferUntil == null || now.isAfter(_cloudPreferUntil!)) {
      return false;
    }
    // Prefer cloud only after device reports MQTT connected.
    return _cloudMqttReady();
  }

  // BLE timers are class-level so nested helpers can access them safely
  Timer? _bleReadTimer;
  Timer? _blePollCmdTimer;
  // BLE notify subscription holder (for cleanup)
  StreamSubscription<List<int>>? notifySub;
  final bool _qrBleConnectDialogOpen = false;
  bool _qrBleConnectInFlight = false;
  int? _bleLastTsMs;

  static const _ownerPrivD32Key = 'owner_priv_d32_b64';
  static const _ownerPubQ65Key = 'owner_pub_q65_b64';
  static const _clientPrivD32Key = 'client_priv_d32_b64';
  static const _clientPubQ65Key = 'client_pub_q65_b64';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _apDiscoveryRunning = false;
  // BLE kontrol kanalı (direkt ESP32 yönetimi için)
  BluetoothDevice? _bleCtrlDevice;
  BluetoothCharacteristic? _bleCtrlInfoChar;
  BluetoothCharacteristic? _bleCtrlCmdChar;
  StreamSubscription<List<int>>? _bleCtrlNotifySub;
  StreamSubscription<BluetoothConnectionState>? _bleCtrlConnSub;
  Timer? _bleCtrlStatusTimer;
  bool _bleControlMode = false;
  bool _bleCtrlConnecting = false;
  bool _bleManageSheetOpen = false;
  bool _bleAutoConnectAttempted = false;
  DateTime? _bleAutoLastAttemptAt;
  bool _bleSessionAuthed = false;
  Completer<bool>? _bleSessionAuthCompleter;
  Completer<String>? _bleNonceCompleter;
  Completer<bool>? _bleAuthCompleter;
  Completer<Map<String, dynamic>>? _bleInviteCompleter;
  String? _bleLastAuthErr;
  Completer<Map<String, dynamic>>? _bleNonceMapCompleter;
  String? _bleControlPairToken;
  List<int>? _ownerPrivD32;
  String? _ownerPubQ65B64;
  List<int>? _clientPrivD32;
  String? _clientPubQ65B64;
  String? _apSessionToken;
  String? _apSessionNonce;

  Completer<Map<String, String>>? _bleApSessionCompleter;
  Completer<Map<String, String>>? _bleApCredsCompleter;
  bool _themeUserSet = false;
  // OTA uyarısını uygulama her açılışında en fazla bir kez göstermek için bayrak
  bool _otaPromptShownThisSession = false;

  // WAQI tabanlı dış ortam hava kalitesi için yardımcı API.
  final OpenWeatherApi _weatherApi = OpenWeatherApi();
  WaqiLocation? _waqiLocation;
  WaqiInfo? _waqiInstantInfo;
  String? _waqiInstantDeviceId;
  List<WaqiLocation> _waqiRecent = const [];
  DateTime? _lastWaqiSnapshotPersistAt;
  bool _autoHumExpanded = false;
  bool _autoHumEnabled = false;
  double _autoHumTarget = 55;
  // Doa cihazları için otomatik sulama parametreleri
  double _doaWaterDurationMin = 2; // pompa çalışma süresi (dakika)
  double _doaWaterIntervalHr = 8; // sulama sıklığı (saat)
  bool _doaWaterAutoEnabled = false;
  bool _doaManualWaterOn = false;
  bool _doaHumAutoEnabled = false;
  bool _fanExpanded = false;
  bool _frameExpanded = false;
  late final AnimationController _fanSpinCtrl;

  String _themeModeKeyForBrand(String brand) {
    if (brand == kDoaDeviceBrand) return 'theme_mode_doa';
    if (brand == kDefaultDeviceBrand) return 'theme_mode';
    return 'theme_mode_${brand.toLowerCase()}';
  }

  String _themeUserSetKeyForBrand(String brand) {
    if (brand == kDoaDeviceBrand) return 'theme_user_set_doa';
    if (brand == kDefaultDeviceBrand) return 'theme_user_set';
    return 'theme_user_set_${brand.toLowerCase()}';
  }

  String _brandFromBleName(String name) {
    return brandFromBleName(name);
  }

  Future<void> _applyDetectedBrand(
    String nextBrand, {
    String reason = '',
  }) async {
    final dev = _activeDevice;
    if (dev == null) return;
    if (nextBrand.trim().isEmpty || dev.brand == nextBrand) return;
    dev.brand = nextBrand;
    final idx = _devices.indexWhere((d) => d.id == dev.id);
    if (idx != -1) _devices[idx].brand = nextBrand;
    if (mounted) {
      _safeSetState(() {});
    }
    debugPrint(
      '[BRAND] active device brand updated -> $nextBrand'
      '${reason.isNotEmpty ? ' ($reason)' : ''}',
    );
    await _saveDevicesToPrefs();
    await _applyThemeForBrand(nextBrand);
  }

  void _syncBrandFromBleRuntimeHint(String? bleName) {
    final hintBrand = _brandFromBleName(bleName ?? '');
    if (hintBrand.isEmpty) return;
    unawaited(_applyDetectedBrand(hintBrand, reason: 'ble_name'));
  }

  Future<void> _applyThemeForBrand(String brand) async {
    try {
      final p = await SharedPreferences.getInstance();
      final themeKey = _themeModeKeyForBrand(brand);
      final themeUserKey = _themeUserSetKeyForBrand(brand);
      final themeStr = p.getString(themeKey);
      _themeUserSet = p.getBool(themeUserKey) ?? false;
      if (!_themeUserSet) {
        final ThemeMode mode = brand == kDoaDeviceBrand
            ? ThemeMode.light
            : ThemeMode.dark;
        widget.onThemeChanged(mode);
      } else if (themeStr != null) {
        final ThemeMode mode = themeStr == 'light'
            ? ThemeMode.light
            : ThemeMode.dark;
        widget.onThemeChanged(mode);
      }
    } catch (_) {}
  }

  void _syncBrandFromFirmwareProduct(DeviceState s) {
    final resolved = resolveDeviceBrand(
      firmwareProduct: s.deviceProduct,
      bleName: _bleCtrlDevice?.platformName ?? '',
      baseUrl: api.baseUrl,
      mdnsHost: s.networkMdnsHost,
      apSsid: s.networkApSsid,
      currentBrand: _activeDevice?.brand ?? '',
    );
    final nextBrand = resolved.brand;
    if (nextBrand.isEmpty) return;
    final reason = resolved.source;
    unawaited(_applyDetectedBrand(nextBrand, reason: reason));
  }

  // Home dashboard grafikleri için basit history
  // Yaklaşık 1 aylık saatlik dilimler için: 24 * 30 = 720 nokta
  static const int _maxHistoryPoints = 24 * 30; // son 30 gün civarı
  final List<_HistoryPoint> _aqHistory = [];
  final List<_HistoryPoint> _cityAqHistory = [];
  final List<_HistoryPoint> _humHistory = [];
  final List<_HistoryPoint> _tempHistory = [];
  final List<_HistoryPoint> _pm25History = [];
  final List<_HistoryPoint> _rpmHistory = [];
  final List<_HistoryPoint> _vocHistory = [];
  final List<_HistoryPoint> _noxHistory = [];
  final List<_HistoryPoint> _aiTempHistory = [];
  final List<_HistoryPoint> _aiHumHistory = [];
  final List<_HistoryPoint> _aiPressHistory = [];
  final List<_HistoryPoint> _aiGasHistory = [];
  final List<_HistoryPoint> _aiIaqHistory = [];
  final List<_HistoryPoint> _aiCo2History = [];
  final List<_HistoryPoint> _aiBVocHistory = [];
  I18n get t => widget.i18n;

  void _syncAutoHumControlsFromState(DeviceState s) {
    _syncBrandFromFirmwareProduct(s);
    _autoHumEnabled = s.autoHumEnabled;
    _autoHumTarget = s.autoHumTarget.clamp(30, 70).toDouble();
    if (_isDoaDevice) {
      if (s.waterAutoEnabled != null) {
        _doaWaterAutoEnabled = s.waterAutoEnabled!;
      }
      if (s.waterDurationMin != null && s.waterDurationMin! > 0) {
        _doaWaterDurationMin = s.waterDurationMin!.clamp(1, 30).toDouble();
      }
      if (s.waterIntervalMin != null && s.waterIntervalMin! > 0) {
        final hr = (s.waterIntervalMin!.toDouble() / 60.0).clamp(1.0, 48.0);
        _doaWaterIntervalHr = hr;
      }
      if (s.waterManual != null) {
        _doaManualWaterOn = s.waterManual!;
      }
      if (s.waterHumAutoEnabled != null) {
        _doaHumAutoEnabled = s.waterHumAutoEnabled!;
      }
    }
  }

  bool _isNoopCommandAgainstState(Map<String, dynamic> body, DeviceState? s) {
    if (s == null || body.isEmpty) return false;
    bool hasComparable = false;
    for (final entry in body.entries) {
      final k = entry.key;
      final v = entry.value;
      if (k == 'cmdId' || k == 'userIdHash' || k == 'acl') continue;
      switch (k) {
        case 'masterOn':
          hasComparable = true;
          if ((v == true) != s.masterOn) return false;
          break;
        case 'lightOn':
          hasComparable = true;
          if ((v == true) != s.lightOn) return false;
          break;
        case 'cleanOn':
          hasComparable = true;
          if ((v == true) != s.cleanOn) return false;
          break;
        case 'ionOn':
          hasComparable = true;
          if ((v == true) != s.ionOn) return false;
          break;
        case 'mode':
          hasComparable = true;
          if ((v is num ? v.toInt() : int.tryParse('$v')) != s.mode) {
            return false;
          }
          break;
        case 'fanPercent':
          hasComparable = true;
          if ((v is num ? v.toInt() : int.tryParse('$v')) != s.fanPercent) {
            return false;
          }
          break;
        case 'autoHumEnabled':
          hasComparable = true;
          final b = (v is bool)
              ? v
              : ((v is num)
                    ? v != 0
                    : ('$v' == '1' || '$v'.toLowerCase() == 'true'));
          if (b != s.autoHumEnabled) return false;
          break;
        case 'autoHumTarget':
          hasComparable = true;
          if ((v is num ? v.toInt() : int.tryParse('$v')) != s.autoHumTarget) {
            return false;
          }
          break;
        case 'rgb':
          if (v is! Map) return false;
          final rgbKeys = v.keys.map((e) => '$e').toSet();
          // Cloud state does not reliably round-trip RGB color/brightness today.
          // If we noop-skip these payloads, real commands never leave the app.
          if (rgbKeys.any(
            (key) =>
                key == 'r' || key == 'g' || key == 'b' || key == 'brightness',
          )) {
            return false;
          }
          if (v.containsKey('on')) {
            hasComparable = true;
            if ((v['on'] == true) != s.rgbOn) return false;
          }
          break;
        default:
          return false;
      }
    }
    return hasComparable;
  }

  DateTime? _lastCmdSendAt;
  String? _lastCmdKey;
  DateTime? _ownerClaimHintUntil;

  Future<void> _autoEnableCloudLocalFlag({String reason = ''}) async {
    final now = DateTime.now();
    if (_cloudManualDisableUntil != null &&
        now.isBefore(_cloudManualDisableUntil!)) {
      debugPrint(
        '[CLOUD] auto-enable suppressed (manual disable lock) '
        'remainingMs=${_cloudManualDisableUntil!.difference(now).inMilliseconds}',
      );
      return;
    }
    if (_cloudUserEnabledLocal) return;
    _startCloudPreferWindow();
    try {
      final p = await SharedPreferences.getInstance();
      await _setCloudEnabledLocalForActiveDevice(true, prefs: p);
    } catch (_) {}
    if (mounted) setState(() {});
    debugPrint('[CLOUD] auto-enabled due to device policy reason=$reason');
  }

  Future<void> _cmdSendQueue = Future<void>.value();

  Future<void> _promoteProvisionedMdnsBaseInBackground(
    String host, {
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return;
    final fqdn = trimmed.endsWith('.local') ? trimmed : '$trimmed.local';
    final hostBase = 'http://$fqdn';
    try {
      if (await _probeInfoReachable(
        hostBase,
        timeout: const Duration(milliseconds: 900),
      )) {
        if (api.baseUrl != hostBase) {
          debugPrint('[BLE] mDNS host reachable in background -> $hostBase');
          await _applyProvisionedBaseUrl(hostBase, showSnack: false);
        }
        return;
      }
    } catch (_) {}

    try {
      final resolved = await _mdnsResolveHost(fqdn, timeout: timeout);
      if (resolved == null || resolved.isEmpty) return;
      final ipBase = 'http://$resolved';
      if (await _probeInfoReachable(
        hostBase,
        timeout: const Duration(milliseconds: 900),
      )) {
        if (api.baseUrl != hostBase) {
          debugPrint('[BLE] mDNS promoted after resolve -> $hostBase');
          await _applyProvisionedBaseUrl(hostBase, showSnack: false);
        }
        return;
      }
      if (await _probeInfoReachable(
        ipBase,
        timeout: const Duration(milliseconds: 900),
      )) {
        debugPrint(
          '[BLE] mDNS background resolved but keeping reachable IP base=$ipBase',
        );
      }
    } catch (e) {
      debugPrint('[BLE] mDNS background promotion skipped: $e');
    }
  }

  Future<String?> _discoverProvisionedMdnsIp({
    required String? mdnsHost,
    String? deviceId,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final host = (mdnsHost ?? '').trim();
    if (host.isNotEmpty) {
      final resolved = await _mdnsResolveHost(host, timeout: timeout);
      if (resolved != null && resolved.isNotEmpty) return resolved;
    }

    final id6 = (deviceId ?? _deviceId6ForMqtt() ?? '').trim();
    if (id6.isEmpty) return null;
    final mdnsHostPrefix = mdnsHostForId6(
      id6,
      rawIdHint: _activeDeviceId ?? id6,
    );
    return mdns.mdnsFindByService(
      service: '_http._tcp',
      namePrefix: mdnsHostPrefix,
      nameContains: id6,
      timeout: timeout,
    );
  }

  Future<bool> _awaitProvisionedDeviceReady({
    String? ip,
    String? mdnsHost,
    String? deviceId,
    Duration total = const Duration(seconds: 75),
  }) async {
    _allowNetworkAutoPolling();
    final deadline = DateTime.now().add(total);
    var primaryIp = (ip ?? '').trim();
    if (primaryIp.isEmpty || primaryIp == '0.0.0.0') {
      primaryIp = '';
    }
    var attempt = 0;
    var mdnsPromoted = false;
    var unauthorizedHits = 0;

    while (DateTime.now().isBefore(deadline)) {
      attempt += 1;
      _setBlockingProgress(
        title: t.t('please_wait'),
        body: attempt <= 2
            ? t.t('onb_wait_device_wifi')
            : t.t('onb_wait_device_discovery'),
      );

      final candidateBases = <String>{};
      final id6 = (deviceId ?? _deviceId6ForMqtt() ?? '').trim();
      if (primaryIp.isNotEmpty) {
        candidateBases.add('http://$primaryIp');
      }
      final lastIp = _getActiveDeviceLastIp();
      if (lastIp != null && lastIp.isNotEmpty) {
        candidateBases.add('http://$lastIp');
      }
      final mdnsHostTrimmed = (mdnsHost ?? '').trim();
      if (mdnsHostTrimmed.isNotEmpty) {
        final fqdn = mdnsHostTrimmed.endsWith('.local')
            ? mdnsHostTrimmed
            : '$mdnsHostTrimmed.local';
        candidateBases.add('http://$fqdn');
      }
      if (id6.isNotEmpty) {
        final mdnsHost = mdnsHostForId6(id6, rawIdHint: _activeDeviceId ?? id6);
        if (mdnsHost.isNotEmpty) {
          candidateBases.add('http://$mdnsHost.local');
        }
      }
      final currentBase = api.baseUrl.trim();
      if (currentBase.isNotEmpty &&
          !(Uri.tryParse(currentBase)?.host == '192.168.4.1')) {
        candidateBases.add(currentBase);
      }

      for (final base in candidateBases) {
        try {
          if (api.baseUrl != base) {
            await _applyProvisionedBaseUrl(base, showSnack: false);
          }
          final reachable = await api.testConnection();
          if (reachable) {
            final s =
                await _fetchStateSmart(force: true) ?? await api.fetchState();
            if (s == null) {
              if ((api.lastErrCode ?? '').toLowerCase() == 'unauthorized') {
                unauthorizedHits++;
                debugPrint(
                  '[BLE] local-ready unauthorized hit=$unauthorizedHits base=${api.baseUrl}',
                );
                if (unauthorizedHits >= 3) {
                  // Do not accept unauthorized as provisioning success.
                  await api.ensureOwnerSession();
                  debugPrint(
                    '[BLE] local-ready unauthorized persisted; waiting for authenticated readiness',
                  );
                }
              }
              continue;
            }
            unauthorizedHits = 0;
            if (!mounted) return true;
            setState(() {
              connected = true;
              _lastUpdate = DateTime.now();
              state = s;
              _syncAutoHumControlsFromState(s);
            });
            _lastLocalOkAt = DateTime.now();
            _localDnsFailUntil = null;
            _localUnreachableUntil = null;
            if (mdnsHost != null &&
                mdnsHost.trim().isNotEmpty &&
                !mdnsPromoted) {
              mdnsPromoted = true;
              unawaited(
                _promoteProvisionedMdnsBaseInBackground(
                  mdnsHost,
                  timeout: const Duration(seconds: 2),
                ),
              );
            }
            return true;
          }
        } catch (e) {
          if (_looksLikeDnsLookupFailure(e) &&
              !_baseHostLooksLikeIpv4(api.baseUrl)) {
            _markLocalDnsFailure();
          } else if (_looksLikeLocalUnreachable(e)) {
            _markLocalUnreachable();
          }
          unauthorizedHits = 0;
        }
      }

      if (attempt == 1 &&
          mdnsHost != null &&
          mdnsHost.trim().isNotEmpty &&
          !mdnsPromoted) {
        mdnsPromoted = true;
        unawaited(
          _promoteProvisionedMdnsBaseInBackground(
            mdnsHost,
            timeout: const Duration(seconds: 2),
          ),
        );
      }

      if (attempt % 2 == 0) {
        final discoveredIp = await _discoverProvisionedMdnsIp(
          mdnsHost: mdnsHost,
          deviceId: deviceId,
          timeout: const Duration(seconds: 2),
        );
        if (discoveredIp != null && discoveredIp.isNotEmpty) {
          primaryIp = discoveredIp;
          await _updateActiveDeviceLastIp(discoveredIp);
          final discoveredBase = 'http://$discoveredIp';
          try {
            if (await _probeInfoReachable(
              discoveredBase,
              timeout: const Duration(milliseconds: 1200),
            )) {
              await _applyProvisionedBaseUrl(discoveredBase, showSnack: false);
            }
          } catch (_) {}
        }
      }

      await Future<void>.delayed(const Duration(seconds: 1));
    }

    return false;
  }

  final _BleJsonFramer _bleProvJsonFramer = _BleJsonFramer();

  @override
  void initState() {
    super.initState();
    // Moved to _initPrefs to ensure api is initialized first
    api = ApiService(baseUrl);
    cloudApi = CloudApiService(_cloudApiBase);
    _fanSpinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _urlCtl = TextEditingController(text: baseUrl);
    _cloudUrlCtl = TextEditingController(text: _cloudApiBase);
    _cloudEmailCtl = TextEditingController();
    _appliedStartMin = [];
    _loadWeather();
    _initPrefs();
    unawaited(_refreshOwnerFromCloud());
  }

  Future<void> _initPrefs() async {
    final p = await SharedPreferences.getInstance();
    final hadDevicesPref = (p.getString('devices') ?? '').trim().isNotEmpty;
    final hasLegacySetupData =
        (p.getString('baseUrl') ?? '').trim().isNotEmpty ||
        (p.getString('pair_token') ?? '').trim().isNotEmpty ||
        (p.getString('active_device_id') ?? '').trim().isNotEmpty;
    final freshInstallCandidate = !hadDevicesPref && !hasLegacySetupData;
    await _wipeSecureStorageOnFreshInstall(
      prefs: p,
      freshInstallCandidate: freshInstallCandidate,
    );
    await _initDevices(p);
    final onboardingDone = p.getBool(kOnboardingV1DoneKey) == true;
    if (freshInstallCandidate && !onboardingDone && mounted) {
      setState(() => _onboardingPreparing = true);
      unawaited(
        _maybeRunFirstLaunchOnboarding(
          freshInstallCandidate: freshInstallCandidate,
        ),
      );
    }
    _showAdvancedSettings = p.getBool(kUiAdvancedSettingsKey) ?? false;
    // Cloud API base is fixed; remove any stored override to avoid confusion.
    await p.remove('cloudApiBase');
    _cloudApiBase = kDefaultCloudApiBase;
    _cloudUserEnabledLocal = _activeDevice?.cloudEnabledLocal ?? false;
    await p.remove('cloudEnabledLocal');
    cloudApi = CloudApiService(_cloudApiBase);
    _cloudUrlCtl.text = _cloudApiBase;
    await _loadCloudAuth();
    if (_cloudUserEmail != null) {
      _cloudEmailCtl.text = _cloudUserEmail!;
    }
    if (_shouldAutoStartConnectivity()) {
      _allowNetworkAutoPolling();
    }
    unawaited(_bootstrapCloudSessionOnStartup());
    // Load saved WAQI location(s)
    try {
      WaqiLocation? legacyWaqiLocation;
      final locStr = p.getString('waqi_location');
      if (locStr != null && locStr.isNotEmpty) {
        final obj = jsonDecode(locStr);
        if (obj is Map<String, dynamic>) {
          legacyWaqiLocation = WaqiLocation.fromJson(obj);
        }
      }
      final recentStr = p.getString('waqi_recent_locations');
      if (recentStr != null && recentStr.isNotEmpty) {
        final arr = jsonDecode(recentStr);
        if (arr is List) {
          _waqiRecent = arr
              .whereType<Map>()
              .map<WaqiLocation>(
                (e) => WaqiLocation.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList();
        }
      }
      // Device-scoped WAQI migration from old global key.
      final active = _activeDevice;
      if (legacyWaqiLocation != null && active != null) {
        final hasDeviceWaqi =
            active.waqiLat != null &&
            active.waqiLon != null &&
            (active.waqiName ?? '').trim().isNotEmpty;
        if (!hasDeviceWaqi) {
          active.waqiName = legacyWaqiLocation.name;
          active.waqiLat = legacyWaqiLocation.lat;
          active.waqiLon = legacyWaqiLocation.lon;
          await _saveDevicesToPrefs(p);
        }
      }
      final activeWaqiReady =
          active?.waqiLat != null &&
          active?.waqiLon != null &&
          (active?.waqiName ?? '').trim().isNotEmpty;
      _waqiLocation = activeWaqiReady
          ? WaqiLocation(
              name: active!.waqiName!.trim(),
              lat: active.waqiLat!,
              lon: active.waqiLon!,
            )
          : legacyWaqiLocation;
    } catch (e) {
      debugPrint('[INIT] waqi prefs parse error: $e');
    }
    if (kDebugMode && kDebugAutoNetOptIn) {
      _allowNetworkAutoPolling();
    }
    // Kullanıcı tema seçmemişse, aktif cihaza göre varsayılanı uygula.
    // Doa -> light, generic/default -> dark.
    // Kullanıcı değişiklik yapmışsa marka bazlı kaydı yükle.
    final brand = _activeDevice?.brand ?? kDefaultDeviceBrand;
    final themeKey = _themeModeKeyForBrand(brand);
    final themeUserKey = _themeUserSetKeyForBrand(brand);
    final themeStr = p.getString(themeKey);
    _themeUserSet = p.getBool(themeUserKey) ?? false;
    if (!_themeUserSet) {
      final ThemeMode mode = brand == kDoaDeviceBrand
          ? ThemeMode.light
          : ThemeMode.dark;
      widget.onThemeChanged(mode);
    } else if (themeStr != null) {
      final ThemeMode mode = themeStr == 'light'
          ? ThemeMode.light
          : ThemeMode.dark;
      widget.onThemeChanged(mode);
    }

    // Owner keypair (private key) may not exist on this phone; don't auto-generate
    // because it would never match an already-owned device.
    await _ensureOwnerKeypair(generateIfMissing: false);
    // Client keypair is per-app-install and used for invited USER access and
    // for frictionless reconnect without sending QR secrets again.
    await _ensureClientKeypair(generateIfMissing: true);
    // Owned cihazlarda local LAN/HTTP kontrolü için imza anahtarı gerekir.
    api.setSigningKey(_ownerPrivD32 ?? _clientPrivD32);

    api.setApSessionToken(_apSessionToken);
    api.setApSessionNonce(_apSessionNonce);

    // AP keşfini arka plana al; init'i bloklamasın.
    unawaited(
      _ensureLocalBaseFromApPortal(
        total: const Duration(seconds: 6),
        step: const Duration(seconds: 1),
      ),
    );
    // Hızlı AP probe: telefonda cihaz AP'si açıksa baseUrl'i hemen 192.168.4.1'e al.
    await _maybeSwitchToApBaseUrlIfReachable();

    DeviceState? st = await _fetchStateSmart();
    if (st != null) {
      if (mounted) {
        setState(() {
          state = st;
          _syncAutoHumControlsFromState(st);
          connected = true;
          _lastUpdate = DateTime.now();
          _pushHistorySample(st);
        });
      } else {
        state = st;
        _syncAutoHumControlsFromState(st);
        connected = true;
        _lastUpdate = DateTime.now();
        _pushHistorySample(st);
      }
      _cacheActiveRuntimeHealth(localOk: true);
      // Planner durumunu da çekmeye çalış (yetki gerektirmiyor)
      // Only try local planner fetch when we're actually on a reachable local/AP base.
      if (!_localDnsFailActive && !_localUnreachableActive) {
        try {
          final r = await http
              .get(
                Uri.parse('${api.baseUrl}/api/status'),
                headers: api.authHeaders(),
              )
              .timeout(kLocalHttpRequestTimeout);
          if (r.statusCode == 200) {
            final decoded = jsonDecode(r.body);
            if (decoded is! Map<String, dynamic>) return;
            final j = decoded;
            final arr = (j['plans'] as List?) ?? [];
            _plans = arr
                .map((e) => _PlanItem.fromJson(e as Map<String, dynamic>))
                .toList();
            _appliedStartMin = List<int>.filled(_plans.length, -1);
            final core = _extractStateCore(j);
            setState(() {
              state = DeviceState.fromJson(core);
              _syncAutoHumControlsFromState(state!);
            });
          }
        } catch (_) {}
      }
    }

    if (st == null) {
      final plansStr = p.getString('plans');
      debugPrint(
        '[PLANNER] st==null, loading local plans: ${plansStr ?? 'null'}',
      );
      if (plansStr != null && plansStr.isNotEmpty) {
        try {
          final arr = (jsonDecode(plansStr) as List)
              .cast<Map<String, dynamic>>();
          _plans = arr.map((e) => _PlanItem.fromJson(e)).toList();
          _appliedStartMin = List<int>.filled(_plans.length, -1);
        } catch (e) {
          debugPrint('[PLANNER] failed to parse saved plans: $e');
          _appliedStartMin = [];
        }
      } else {
        _appliedStartMin = [];
      }
    }

    if (_appliedStartMin.length != _plans.length) {
      _appliedStartMin = List<int>.filled(_plans.length, -1);
    }
    lastFilterMsg = p.getString('filterMsg');

    // Her durumda periyodik HTTP polling'i başlat
    _startPolling();
    if (_shouldAutoStartConnectivity()) {
      unawaited(_connectionTick(force: true));
    }
  }

  Future<void> _wipeSecureStorageOnFreshInstall({
    required SharedPreferences prefs,
    required bool freshInstallCandidate,
  }) async {
    if (!freshInstallCandidate) return;
    final alreadyWiped = prefs.getBool('fresh_install_secure_wiped') ?? false;
    if (alreadyWiped) return;
    try {
      // Fresh install'de stale token/session verilerini temizle;
      // owner/client keypair'i KORU ki mevcut owned cihazlarda imza doğrulaması bozulmasın.
      final all = await _secureStorage.readAll();
      for (final key in all.keys) {
        final keep =
            key == _ownerPrivD32Key ||
            key == _ownerPubQ65Key ||
            key == _clientPrivD32Key ||
            key == _clientPubQ65Key;
        if (keep) continue;
        final isVolatile =
            key.startsWith('pair_token') ||
            key.startsWith('ble_setup_') ||
            key == 'cloud_id_token' ||
            key == 'cloud_refresh_token' ||
            key == 'cloud_user_email' ||
            key == 'cloud_token_exp' ||
            key.startsWith('ap_session');
        if (!isVolatile) continue;
        await _secureStorage.delete(key: key);
      }
      _cloudIdToken = null;
      _cloudRefreshToken = null;
      _cloudTokenExp = null;
      _cloudUserEmail = null;
      _apSessionToken = null;
      _apSessionNonce = null;
      await prefs.setBool('fresh_install_secure_wiped', true);
      debugPrint(
        '[INIT] fresh install detected -> secure storage pruned (keys preserved)',
      );
    } catch (e) {
      debugPrint('[INIT] secure storage wipe failed: $e');
    }
  }

  _SavedDevice? get _activeDevice {
    if (_devices.isEmpty) return null;
    if (_activeDeviceId == null) return null;
    final found = _devices
        .where((d) => d.id == _activeDeviceId)
        .toList(growable: false);
    if (found.isEmpty) return null;
    return found.first;
  }

  bool get _isDoaDevice {
    final productSlug = _canonicalDeviceProductSlug(state?.deviceProduct ?? '');
    if (productSlug == 'doa') return true;
    return _activeDevice?.brand == kDoaDeviceBrand;
  }

  String _activeDeviceTitleText() {
    final dev = _activeDevice;
    final runtimeBrand = brandFromDeviceProduct(
      state?.deviceProduct ?? '',
    ).trim();
    if (dev == null) {
      if (runtimeBrand.isNotEmpty) return runtimeBrand;
      return t.t('title');
    }
    final storedBrand = dev.brand.trim();
    final shouldPreferRuntimeBrand =
        runtimeBrand.isNotEmpty &&
        !isDefaultDeviceBrand(runtimeBrand) &&
        (storedBrand.isEmpty || isDefaultDeviceBrand(storedBrand));
    if (shouldPreferRuntimeBrand) {
      final suffix = dev.suffix.trim();
      if (suffix.isEmpty) return runtimeBrand;
      return '$runtimeBrand $suffix';
    }
    return dev.displayName;
  }

  Future<bool> _verifyAdvancedSettingsPassword() async {
    final id6 =
        _deviceId6ForMqtt() ??
        _normalizeDeviceId6(_activeDevice?.id ?? _activeDeviceId ?? '');
    if (id6 == null || id6.isEmpty) {
      _showSnack('Chip ID bulunamadi. Once cihazi secin.');
      return false;
    }
    final expected = '*$id6';
    final ctl = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Gelistirici sifresi'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '*chipid',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Iptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
              child: const Text('Onayla'),
            ),
          ],
        );
      },
    );
    if (input == null || input.isEmpty) return false;
    if (input == expected) return true;
    _showSnack('Sifre yanlis.');
    return false;
  }

  @override
  void dispose() {
    _fanSpinCtrl.dispose();
    _poller?.cancel();
    _urlCtl.dispose();
    try {
      _bleCtrlNotifySub?.cancel();
    } catch (_) {}
    _bleCtrlNotifySub = null;
    try {
      _bleCtrlConnSub?.cancel();
    } catch (_) {}
    _bleCtrlConnSub = null;
    try {
      _bleCtrlStatusTimer?.cancel();
    } catch (_) {}
    _bleCtrlStatusTimer = null;
    try {
      unawaited(
        safeBleDisconnect(_bleCtrlDevice, reason: 'dispose_ble_control'),
      );
    } catch (_) {}
    _bleCtrlDevice = null;
    _bleCtrlInfoChar = null;
    _bleCtrlCmdChar = null;
    _bleControlMode = false;
    super.dispose();
  }

  bool get _isMasterOn => state?.masterOn ?? false;
  // Master kapalıyken tüm kontroller pasif olmalı (istek gereği)
  bool get _isActive => _canControlDevice && _isMasterOn;

  // --- Small helpers for UI
  Widget _dot(Color c) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  /// Collapsible & compact RGB swatch palette
  Widget _rgbPalette(DeviceState? s) {
    final current = Color.fromARGB(255, s?.r ?? 0, s?.g ?? 0, s?.b ?? 0);
    final int currentBr = _rgbBrightnessDraft ?? (s?.rgbBrightness ?? 100);
    final bool rgbEnabled = _isActive && (s?.rgbOn ?? false);
    final swatches = <Color>[
      Colors.white,
      const Color(0xFFFFE6CC),
      const Color.fromARGB(255, 255, 0, 0),
      Colors.orange,
      Colors.amber,
      Colors.yellow,
      Colors.lime,
      const Color.fromARGB(255, 0, 255, 0),
      Colors.teal,
      Colors.cyan,
      const Color.fromARGB(255, 0, 0, 255),
      Colors.indigo,
      Colors.purple,
      Colors.pink,
    ];

    Widget dot(Color c, {bool selected = false}) => Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.black12,
          width: selected ? 2 : 1,
        ),
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: ExpansionTile(
          initiallyExpanded: _rgbExpanded,
          onExpansionChanged: (v) => setState(() => _rgbExpanded = v),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Row(
            children: [
              dot(current, selected: true),
              const SizedBox(width: 10),
              Text(
                t.t('flame'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                'R:${(current.r * 255.0).round() & 0xff} '
                'G:${(current.g * 255.0).round() & 0xff} '
                'B:${(current.b * 255.0).round() & 0xff}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          children: [
            const SizedBox(height: 6),
            IgnorePointer(
              ignoring: !rgbEnabled,
              child: Opacity(
                opacity: rgbEnabled ? 1.0 : 0.35,
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: swatches.map((c) {
                        final isSel =
                            ((c.r * 255.0).round() & 0xff) ==
                                ((current.r * 255.0).round() & 0xff) &&
                            ((c.g * 255.0).round() & 0xff) ==
                                ((current.g * 255.0).round() & 0xff) &&
                            ((c.b * 255.0).round() & 0xff) ==
                                ((current.b * 255.0).round() & 0xff);
                        return InkWell(
                          onTap: _isActive
                              ? () => _send({
                                  'rgb': {
                                    'on': true,
                                    'r': (c.r * 255.0).round() & 0xff,
                                    'g': (c.g * 255.0).round() & 0xff,
                                    'b': (c.b * 255.0).round() & 0xff,
                                  },
                                })
                              : null,
                          child: dot(c, selected: isSel),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.light_mode_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Slider(
                              value: currentBr.toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '${currentBr.round()}%',
                              onChanged: _isActive
                                  ? (v) => setState(
                                      () => _rgbBrightnessDraft = v.round(),
                                    )
                                  : null,
                              onChangeEnd: _isActive
                                  ? (v) {
                                      final next = v.round();
                                      setState(
                                        () => _rgbBrightnessDraft = next,
                                      );
                                      _send({
                                        'rgb': {'on': true, 'brightness': next},
                                      });
                                    }
                                  : null,
                            ),
                          ),
                          Text('${currentBr.round()}%'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('3000K'),
                          avatar: const CircleAvatar(
                            backgroundColor: Color.fromARGB(255, 255, 180, 107),
                          ),
                          onPressed: _isActive
                              ? () => _send({
                                  'rgb': {
                                    'on': true,
                                    'r': 255,
                                    'g': 180,
                                    'b': 107,
                                  },
                                })
                              : null,
                        ),
                        ActionChip(
                          label: const Text('4000K'),
                          avatar: const CircleAvatar(
                            backgroundColor: Color.fromARGB(255, 255, 209, 163),
                          ),
                          onPressed: _isActive
                              ? () => _send({
                                  'rgb': {
                                    'on': true,
                                    'r': 255,
                                    'g': 209,
                                    'b': 163,
                                  },
                                })
                              : null,
                        ),
                        ActionChip(
                          label: const Text('5000K'),
                          avatar: const CircleAvatar(
                            backgroundColor: Color.fromARGB(255, 255, 228, 206),
                          ),
                          onPressed: _isActive
                              ? () => _send({
                                  'rgb': {
                                    'on': true,
                                    'r': 255,
                                    'g': 228,
                                    'b': 206,
                                  },
                                })
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            InkWell(
              onTap: () =>
                  _openDevicePicker(autoStartProvisionOnNewDevice: true),
              borderRadius: BorderRadius.circular(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_activeDeviceTitleText()),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _dot(_canControlDevice ? Colors.green : Colors.red),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Provisioning',
            onPressed: _showProvisioningDialog,
            icon: const Icon(Icons.security_update_good),
          ),
          IconButton(
            tooltip: 'Wi‑Fi Tara (BLE)',
            onPressed: _bleSsidPicker,
            icon: const Icon(Icons.wifi_find),
          ),
          IconButton(
            tooltip: t.t('ota_check'),
            onPressed: _checkOtaNow,
            icon: const Icon(Icons.system_update),
          ),
          IconButton(
            tooltip: t.t('refresh'),
            onPressed: () async {
              // User explicitly requested refresh: try to recover any channel in priority order.
              unawaited(_connectionTick(force: true));
              final canForceBle =
                  state?.pairingWindowActive == true ||
                  state?.softRecoveryActive == true ||
                  state?.apSessionActive == true;
              unawaited(_autoConnectBleIfNeeded(force: canForceBle));
              final st = await _fetchStateSmart();
              if (!mounted) return;
              if (st != null) {
                setState(() {
                  state = st;
                  _syncAutoHumControlsFromState(st);
                  connected = true;
                  _lastUpdate = DateTime.now();
                  _pushHistorySample(st);
                });
              } else {
                if (!_shouldKeepConnectedOnNullState()) {
                  setState(() => connected = false);
                  _showSnack(t.t('reachable_no'));
                }
              }
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _tab,
            children: [
              _buildDashboard(),
              _buildSensors(),
              _buildPlanner(),
              _buildSettings(),
            ],
          ),
          if (_onboardingPreparing)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.18),
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.8),
                          ),
                          SizedBox(height: 10),
                          Text('Kurulum hazırlanıyor...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_blockingProgressVisible)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.24),
                child: Center(
                  child: Card(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.8,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _blockingProgressTitle ?? t.t('please_wait'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if ((_blockingProgressBody ?? '').trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _blockingProgressBody!,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            label: t.t('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.sensors),
            label: t.t('sensors'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.schedule),
            label: t.t('planner'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings),
            label: t.t('settings'),
          ),
        ],
      ),
    );
  }

  // Removed misplaced debugPrint for _buildDashboard
  Widget _buildDashboard() => _buildDashboardImpl();

  Widget _buildSensors() => _buildSensorsImpl();

  Widget _buildWaqiCard() => _buildWaqiCardImpl();

  Widget _buildHomeHeader() => _buildHomeHeaderImpl();

  Widget _buildHomeInsight(DeviceState? st) => _buildHomeInsightImpl(st);

  Widget _buildHomeTrendStrip() => _buildHomeTrendStripImpl();

  Widget _buildToggleTileNew({
    required String label,
    String? subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    IconData? icon,
    bool boldTitle = false,
  }) => _buildToggleTileNewImpl(
    label: label,
    subtitle: subtitle,
    value: value,
    enabled: enabled,
    onChanged: onChanged,
    icon: icon,
    boldTitle: boldTitle,
  );

  Widget _buildFanCleanTile(DeviceState st, bool canControl) =>
      _buildFanCleanTileImpl(st, canControl);

  Widget _buildFrameLightTile(DeviceState? st, bool canControl) =>
      _buildFrameLightTileImpl(st, canControl);

  Widget _buildHomeToggles() => _buildHomeTogglesImpl();

  Widget _buildHomeTab() => _buildHomeTabImpl();

  Widget _buildPlanner() => _buildPlannerImpl();

  Widget _buildAutoHumidityTile() => _buildAutoHumidityTileImpl();

  String _fmtTod(TimeOfDay t) => _fmtTodImpl(t);
  Widget _buildSettings() => _buildSettingsImpl();

  /// DeviceId değerini direkt alıp _activeDeviceId'ye set et
  /// Güvenli string prefix helper - null ve kısa string'leri handle eder
  String safePrefix(String? s, int len) {
    if (s == null || s.isEmpty) return '(empty)';
    if (s.length <= len) return s;
    return '${s.substring(0, len)}...';
  }

  Future<void> _updateActiveDeviceIdFromApiValue(String apiDeviceId) async {
    final canonicalId = canonicalizeDeviceId(apiDeviceId);
    if (canonicalId == null ||
        canonicalId.isEmpty ||
        canonicalId.startsWith('dev_')) {
      return; // Geçerli device ID değil
    }

    final currentActive = _activeDeviceId?.trim();
    final currentCanonical = (currentActive == null || currentActive.isEmpty)
        ? ''
        : (canonicalizeDeviceId(currentActive) ?? '');
    final canPromoteActiveId =
        currentActive == null ||
        currentActive.isEmpty ||
        _isPlaceholderDeviceId(currentActive) ||
        (currentCanonical.isNotEmpty && currentCanonical == canonicalId);
    debugPrint(
      '[STATE] API deviceId bulundu: $canonicalId, active=$currentActive promote=$canPromoteActiveId',
    );
    if (canPromoteActiveId) {
      _moveRuntimeContext(_activeDeviceId, canonicalId);
    }

    // Eski placeholder/local kaydı canonical cloud kimliğine taşırken
    // kullanıcı verdiği görünen adı ve local baseUrl'yi koru.
    _SavedDevice? previousDevice;
    final activeCanonical = _activeDeviceId != null
        ? (canonicalizeDeviceId(_activeDeviceId!) ?? '')
        : '';
    if (_activeDeviceId != null && _activeDeviceId != canonicalId) {
      final oldDevice =
          (_isPlaceholderDeviceId(_activeDeviceId)
              ? _firstWhereOrNull<_SavedDevice>(
                  _devices,
                  (d) => d.id == _activeDeviceId,
                )
              : null) ??
          (activeCanonical.isNotEmpty
              ? _firstWhereOrNull<_SavedDevice>(
                  _devices,
                  (d) => canonicalizeDeviceId(d.id) == activeCanonical,
                )
              : null) ??
          _SavedDevice(
            id: _activeDeviceId!,
            brand: kDefaultDeviceBrand,
            baseUrl: api.baseUrl,
          );
      previousDevice = oldDevice;
    }

    _promotePlaceholderDeviceToCanonical(
      canonicalId: canonicalId,
      preferredPlaceholderId: previousDevice?.id ?? _activeDeviceId,
      brandHint: previousDevice?.brand,
      suffixHint: previousDevice?.suffix,
      baseUrlHint: previousDevice?.baseUrl ?? api.baseUrl,
    );

    final existingIndex = _devices.indexWhere(
      (d) => canonicalizeDeviceId(d.id) == canonicalId,
    );
    late _SavedDevice device;
    if (existingIndex >= 0) {
      device = _devices[existingIndex];
      if (previousDevice != null) {
        final prev = previousDevice;
        if (device.suffix.trim().isEmpty && prev.suffix.trim().isNotEmpty) {
          device.suffix = prev.suffix;
        }
        if ((device.brand.trim().isEmpty ||
                isDefaultDeviceBrand(device.brand.trim())) &&
            prev.brand.trim().isNotEmpty) {
          device.brand = prev.brand;
        }
        if ((device.baseUrl.trim().isEmpty ||
                device.baseUrl.trim() == 'http://192.168.4.1') &&
            prev.baseUrl.trim().isNotEmpty) {
          device.baseUrl = _normalizedStoredBaseForDevice(device, prev.baseUrl);
        }
        device.lastIp ??= prev.lastIp;
        device.thingName ??= prev.thingName ?? thingNameFromAny(canonicalId);
        device.mdnsHost ??= prev.mdnsHost ?? mdnsHostFromAny(canonicalId);
        device.cloudLinked = device.cloudLinked || prev.cloudLinked;
        device.cloudRole ??= prev.cloudRole;
        device.cloudSource ??= prev.cloudSource;
      }
    } else {
      device = _SavedDevice(
        id: canonicalId,
        brand: previousDevice?.brand.trim().isNotEmpty == true
            ? previousDevice!.brand
            : kDefaultDeviceBrand,
        suffix: previousDevice?.suffix ?? '',
        baseUrl: previousDevice?.baseUrl.trim().isNotEmpty == true
            ? previousDevice!.baseUrl
            : api.baseUrl,
        lastIp: previousDevice?.lastIp,
        thingName: previousDevice?.thingName ?? thingNameFromAny(canonicalId),
        mdnsHost: previousDevice?.mdnsHost ?? mdnsHostFromAny(canonicalId),
        pairToken: null,
        cloudLinked: previousDevice?.cloudLinked ?? false,
        cloudRole: previousDevice?.cloudRole,
        cloudSource: previousDevice?.cloudSource,
        doaWaterDurationMin: previousDevice?.doaWaterDurationMin,
        doaWaterIntervalHr: previousDevice?.doaWaterIntervalHr,
        doaWaterAutoEnabled: previousDevice?.doaWaterAutoEnabled,
      );
      _devices.add(device);
    }

    if (previousDevice != null &&
        previousDevice.id != device.id &&
        _devices.any((d) => identical(d, previousDevice))) {
      _devices.removeWhere((d) => identical(d, previousDevice));
    }

    device.baseUrl = _normalizedStoredBaseForDevice(device, device.baseUrl);

    // Preserve pair token when active device id is promoted from a placeholder
    // (e.g. dev_* -> aac-xxxxxx). Losing this token causes cloud claim to fail
    // with claim_proof_required and blocks automatic re-link.
    String? migratedPairToken = device.pairToken?.trim();
    if (migratedPairToken == null || migratedPairToken.isEmpty) {
      final fromPrev = previousDevice?.pairToken?.trim() ?? '';
      if (fromPrev.isNotEmpty) {
        migratedPairToken = fromPrev;
      } else if (previousDevice != null &&
          previousDevice.id.trim().isNotEmpty) {
        final storedPrev =
            (await _loadPairToken(previousDevice.id))?.trim() ?? '';
        if (storedPrev.isNotEmpty) migratedPairToken = storedPrev;
      }
    }
    if ((migratedPairToken == null || migratedPairToken.isEmpty) &&
        canonicalId.isNotEmpty) {
      final storedCanonical = (await _loadPairToken(canonicalId))?.trim() ?? '';
      if (storedCanonical.isNotEmpty) migratedPairToken = storedCanonical;
    }
    if (migratedPairToken != null && migratedPairToken.isNotEmpty) {
      device.pairToken = migratedPairToken;
      api.setPairToken(migratedPairToken);
      await _persistPairToken(migratedPairToken, deviceListId: canonicalId);
      debugPrint(
        '[QR][PAIR] migrated pair token during id promote -> $canonicalId len=${migratedPairToken.length}',
      );
    }

    _normalizeSavedDeviceInventory();

    // Aktif cihazı sadece placeholder/aynı-cihaz kanonikleştirme durumunda güncelle.
    if (canPromoteActiveId) {
      _activeDeviceId = canonicalId;
      _activeDeviceSwitchEpoch++;
    }
    await _saveDevicesToPrefs();

    debugPrint('[STATE] _activeDeviceId güncellendi: $_activeDeviceId');
    debugPrint('[STATE] _activeCanonicalDeviceId: $_activeCanonicalDeviceId');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    final localized = t.literal(msg);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(localized)));
  }

  // Extension part dosyalarından setState çağrılarını tek noktadan güvenli yapar.
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }
}
